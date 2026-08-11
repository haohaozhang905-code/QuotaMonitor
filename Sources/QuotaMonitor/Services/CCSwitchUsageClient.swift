import Foundation
import AppKit
import SQLite3

/// cc-switch 本地数据库的单日聚合结果。
struct CCSwitchDailyUsage: Sendable {
    let all: [DailyTokenUsage]
    let deepSeek: [DailyTokenUsage]
}

/// 从 cc-switch 的请求日志读取 Claude / Claude 桌面版 token 用量。
///
/// 数据来源：`~/.cc-switch/cc-switch.db` 的 `proxy_request_logs` 表，
/// 每行一次请求：app_type / model / input / output / cache_read /
/// cache_creation / created_at（epoch 毫秒）。cc-switch 为 Claude 桌面版
/// 的本地代理捕获，这是桌面版唯一可用的用量来源。
///
/// 统一口径：input = input_tokens + cache_read + cache_creation（cc-switch
/// 的 input_tokens 不含缓存），cachedInput 单独列示。
actor CCSwitchUsageClient {
    /// SQLite 的 C 宏 `SQLITE_TRANSIENT` 在 Swift 中没有直接导入。
    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private struct Row {
        let model: String
        let inputTokens: Int
        let outputTokens: Int
        let cacheReadTokens: Int
        let cacheCreationTokens: Int
        /// cc-switch 的 created_at 是 epoch 秒（与 sessions 表的毫秒不同）。
        let createdAt: Int64
    }

    private let dbURL: URL

    init(dbURL: URL? = nil) {
        self.dbURL = dbURL ?? Self.defaultDBURL()
    }

    func fetch(appType: String) -> CCSwitchDailyUsage? {
        guard let rows = queryRows(appType: appType) else { return nil }
        var allByDay: [String: TokenTotals] = [:]
        var deepSeekByDay: [String: TokenTotals] = [:]

        for row in rows {
            let dayKey = DailyTokenUsage.dayKey(
                for: Date(timeIntervalSince1970: Double(row.createdAt))
            )
            var totals = TokenTotals()
            totals.input = row.inputTokens + row.cacheReadTokens + row.cacheCreationTokens
            totals.cachedInput = row.cacheReadTokens
            totals.cacheWriteInput = row.cacheCreationTokens
            totals.output = row.outputTokens

            allByDay[dayKey, default: TokenTotals()] = allByDay[dayKey, default: TokenTotals()].adding(totals)
            if row.model.lowercased().contains("deepseek") {
                deepSeekByDay[dayKey, default: TokenTotals()] = deepSeekByDay[dayKey, default: TokenTotals()].adding(totals)
            }
        }

        return CCSwitchDailyUsage(
            all: makeUsage(byDay: allByDay),
            deepSeek: makeUsage(byDay: deepSeekByDay)
        )
    }

    func fetchBuckets(appType: String, client: TokenClient = .desktop) -> [TokenUsageBucket]? {
        guard let rows = queryRows(appType: appType) else { return nil }
        let buckets = rows.map { row -> TokenUsageBucket in
            var totals = TokenTotals()
            totals.input = row.inputTokens + row.cacheReadTokens + row.cacheCreationTokens
            totals.cachedInput = row.cacheReadTokens
            totals.cacheWriteInput = row.cacheCreationTokens
            totals.output = row.outputTokens
            let model = row.model.isEmpty ? "unknown" : row.model
            return TokenUsageBucket(
                bucketStart: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: Double(row.createdAt))),
                platform: .claude,
                client: client,
                model: model,
                provider: model.lowercased().contains("deepseek") ? .deepseek : .official,
                totals: totals
            )
        }
        return TokenUsageBucket.combining(buckets)
    }

    private func makeUsage(byDay: [String: TokenTotals]) -> [DailyTokenUsage] {
        byDay.map { key, totals in
            DailyTokenUsage(day: Self.day(from: key), totals: totals)
        }
        .sorted { $0.day < $1.day }
    }

    private func queryRows(appType: String) -> [Row]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)

        let sql = """
        SELECT app_type, model, input_tokens, output_tokens, cache_read_tokens, \
        cache_creation_tokens, created_at FROM proxy_request_logs WHERE app_type = ?1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, appType, -1, Self.sqliteTransient)

        var rows: [Row] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                guard let modelC = sqlite3_column_text(statement, 1) else { continue }
                rows.append(Row(
                    model: String(cString: modelC),
                    inputTokens: Int(sqlite3_column_int64(statement, 2)),
                    outputTokens: Int(sqlite3_column_int64(statement, 3)),
                    cacheReadTokens: Int(sqlite3_column_int64(statement, 4)),
                    cacheCreationTokens: Int(sqlite3_column_int64(statement, 5)),
                    createdAt: sqlite3_column_int64(statement, 6)
                ))
                if rows.count >= 500_000 { break }
            } else if step == SQLITE_DONE {
                break
            } else {
                return nil
            }
        }
        return rows
    }

    /// 数据库文件最近修改时间；QuotaStore 用它判断 cc-switch 是否仍在写入。
    static func lastDatabaseModification() -> Date? {
        let url = defaultDBURL()
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else { return nil }
        return values.contentModificationDate
    }

    /// cc-switch 是否正在运行（Claude 桌面版用量依赖它的本地代理）。
    @MainActor
    static func isCCSwitchRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.ccswitch.desktop"
        }
    }

    private static func day(from key: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: key) ?? .now
    }

    private static func defaultDBURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-switch", isDirectory: true)
            .appendingPathComponent("cc-switch.db", isDirectory: false)
    }
}
