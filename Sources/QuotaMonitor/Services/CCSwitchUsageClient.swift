import Foundation
import AppKit
import SQLite3

/// 从 cc-switch 的请求日志读取 Claude / Claude 桌面版 token 用量。
///
/// 数据来源：`~/.cc-switch/cc-switch.db` 的 `proxy_request_logs` 表，
/// 每行一次请求：app_type / model / input / output / cache_read /
/// cache_creation / created_at（epoch 秒）。cc-switch 为 Claude 桌面版
/// 的本地代理捕获，这是当前 QuotaMonitor 已接入的桌面版用量来源。
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
        let inputTokenSemantics: Int?
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
            let inclusiveInput = Self.inclusiveInput(
                rawInput: row.inputTokens,
                cacheRead: row.cacheReadTokens,
                cacheCreation: row.cacheCreationTokens,
                semantics: row.inputTokenSemantics
            )
            // Existing Claude Desktop rows use fresh input. For unknown semantics,
            // preserve the historic aggregate while refusing cache-rate evidence.
            totals.input = inclusiveInput
                ?? Self.checkedInputTotal(uncached: row.inputTokens, cached: row.cacheReadTokens, cacheWrite: row.cacheCreationTokens)
                ?? max(0, row.inputTokens)
            totals.cachedInput = row.cacheReadTokens
            totals.cacheWriteInput = row.cacheCreationTokens
            totals.output = row.outputTokens
            if let inclusiveInput,
               let measurement = CacheUsageMeasurement(
                input: inclusiveInput, cachedInput: row.cacheReadTokens,
                cacheWriteInput: row.cacheCreationTokens, output: row.outputTokens
               ) {
                totals.cacheMeasurement = measurement
            } else {
                totals.cacheExclusionReasons = [
                    row.inputTokenSemantics == nil ? .missingFields : .invalidFields
                ]
            }
            let createdAt = Date(timeIntervalSince1970: Double(row.createdAt))
            let hour = Calendar.current.date(
                from: Calendar.current.dateComponents([.year, .month, .day, .hour], from: createdAt)
            ) ?? createdAt
            return TokenUsageBucket.modelBucket(
                at: hour, platform: .claude, client: client, model: row.model, totals: totals
            )
        })
    }

    private func queryRows(appType: String) -> [Row]? {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 2_000)

        // 直接在 SQLite 层按小时和模型聚合，避免把完整请求历史加载进内存，
        // 也消除旧版 500,000 行静默截断造成的不确定结果。
        let hasInputSemantics = hasColumn("input_token_semantics", in: "proxy_request_logs", database: db)
        let semanticsSelection = hasInputSemantics ? "input_token_semantics" : "NULL"
        let semanticsGrouping = hasInputSemantics ? ", input_token_semantics" : ""
        let sql = """
        SELECT model,
               SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens),
               SUM(cache_creation_tokens), \(semanticsSelection),
               MIN(created_at)
        FROM proxy_request_logs
        WHERE app_type = ?1
        GROUP BY model, strftime('%Y-%m-%d-%H', created_at, 'unixepoch', 'localtime') \(semanticsGrouping)
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
            guard !Task.isCancelled else { return nil }
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                let model = sqlite3_column_text(statement, 0).map { String(cString: $0) } ?? TokenModelName.unknown
                rows.append(Row(
                    model: model,
                    inputTokens: Int(sqlite3_column_int64(statement, 1)),
                    outputTokens: Int(sqlite3_column_int64(statement, 2)),
                    cacheReadTokens: Int(sqlite3_column_int64(statement, 3)),
                    cacheCreationTokens: Int(sqlite3_column_int64(statement, 4)),
                    inputTokenSemantics: sqlite3_column_type(statement, 5) == SQLITE_NULL
                        ? nil : Int(sqlite3_column_int64(statement, 5)),
                    createdAt: sqlite3_column_int64(statement, 6)
                ))
            } else if step == SQLITE_DONE {
                break
            } else {
                return nil
            }
        }
        return rows
    }

    private func hasColumn(_ column: String, in table: String, database: OpaquePointer) -> Bool {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, "PRAGMA table_info(\(table))", -1, &statement, nil) == SQLITE_OK,
              let statement else { return false }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let name = sqlite3_column_text(statement, 1), String(cString: name) == column else { continue }
            return true
        }
        return false
    }

    /// cc-switch input_token_semantics: 0 = legacy (read already included),
    /// 1 = total inclusive (read + creation included), 2 = fresh/uncached input.
    private static func inclusiveInput(rawInput: Int, cacheRead: Int, cacheCreation: Int, semantics: Int?) -> Int? {
        guard rawInput >= 0, cacheRead >= 0, cacheCreation >= 0 else { return nil }
        let extra: Int
        switch semantics {
        case 0: extra = cacheCreation
        case 1: extra = 0
        case 2:
            return checkedInputTotal(uncached: rawInput, cached: cacheRead, cacheWrite: cacheCreation)
        default: return nil
        }
        let (total, overflow) = rawInput.addingReportingOverflow(extra)
        return overflow ? nil : total
    }

    private static func checkedInputTotal(uncached: Int, cached: Int, cacheWrite: Int) -> Int? {
        guard uncached >= 0, cached >= 0, cacheWrite >= 0 else { return nil }
        let (withRead, readOverflow) = uncached.addingReportingOverflow(cached)
        let (inclusive, writeOverflow) = withRead.addingReportingOverflow(cacheWrite)
        return readOverflow || writeOverflow ? nil : inclusive
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
