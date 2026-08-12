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
/// cache_creation / created_at（epoch 秒）。cc-switch 为 Claude 桌面版
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

    /// 同一次 SQLite 查询同时生成总量、DeepSeek 子集和模型桶。
    func fetchSnapshot(appType: String, client: TokenClient = .desktop) -> TokenSourceSnapshot? {
        guard let rows = queryRows(appType: appType) else { return nil }
        return TokenSourceSnapshot(buckets: rows.map { row in
            var totals = TokenTotals()
            totals.input = row.inputTokens + row.cacheReadTokens + row.cacheCreationTokens
            totals.cachedInput = row.cacheReadTokens
            totals.cacheWriteInput = row.cacheCreationTokens
            totals.output = row.outputTokens
            let model = TokenModelName.canonical(row.model)
            return TokenUsageBucket(
                bucketStart: Calendar.current.startOfDay(for: Date(timeIntervalSince1970: Double(row.createdAt))),
                platform: .claude,
                client: client,
                model: model,
                provider: model.lowercased().contains("deepseek") ? .deepseek : .official,
                totals: totals
            )
        })
    }

    func fetch(appType: String) -> CCSwitchDailyUsage? {
        guard let snapshot = fetchSnapshot(appType: appType) else { return nil }
        return CCSwitchDailyUsage(all: snapshot.history, deepSeek: snapshot.deepSeekHistory)
    }

    func fetchBuckets(appType: String, client: TokenClient = .desktop) -> [TokenUsageBucket]? {
        fetchSnapshot(appType: appType, client: client)?.buckets
    }

    private func queryRows(appType: String) -> [Row]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)

        // 直接在 SQLite 层按日和模型聚合，避免把完整请求历史加载进内存，
        // 也消除旧版 500,000 行静默截断造成的不确定结果。
        let sql = """
        SELECT model,
               SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens),
               SUM(cache_creation_tokens),
               MIN(created_at)
        FROM proxy_request_logs
        WHERE app_type = ?1
        GROUP BY model, date(created_at, 'unixepoch', 'localtime')
        ORDER BY MIN(created_at) ASC, model ASC
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
                let model = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? TokenModelName.unknown
                rows.append(Row(
                    model: model,
                    inputTokens: Int(sqlite3_column_int64(statement, 1)),
                    outputTokens: Int(sqlite3_column_int64(statement, 2)),
                    cacheReadTokens: Int(sqlite3_column_int64(statement, 3)),
                    cacheCreationTokens: Int(sqlite3_column_int64(statement, 4)),
                    createdAt: sqlite3_column_int64(statement, 5)
                ))
            } else if step == SQLITE_DONE {
                break
            } else {
                return nil
            }
        }
        return rows
    }

    /// cc-switch 是否正在运行（Claude 桌面版用量依赖它的本地代理）。
    @MainActor
    static func isCCSwitchRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == "com.ccswitch.desktop"
        }
    }

    private static func defaultDBURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-switch", isDirectory: true)
            .appendingPathComponent("cc-switch.db", isDirectory: false)
    }
}
