import Foundation
import Testing
import SQLite3
@testable import QuotaMonitor

// MARK: - 夹具工具

private enum Fixtures {
    static func makeTempDir(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("quota-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func remove(_ dir: URL) {
        try? FileManager.default.removeItem(at: dir)
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func day(_ date: Date) -> String {
        DailyTokenUsage.dayKey(for: date)
    }

    static func noon(yesterdayOffset: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: .now)
        components.hour = 12
        components.minute = 0
        let base = Calendar.current.date(from: components) ?? .now
        return Calendar.current.date(byAdding: .day, value: -yesterdayOffset, to: base) ?? base
    }
}

// MARK: - Claude 转录解析

struct ClaudeSessionTokenClientTests {
    @Test func aggregatesByDayAndSplitsDeepSeek() async throws {
        let root = try Fixtures.makeTempDir("claude")
        defer { Fixtures.remove(root) }

        let day1 = Fixtures.noon(yesterdayOffset: 1)
        let day2 = Fixtures.noon(yesterdayOffset: 0)
        let project = root.appendingPathComponent("projects/-Users-test", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("session-1.jsonl")

        let lines = [
            #"{"type":"user","message":{"role":"user","content":"hi"},"timestamp":"\#(Fixtures.iso(day1))"}"#,
            #"{"type":"assistant","message":{"model":"gpt-5.6-sol","usage":{"input_tokens":100,"cache_creation_input_tokens":10,"cache_read_input_tokens":50,"output_tokens":20}},"timestamp":"\#(Fixtures.iso(day1))"}"#,
            #"{"type":"assistant","message":{"model":"deepseek-v4-flash","usage":{"input_tokens":200,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":30}},"timestamp":"\#(Fixtures.iso(day1))"}"#,
            #"{"type":"assistant","message":{"model":"deepseek-v4-flash","usage":{"input_tokens":300,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":40}},"timestamp":"\#(Fixtures.iso(day2))"}"#
        ]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let client = ClaudeSessionTokenClient(root: root)
        let all = await client.fetch()
        let deepSeek = await client.fetch(modelFilter: "deepseek")

        // 统一口径：input 含 cache_read + cache_creation。
        // 第 1 天：180（官方）+ 230（DS）；第 2 天：340（DS）。
        let day1Key = Fixtures.day(day1)
        let day2Key = Fixtures.day(day2)
        #expect(all.first { $0.id == day1Key }?.total == 410)
        #expect(all.first { $0.id == day1Key }?.cachedInput == 50)
        #expect(all.first { $0.id == day1Key }?.cacheWriteInput == 10)
        #expect(all.first { $0.id == day2Key }?.total == 340)
        #expect(deepSeek.first { $0.id == day1Key }?.total == 230)
        #expect(deepSeek.first { $0.id == day2Key }?.total == 340)
        #expect(all.count == 2)
    }

    @Test func cachesUnchangedFiles() async throws {
        let root = try Fixtures.makeTempDir("claude-cache")
        defer { Fixtures.remove(root) }

        let day = Fixtures.noon(yesterdayOffset: 0)
        let project = root.appendingPathComponent("projects/-Users-test", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("session-2.jsonl")
        let line = #"{"type":"assistant","message":{"model":"deepseek-v4-flash","usage":{"input_tokens":10,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":2}},"timestamp":"\#(Fixtures.iso(day))"}"#
        try line.write(to: file, atomically: true, encoding: .utf8)

        let client = ClaudeSessionTokenClient(root: root)
        let first = await client.fetch()
        let second = await client.fetch()
        #expect(first.first?.total == 12)
        #expect(second.first?.total == 12)
    }
    @Test func appendsOnlyNewClaudeJSONLLinesAfterCachedBoundary() async throws {
        let root = try Fixtures.makeTempDir("claude-append")
        defer { Fixtures.remove(root) }

        let project = root.appendingPathComponent("projects/-Users-test", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let file = project.appendingPathComponent("session-append.jsonl")
        let timestamp = Fixtures.iso(Fixtures.noon(yesterdayOffset: 0))
        let firstLine = #"{"type":"assistant","message":{"model":"gpt-5.6-sol","usage":{"input_tokens":10,"output_tokens":2}},"timestamp":"\#(timestamp)"}"#
        let secondLine = #"{"type":"assistant","message":{"model":"gpt-5.6-sol","usage":{"input_tokens":20,"output_tokens":3}},"timestamp":"\#(timestamp)"}"#
        let original = Data((firstLine + "\n").utf8)
        try original.write(to: file)

        let client = ClaudeSessionTokenClient(root: root)
        #expect(await client.fetch().first?.total == 12)

        // 破坏已缓存前缀但保留原字节数与末尾换行；若错误地全量回扫，旧的 12 会丢失。
        var corrupted = Data(repeating: 0x20, count: original.count)
        corrupted[corrupted.index(before: corrupted.endIndex)] = 0x0A
        try corrupted.write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((secondLine + "\n").utf8))
        try handle.close()

        #expect(await client.fetch().first?.total == 35)
    }

}

// MARK: - Codex 会话解析（含归档目录）

struct CodexSessionTokenClientTests {
    @Test func readsArchivedSessionsWithFilenameDates() async throws {
        let root = try Fixtures.makeTempDir("codex")
        defer { Fixtures.remove(root) }

        let dayA = Fixtures.noon(yesterdayOffset: 2)
        let dayB = Fixtures.noon(yesterdayOffset: 1)
        let dayAKey = Fixtures.day(dayA)
        let dayBKey = Fixtures.day(dayB)

        // 归档目录是扁平结构，日期从文件名 rollout-YYYY-MM-DD 解析。
        let archivedDir = root.appendingPathComponent("archived_sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: archivedDir, withIntermediateDirectories: true)
        let archived = archivedDir
            .appendingPathComponent("rollout-2026-08-05T17-39-59-019fd14b-archived.jsonl")
        // 模型在状态行（不带 usage），需跨行跟踪；同一文件跨两天的两条请求按 timestamp 拆分增量。
        let stateLine = #"{"timestamp":"\#(Fixtures.iso(dayA))","payload":{"state":{"model":"deepseek-v4-flash"}}}"#
        let usageA = #"{"timestamp":"\#(Fixtures.iso(dayA))","payload":{"info":{"total_token_usage":{"input_tokens":1000,"cached_input_tokens":900,"cache_write_input_tokens":50,"output_tokens":60,"reasoning_output_tokens":10}}}}"#
        let usageB = #"{"timestamp":"\#(Fixtures.iso(dayB))","payload":{"info":{"total_token_usage":{"input_tokens":1100,"cached_input_tokens":900,"cache_write_input_tokens":50,"output_tokens":70,"reasoning_output_tokens":10}}}}"#
        try [stateLine, usageA, usageB].joined(separator: "\n").write(to: archived, atomically: true, encoding: .utf8)

        // 未归档目录仍按路径 <年>/<月>/<日> 归日。
        let sessionsDir = root
            .appendingPathComponent("sessions/\(Self.pathDay(dayB))", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsDir, withIntermediateDirectories: true)
        let active = sessionsDir.appendingPathComponent("rollout-active.jsonl")
        let gptLine = #"{"payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":500,"cached_input_tokens":0,"cache_write_input_tokens":0,"output_tokens":40,"reasoning_output_tokens":0}},"model":"gpt-5.6-sol"}}"#
        try gptLine.write(to: active, atomically: true, encoding: .utf8)

        let client = CodexSessionTokenClient(root: root)
        let all = await client.fetch()
        let deepSeek = await client.fetch(modelFilter: "deepseek")

        // 第 1 天：首行全量 1060；第 2 天：第二行增量 110 + gpt 会话 540。
        #expect(all.first { $0.id == dayAKey }?.total == 1060)
        #expect(all.first { $0.id == dayBKey }?.total == 650)
        #expect(deepSeek.first { $0.id == dayAKey }?.total == 1060)
        #expect(deepSeek.first { $0.id == dayBKey }?.total == 110)
    }

    @Test func restoresUnchangedFilesFromPersistentCache() async throws {
        let root = try Fixtures.makeTempDir("codex-persistent-cache")
        defer { Fixtures.remove(root) }

        let sessions = root.appendingPathComponent("sessions/2026/08/11", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-cache.jsonl")
        let line = #"{"timestamp":"2026-08-11T08:00:00Z","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":120,"output_tokens":30}}}}"#
        try line.write(to: file, atomically: true, encoding: .utf8)
        let originalMtime = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        let cacheURL = root.appendingPathComponent("cache/codex.json")

        let firstClient = CodexSessionTokenClient(root: root, persistentCacheURL: cacheURL)
        #expect(await firstClient.fetch().first?.total == 150)

        // 保持元数据不变但破坏正文；新 actor 仍能从落盘汇总恢复，证明无需重扫历史文件。
        let originalSize = Data(line.utf8).count
        try Data(repeating: 0x20, count: originalSize).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: originalMtime], ofItemAtPath: file.path)

        let secondClient = CodexSessionTokenClient(root: root, persistentCacheURL: cacheURL)
        #expect(await secondClient.fetch().first?.total == 150)
    }

    @Test func retainsLastGoodFileAggregateWhenAnActiveFileTemporarilyStopsParsing() async throws {
        let root = try Fixtures.makeTempDir("codex-last-good")
        defer { Fixtures.remove(root) }
        let sessions = root.appendingPathComponent("sessions/2026/08/11", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-active.jsonl")
        let valid = #"{"timestamp":"2026-08-11T08:00:00Z","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":120,"output_tokens":30}}}}"#
        try valid.write(to: file, atomically: true, encoding: .utf8)

        let client = CodexSessionTokenClient(root: root)
        #expect(try await client.fetchSnapshot().history.first?.total == 150)
        try "temporarily incomplete".write(to: file, atomically: true, encoding: .utf8)
        #expect(try await client.fetchSnapshot().history.first?.total == 150)
    }


    @Test func appendsOnlyNewCodexJSONLLinesAndContinuesCumulativeTotals() async throws {
        let root = try Fixtures.makeTempDir("codex-append")
        defer { Fixtures.remove(root) }

        let sessions = root.appendingPathComponent("sessions/2026/08/13", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-active.jsonl")
        let firstLine = #"{"timestamp":"2026-08-13T08:00:00Z","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":100,"output_tokens":20}}}}"#
        let secondLine = #"{"timestamp":"2026-08-13T08:01:00Z","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":140,"output_tokens":30}}}}"#
        let original = Data((firstLine + "\n").utf8)
        try original.write(to: file)

        let client = CodexSessionTokenClient(root: root)
        #expect(await client.fetch().first?.total == 120)

        var corrupted = Data(repeating: 0x20, count: original.count)
        corrupted[corrupted.index(before: corrupted.endIndex)] = 0x0A
        try corrupted.write(to: file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((secondLine + "\n").utf8))
        try handle.close()

        // 新累计值 170；增量游标会在旧 120 基础上只追加 50。
        #expect(await client.fetch().first?.total == 170)
    }

    private static func pathDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        formatter.timeZone = .current
        return formatter.string(from: date)
    }
}

// MARK: - WorkBuddy trace 解析

struct WorkBuddyTraceClientTests {
    @Test func readsTraceHeadersAndAggregates() async throws {
        let root = try Fixtures.makeTempDir("workbuddy")
        defer { Fixtures.remove(root) }

        let day1 = Fixtures.noon(yesterdayOffset: 1)
        let day2 = Fixtures.noon(yesterdayOffset: 0)
        let dir1 = root.appendingPathComponent("111", isDirectory: true)
        let dir2 = root.appendingPathComponent("222", isDirectory: true)
        try FileManager.default.createDirectory(at: dir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir2, withIntermediateDirectories: true)

        let trace1 = #"{"trace":{"traceId":"t1","startedAt":"\#(Fixtures.iso(day1))","totalTokens":500,"modelInfo":{"models":["hy3"],"totalInputTokens":450,"totalOutputTokens":50,"totalCachedTokens":300}},"spans":[]}"#
        let trace2 = #"{"trace":{"traceId":"t2","startedAt":"\#(Fixtures.iso(day2))","totalTokens":700,"modelInfo":{"models":["deepseek-v4-flash"],"totalInputTokens":650,"totalOutputTokens":50,"totalCachedTokens":600}},"spans":[]}"#
        try trace1.write(to: dir1.appendingPathComponent("trace_a.json"), atomically: true, encoding: .utf8)
        try trace2.write(to: dir2.appendingPathComponent("trace_b.json"), atomically: true, encoding: .utf8)

        let client = WorkBuddyTraceClient(root: root)
        let all = await client.fetch()
        let deepSeek = await client.fetch(modelFilter: "deepseek")

        let day1Key = Fixtures.day(day1)
        let day2Key = Fixtures.day(day2)
        #expect(all.first { $0.id == day1Key }?.total == 500)
        #expect(all.first { $0.id == day1Key }?.cachedInput == 300)
        #expect(all.first { $0.id == day2Key }?.total == 700)
        #expect(deepSeek.first { $0.id == day1Key } == nil)
        #expect(deepSeek.first { $0.id == day2Key }?.total == 700)
    }

    @Test func skipsEmptyTraces() async throws {
        let root = try Fixtures.makeTempDir("workbuddy-empty")
        defer { Fixtures.remove(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let empty = #"{"trace":{"traceId":"t0","startedAt":"\#(Fixtures.iso(.now))","totalTokens":0,"modelInfo":{"models":["hy3"],"totalInputTokens":0,"totalOutputTokens":0,"totalCachedTokens":0}},"spans":[]}"#
        try empty.write(to: root.appendingPathComponent("trace_empty.json"), atomically: true, encoding: .utf8)

        let client = WorkBuddyTraceClient(root: root)
        #expect(await client.fetch().isEmpty)
    }

    @Test func readsGenerationUsageFromNewTraceFormat() async throws {
        let root = try Fixtures.makeTempDir("workbuddy-generation")
        defer { Fixtures.remove(root) }

        let day = Fixtures.noon(yesterdayOffset: 0)
        let created = Int(day.timeIntervalSince1970)
        let responseObject: [String: Any] = [
            "id": "g1",
            "created": created,
            "model": "hy3",
            "usage": [
                "prompt_tokens": 120,
                "completion_tokens": 30,
                "total_tokens": 150,
                "prompt_tokens_details": ["cached_tokens": 80],
                "completion_tokens_details": ["reasoning_tokens": 7]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseObject)
        let response = String(decoding: responseData, as: UTF8.self)
        let escapedResponse = response.replacingOccurrences(of: "\"", with: "\\\"")
        let trace = "{\"trace\":{\"traceId\":\"new\",\"startedAt\":\""
            + Fixtures.iso(day)
            + "\",\"totalTokens\":0},\"spans\":[{\"name\":\"generation\",\"type\":\"generation\",\"toolOutput\":\"["
            + escapedResponse
            + "]\"}]}"
        try trace.write(to: root.appendingPathComponent("trace_new.json"), atomically: true, encoding: .utf8)

        let client = WorkBuddyTraceClient(root: root)
        let all = await client.fetch()
        let buckets = await client.fetchBuckets()

        #expect(all.first?.total == 150)
        #expect(all.first?.cachedInput == 80)
        #expect(all.first?.reasoning == 7)
        #expect(buckets.first?.model == "hy3")
    }

    @Test func waitsForCompleteGenerationUsageAcrossReadChunks() async throws {
        let root = try Fixtures.makeTempDir("workbuddy-generation-boundary")
        defer { Fixtures.remove(root) }
        let created = Int(Fixtures.noon(yesterdayOffset: 0).timeIntervalSince1970)
        let padding = String(repeating: "x", count: 63_500)
        let response = "{\"id\":\"g2\",\"created\":\(created),\"model\":\"hy3\",\"choices\":[{\"message\":{\"content\":\"\(padding)\"}}],\"usage\":{\"prompt_tokens\":120,\"completion_tokens\":30,\"total_tokens\":150,\"prompt_tokens_details\":{\"cached_tokens\":80},\"completion_tokens_details\":{\"reasoning_tokens\":7}}}"
        let escaped = response.replacingOccurrences(of: "\"", with: "\\\"")
        let trace = "{\"trace\":{\"startedAt\":\"\(Fixtures.iso(.now))\",\"totalTokens\":0},\"spans\":[{\"name\":\"generation\",\"type\":\"generation\",\"toolOutput\":\"[\(escaped)]\"}]}"
        try trace.write(to: root.appendingPathComponent("trace_boundary.json"), atomically: true, encoding: .utf8)

        let snapshot = try await WorkBuddyTraceClient(root: root).fetchSnapshot()
        #expect(snapshot.history.first?.total == 150)
        #expect(snapshot.history.first?.cachedInput == 80)
        #expect(snapshot.history.first?.reasoning == 7)
    }

    @Test func ignoresUsageShapedJSONOutsideToolOutput() async throws {
        let root = try Fixtures.makeTempDir("workbuddy-generation-false-marker")
        defer { Fixtures.remove(root) }
        let fake = #"{\"created\":1780000000,\"model\":\"deepseek-v4-pro\",\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":20,\"total_tokens\":120}}"#
        let trace = "{\"trace\":{\"startedAt\":\"\(Fixtures.iso(.now))\",\"totalTokens\":0},\"spans\":[{\"name\":\"generation\",\"type\":\"generation\",\"toolInput\":\"\(fake)\",\"toolOutput\":\"[]\"}]}"
        try trace.write(to: root.appendingPathComponent("trace_fake.json"), atomically: true, encoding: .utf8)

        #expect(try await WorkBuddyTraceClient(root: root).fetchSnapshot().history.isEmpty)
    }

}

// MARK: - cc-switch 请求日志解析

struct CCSwitchUsageClientTests {
    @Test func readsProxyRequestLogsByAppType() async throws {
        let dir = try Fixtures.makeTempDir("ccswitch")
        defer { Fixtures.remove(dir) }
        let dbURL = dir.appendingPathComponent("cc-switch.db")

        let day1 = Fixtures.noon(yesterdayOffset: 1)
        let day2 = Fixtures.noon(yesterdayOffset: 0)
        try createDB(
            at: dbURL,
            rows: [
                ("claude-desktop", "deepseek-v4-flash", 100, 10, 50, 5, Int64(day1.timeIntervalSince1970)),
                ("claude-desktop", "deepseek-v4-flash", 200, 20, 0, 0, Int64(day2.timeIntervalSince1970)),
                ("claude", "gpt-5.6-sol", 30, 3, 0, 0, Int64(day2.timeIntervalSince1970))
            ]
        )

        let client = CCSwitchUsageClient(dbURL: dbURL)
        let desktop = await client.fetch(appType: "claude-desktop")
        let claude = await client.fetch(appType: "claude")

        // 统一口径：input 含 cache_read + cache_creation。
        let day1Key = Fixtures.day(day1)
        let day2Key = Fixtures.day(day2)
        #expect(desktop?.all.first { $0.id == day1Key }?.total == 165)
        #expect(desktop?.all.first { $0.id == day1Key }?.cachedInput == 50)
        #expect(desktop?.all.first { $0.id == day1Key }?.cacheWriteInput == 5)
        #expect(desktop?.all.first { $0.id == day2Key }?.total == 220)
        #expect(desktop?.deepSeek.first { $0.id == day1Key }?.total == 165)
        #expect(desktop?.deepSeek.first { $0.id == day2Key }?.total == 220)

        #expect(claude?.all.first { $0.id == day2Key }?.total == 33)
        #expect(claude?.deepSeek.isEmpty == true)
    }

    private func createDB(at url: URL, rows: [(String, String, Int, Int, Int, Int, Int64)]) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else {
            throw TestError.dbOpenFailed
        }
        defer { sqlite3_close(db) }

        let schema = """
        CREATE TABLE proxy_request_logs (
            app_type TEXT, model TEXT, input_tokens INTEGER, output_tokens INTEGER,
            cache_read_tokens INTEGER, cache_creation_tokens INTEGER, created_at INTEGER
        );
        """
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
            throw TestError.schemaFailed
        }
        for row in rows {
            let sql = """
            INSERT INTO proxy_request_logs VALUES
            ('\(row.0)', '\(row.1)', \(row.2), \(row.3), \(row.4), \(row.5), \(row.6));
            """
            guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
                throw TestError.insertFailed
            }
        }
    }

    private enum TestError: Error {
        case dbOpenFailed
        case schemaFailed
        case insertFailed
    }
}
