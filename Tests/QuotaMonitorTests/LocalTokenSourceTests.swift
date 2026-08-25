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
    @Test func excludesForkedHistoryAndCountsOnlyForkAdditions() async throws {
        let root = try Fixtures.makeTempDir("codex-fork")
        defer { Fixtures.remove(root) }

        let parentDay = Fixtures.noon(yesterdayOffset: 1)
        let forkDay = Fixtures.noon(yesterdayOffset: 0)
        let sessions = root.appendingPathComponent("sessions/2026/08/17", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        let parentID = "parent-session"
        let childID = "child-session"
        let parentMeta = #"{"timestamp":"\#(Fixtures.iso(parentDay))","type":"session_meta","payload":{"session_id":"\#(parentID)","id":"\#(parentID)","forked_from_id":null}}"#
        let childMeta = #"{"timestamp":"\#(Fixtures.iso(forkDay))","type":"session_meta","payload":{"session_id":"\#(childID)","id":"\#(childID)","forked_from_id":"\#(parentID)"}}"#
        let parentUsage1 = #"{"timestamp":"\#(Fixtures.iso(parentDay))","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#
        let parentUsage2 = #"{"timestamp":"\#(Fixtures.iso(parentDay))","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":150,"output_tokens":20}}}}"#
        let forkUsage1 = #"{"timestamp":"\#(Fixtures.iso(forkDay))","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":100,"output_tokens":10}}}}"#
        let forkUsage2 = #"{"timestamp":"\#(Fixtures.iso(forkDay))","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":150,"output_tokens":20}}}}"#
        let forkUsage3 = #"{"timestamp":"\#(Fixtures.iso(forkDay))","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":180,"output_tokens":25}}}}"#
        let forkUsage4 = #"{"timestamp":"\#(Fixtures.iso(forkDay))","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":220,"output_tokens":30}}}}"#

        try [parentMeta, parentUsage1, parentUsage2]
            .joined(separator: "\n")
            .write(to: sessions.appendingPathComponent("parent.jsonl"), atomically: true, encoding: .utf8)
        // Codex fork 文件会保留复制进来的父 session_meta；首条 metadata 必须决定文件身份。
        try [childMeta, parentMeta, forkUsage1, forkUsage2, forkUsage3]
            .joined(separator: "\n")
            .appending("\n")
            .write(to: sessions.appendingPathComponent("child.jsonl"), atomically: true, encoding: .utf8)

        let client = CodexSessionTokenClient(root: root)
        let history = await client.fetch()

        // 父会话 170，加上 fork 后新增的 35；继承的 170 不能再次计入。
        #expect(history.first { $0.id == Fixtures.day(parentDay) }?.total == 170)
        #expect(history.first { $0.id == Fixtures.day(forkDay) }?.total == 35)
        #expect(history.reduce(0) { $0 + $1.total } == 205)

        let childFile = sessions.appendingPathComponent("child.jsonl")
        let handle = try FileHandle(forWritingTo: childFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((forkUsage4 + "\n").utf8))
        try handle.close()

        let refreshed = await client.fetch()
        #expect(refreshed.first { $0.id == Fixtures.day(forkDay) }?.total == 80)
        #expect(refreshed.reduce(0) { $0 + $1.total } == 250)
    }

    @Test func handlesChainedForksWithoutRepeatingAncestorHistory() async throws {
        let root = try Fixtures.makeTempDir("codex-chained-fork")
        defer { Fixtures.remove(root) }

        let day = Fixtures.noon(yesterdayOffset: 0)
        let sessions = root.appendingPathComponent("sessions/2026/08/17", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)

        func meta(_ id: String, parent: String?) -> String {
            let parentJSON = parent.map { "\"\($0)\"" } ?? "null"
            return #"{"timestamp":"\#(Fixtures.iso(day))","type":"session_meta","payload":{"session_id":"\#(id)","id":"\#(id)","forked_from_id":\#(parentJSON)}}"#
        }
        func usage(_ input: Int, _ output: Int) -> String {
            #"{"timestamp":"\#(Fixtures.iso(day))","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":\#(input),"output_tokens":\#(output)}}}}"#
        }

        let parentID = "chain-parent"
        let childID = "chain-child"
        let grandchildID = "chain-grandchild"
        let u1 = usage(100, 10)
        let u2 = usage(140, 15)
        let u3 = usage(180, 20)
        let u4 = usage(210, 25)
        try [meta(parentID, parent: nil), u1, u2]
            .joined(separator: "\n")
            .write(to: sessions.appendingPathComponent("parent.jsonl"), atomically: true, encoding: .utf8)
        try [meta(childID, parent: parentID), meta(parentID, parent: nil), u1, u2, u3]
            .joined(separator: "\n")
            .write(to: sessions.appendingPathComponent("child.jsonl"), atomically: true, encoding: .utf8)
        try [meta(grandchildID, parent: childID), meta(childID, parent: parentID), u1, u2, u3, u4]
            .joined(separator: "\n")
            .write(to: sessions.appendingPathComponent("grandchild.jsonl"), atomically: true, encoding: .utf8)

        let client = CodexSessionTokenClient(root: root)
        let history = await client.fetch()
        #expect(history.first?.total == 235)
    }

    @Test func usesPayloadIDForSubagentForks() async throws {
        let root = try Fixtures.makeTempDir("codex-subagent-fork")
        defer { Fixtures.remove(root) }

        let sessions = root.appendingPathComponent("sessions/2026/08/17", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let day = Fixtures.noon(yesterdayOffset: 0)

        func usage(_ input: Int, _ output: Int) -> String {
            #"{"timestamp":"\#(Fixtures.iso(day))","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":\#(input),"output_tokens":\#(output)}}}}"#
        }
        let parentID = "thread-parent"
        let childID = "rollout-child"
        let parentMeta = #"{"timestamp":"2026-08-17T08:00:00Z","type":"session_meta","payload":{"session_id":"\#(parentID)","id":"\#(parentID)"}}"#
        let childMeta = #"{"timestamp":"2026-08-17T08:01:00Z","type":"session_meta","payload":{"session_id":"\#(parentID)","id":"\#(childID)","parent_thread_id":"\#(parentID)"}}"#

        try [parentMeta, usage(100, 10)]
            .joined(separator: "\n")
            .appending("\n")
            .write(to: sessions.appendingPathComponent("parent.jsonl"), atomically: true, encoding: .utf8)
        try [childMeta, usage(100, 10), usage(140, 20)]
            .joined(separator: "\n")
            .appending("\n")
            .write(to: sessions.appendingPathComponent("child.jsonl"), atomically: true, encoding: .utf8)

        let client = CodexSessionTokenClient(root: root)
        let history = await client.fetch()
        #expect(history.first?.total == 160)
    }

    @Test func ignoresPreForkPersistentCacheVersion() async throws {
        let root = try Fixtures.makeTempDir("codex-cache-version")
        defer { Fixtures.remove(root) }

        let sessions = root.appendingPathComponent("sessions/2026/08/17", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-cache-version.jsonl")
        let line = #"{"timestamp":"2026-08-17T08:00:00Z","payload":{"info":{"model":"gpt-5.6-sol","total_token_usage":{"input_tokens":120,"output_tokens":30}}}}"#
        try line.write(to: file, atomically: true, encoding: .utf8)
        let cacheURL = root.appendingPathComponent("cache/codex.json")

        let firstClient = CodexSessionTokenClient(root: root, persistentCacheURL: cacheURL)
        #expect(await firstClient.fetch().first?.total == 150)
        let oldVersionData = try Data(contentsOf: cacheURL)
        let oldVersion = String(decoding: oldVersionData, as: UTF8.self)
            .replacingOccurrences(of: "\"version\":5", with: "\"version\":4")
        try oldVersion.write(to: cacheURL, atomically: true, encoding: .utf8)

        let secondClient = CodexSessionTokenClient(root: root, persistentCacheURL: cacheURL)
        #expect(await secondClient.fetch().first?.total == 150)
    }

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

    @Test func prefersLastTokenUsageWhenCumulativeTotalDoesNotAdvance() async throws {
        let root = try Fixtures.makeTempDir("codex-last-token-usage")
        defer { Fixtures.remove(root) }

        let sessions = root.appendingPathComponent("sessions/2026/08/13", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let file = sessions.appendingPathComponent("rollout-last-token-usage.jsonl")
        let first = #"{"timestamp":"2026-08-13T08:00:00Z","payload":{"info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":100,"output_tokens":10,"total_tokens":110}}}}"#
        let compaction = #"{"timestamp":"2026-08-13T08:01:00Z","payload":{"info":{"total_token_usage":{"input_tokens":100,"output_tokens":10},"last_token_usage":{"input_tokens":0,"output_tokens":0,"total_tokens":25}}}}"#
        let third = #"{"timestamp":"2026-08-13T08:02:00Z","payload":{"info":{"total_token_usage":{"input_tokens":140,"output_tokens":15},"last_token_usage":{"input_tokens":40,"output_tokens":5,"total_tokens":45}}}}"#
        try [first, compaction, third].joined(separator: "\n").appending("\n")
            .write(to: file, atomically: true, encoding: .utf8)

        let client = CodexSessionTokenClient(root: root)
        let usage = await client.fetch().first
        #expect(usage?.input == 165)
        #expect(usage?.output == 15)
        #expect(usage?.total == 180)
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

    @Test func appendsWorkBuddyGenerationUsageWithoutDoubleCounting() async throws {
        let root = try Fixtures.makeTempDir("workbuddy-generation-append")
        defer { Fixtures.remove(root) }

        let day = Fixtures.noon(yesterdayOffset: 0)
        let created = Int(day.timeIntervalSince1970)
        func response(id: String, input: Int, output: Int) throws -> String {
            let object: [String: Any] = [
                "id": id,
                "created": created,
                "model": "hy3",
                "usage": [
                    "prompt_tokens": input,
                    "completion_tokens": output,
                    "total_tokens": input + output
                ]
            ]
            let data = try JSONSerialization.data(withJSONObject: object)
            return String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"", with: "\\\"")
        }

        let first = try response(id: "g1", input: 120, output: 30)
        let second = try response(id: "g2", input: 200, output: 40)
        let prefix = "{\"trace\":{\"startedAt\":\"\(Fixtures.iso(day))\",\"totalTokens\":0},\"spans\":[{\"name\":\"generation\",\"type\":\"generation\",\"toolOutput\":\"["
        let file = root.appendingPathComponent("trace_append.json")
        try (prefix + first + "]}]}" ).write(to: file, atomically: true, encoding: .utf8)

        let client = WorkBuddyTraceClient(root: root)
        #expect(await client.fetch().first?.total == 150)

        try (prefix + first + "," + second + "]}]}" ).write(to: file, atomically: true, encoding: .utf8)
        #expect(await client.fetch().first?.total == 390)
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

// MARK: - 可扩展工具来源解析

struct AdditionalLocalTokenClientTests {
    @Test func collectsJSONLJSONAndSQLiteSourcesIntoSeparatePlatforms() async throws {
        let root = try Fixtures.makeTempDir("additional-tools")
        defer { Fixtures.remove(root) }
        let day = Fixtures.noon(yesterdayOffset: 0)

        let openClaw = root.appendingPathComponent("openclaw", isDirectory: true)
        try FileManager.default.createDirectory(at: openClaw, withIntermediateDirectories: true)
        try #"{"timestamp":"\#(Fixtures.iso(day))","model":"gpt-5.6-sol","usage":{"prompt_tokens":100,"completion_tokens":20,"cached_tokens":40}}"#
            .write(to: openClaw.appendingPathComponent("session.jsonl"), atomically: true, encoding: .utf8)

        let kimi = root.appendingPathComponent("kimi", isDirectory: true)
        try FileManager.default.createDirectory(at: kimi, withIntermediateDirectories: true)
        let kimiJSON = #"{"events":[{"created":\#(Int(day.timeIntervalSince1970 * 1_000)),"model_name":"kimi-k2","tokenUsage":{"inputTokens":30,"outputTokens":7}}]}"#
        try kimiJSON.write(to: kimi.appendingPathComponent("session.json"), atomically: true, encoding: .utf8)

        let zed = root.appendingPathComponent("zed", isDirectory: true)
        try FileManager.default.createDirectory(at: zed, withIntermediateDirectories: true)
        try createUsageDB(at: zed.appendingPathComponent("threads.db"), day: day)

        let client = AdditionalLocalTokenClient(
            sources: [
                .init(platform: .openclaw, roots: ["openclaw"], overrideEnvironment: ""),
                .init(platform: .kimi, roots: ["kimi"], overrideEnvironment: ""),
                .init(platform: .zed, roots: ["zed"], overrideEnvironment: "")
            ],
            home: root,
            environment: [:],
            persistentCacheURL: nil
        )
        let snapshots = try await client.fetchSnapshots()
        let totals = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.buckets.first!.platform, $0.history.first!.total) })

        #expect(totals[.openclaw] == 120)
        #expect(totals[.kimi] == 37)
        #expect(totals[.zed] == 18)
        // 第二次读取复用 mtime + size 缓存，聚合结果保持一致。
        #expect(try await client.fetchSnapshots() == snapshots)
    }

    @Test func appendsOnlyNewGenericJSONLLines() async throws {
        let root = try Fixtures.makeTempDir("additional-append")
        defer { Fixtures.remove(root) }
        let day = Fixtures.iso(Fixtures.noon(yesterdayOffset: 0))
        let directory = root.appendingPathComponent("openclaw", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("session.jsonl")
        let first = #"{"timestamp":"\#(day)","model":"gpt-5.6-sol","usage":{"prompt_tokens":10,"completion_tokens":2}}"#
        let second = #"{"timestamp":"\#(day)","model":"gpt-5.6-sol","usage":{"prompt_tokens":20,"completion_tokens":3}}"#
        try (first + "\n").write(to: file, atomically: true, encoding: .utf8)

        let source = LocalToolTokenSource(
            platform: .openclaw,
            roots: ["openclaw"],
            overrideEnvironment: ""
        )
        let client = AdditionalLocalTokenClient(sources: [source], home: root, environment: [:])
        #expect(try await client.fetchSnapshots().first?.history.first?.total == 12)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((second + "\n").utf8))
        try handle.close()
        #expect(try await client.fetchSnapshots().first?.history.first?.total == 35)
    }

    private func createUsageDB(at url: URL, day: Date) throws {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw TestError.dbOpenFailed }
        defer { sqlite3_close(db) }
        let timestamp = Int64(day.timeIntervalSince1970)
        let sql = """
        CREATE TABLE messages (model TEXT, input_tokens INTEGER, output_tokens INTEGER, created_at INTEGER);
        INSERT INTO messages VALUES ('zed-ai', 12, 6, \(timestamp));
        """
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw TestError.writeFailed }
    }

    private enum TestError: Error {
        case dbOpenFailed
        case writeFailed
    }
}

struct KimiDesktopTokenClientTests {
    @Test func countsUsageRecordsWithoutRepeatingStepEndEvents() async throws {
        let root = try Fixtures.makeTempDir("kimi-desktop")
        defer { Fixtures.remove(root) }
        let day = Fixtures.noon(yesterdayOffset: 0)
        let sessions = root.appendingPathComponent("sessions/a/agents/main", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let timestamp = Int(day.timeIntervalSince1970 * 1_000)
        let lines = [
            #"{"type":"context.append_loop_event","event":{"type":"step.end","usage":{"inputOther":100,"inputCacheRead":50,"inputCacheCreation":10,"output":20}},"time":\#(timestamp)}"#,
            #"{"type":"usage.record","model":"k2d6-agent","usage":{"inputOther":100,"inputCacheRead":50,"inputCacheCreation":10,"output":20},"usageScope":"turn","time":\#(timestamp)}"#
        ]
        try lines.joined(separator: "\n").write(to: sessions.appendingPathComponent("wire.jsonl"), atomically: true, encoding: .utf8)

        let source = LocalToolTokenSource(
            platform: .kimi,
            roots: ["sessions"],
            overrideEnvironment: "",
            format: .kimiWire,
            client: .desktop
        )
        let client = AdditionalLocalTokenClient(sources: [source], home: root, environment: [:])
        let snapshot = try await client.fetchSnapshots().first

        #expect(snapshot?.history.first?.total == 180)
        #expect(snapshot?.history.first?.cachedInput == 50)
        #expect(snapshot?.buckets.first?.client == .desktop)
        #expect(snapshot?.buckets.first?.model == "k2d6-agent")
    }
}

struct QwenWorkTokenClientTests {
    @Test func countsModelResponsesWithoutRepeatingTurnSummary() async throws {
        let root = try Fixtures.makeTempDir("qwen-work")
        defer { Fixtures.remove(root) }
        let day = Fixtures.noon(yesterdayOffset: 0)
        let sessions = root.appendingPathComponent(".qwenworkcn/logs/sessions/project/session", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        let timestamp = Fixtures.iso(day)
        let lines = [
            #"{"ts":"\#(timestamp)","type":"model.response.completed","data":{"model":"qwork-lite","input_tokens":100,"output_tokens":20,"cache_read_input_tokens":30}}"#,
            #"{"ts":"\#(timestamp)","type":"turn.finished","data":{"input_tokens":100,"output_tokens":20,"cache_read_input_tokens":30}}"#
        ]
        try lines.joined(separator: "\n").write(to: sessions.appendingPathComponent("segment.jsonl"), atomically: true, encoding: .utf8)

        let source = LocalToolTokenSource(
            platform: .qwenWork,
            roots: [".qwenworkcn/logs/sessions"],
            overrideEnvironment: "",
            format: .qwenWork,
            client: .desktop
        )
        let client = AdditionalLocalTokenClient(sources: [source], home: root, environment: [:])
        let snapshot = try await client.fetchSnapshots().first

        #expect(snapshot?.history.first?.total == 150)
        #expect(snapshot?.history.first?.cachedInput == 30)
        #expect(snapshot?.buckets.first?.model == "qwork-lite")
    }

}

struct TraeWorkTokenSourceTests {
    @Test func countsOnlyExplicitFeeUsageAndIgnoresNullMetadata() async throws {
        let root = try Fixtures.makeTempDir("trae-work")
        defer { Fixtures.remove(root) }
        let logs = root.appendingPathComponent("Library/Application Support/TRAE SOLO CN/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let lines = [
            #"2026-08-14 [info] metadata {"fee_usage":null,"model_info":{"prompt_max_tokens":168000}}"#,
            #"2026-08-14 [info] metadata {"model":"DeepSeek-V4-Flash","fee_usage":{"input_tokens":40,"output_tokens":8}}"#
        ]
        try lines.joined(separator: "\n").write(to: logs.appendingPathComponent("renderer.log"), atomically: true, encoding: .utf8)

        let source = LocalToolTokenSource(
            platform: .traeWork,
            roots: ["Library/Application Support/TRAE SOLO CN/logs"],
            overrideEnvironment: "",
            format: .traeWork,
            client: .desktop
        )
        let client = AdditionalLocalTokenClient(sources: [source], home: root, environment: [:])
        let snapshot = try await client.fetchSnapshots().first

        #expect(snapshot?.history.first?.total == 48)
        #expect(snapshot?.buckets.first?.model == "deepseek-v4-flash")
    }

    @Test func ignoresMetadataWithoutFeeUsage() async throws {
        let root = try Fixtures.makeTempDir("trae-work-estimate")
        defer { Fixtures.remove(root) }
        let logs = root.appendingPathComponent("Library/Application Support/TRAE SOLO CN/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let day = Fixtures.noon(yesterdayOffset: 0)
        let line = #"2026-08-14T18:44:18.566+08:00 [info] [trae-chat-core] [MetadataHandler] received metadata {"message_id":"m1","created_at":\#(Int(day.timeIntervalSince1970)),"user_message_context":{"model_info":{"model_name":"DeepSeek-V4-Flash"},"query":"[{\"type\":\"text\",\"data\":{\"content\":\"请分析这份报告\"}}]"}}"#
        try line.write(to: logs.appendingPathComponent("renderer.log"), atomically: true, encoding: .utf8)

        let source = LocalToolTokenSource(
            platform: .traeWork,
            roots: ["Library/Application Support/TRAE SOLO CN/logs"],
            overrideEnvironment: "",
            format: .traeWork,
            client: .desktop
        )
        let client = AdditionalLocalTokenClient(sources: [source], home: root, environment: [:])
        let snapshot = try await client.fetchSnapshots().first

        #expect(snapshot == nil)
    }
}

struct QoderSessionTokenClientTests {
    @Test func readsCanonicalEventsAndDeduplicatesDesktopMessageCopies() async throws {
        let root = try Fixtures.makeTempDir("qoder")
        defer { Fixtures.remove(root) }
        let day = Fixtures.noon(yesterdayOffset: 0)
        let native = root.appendingPathComponent(".qoder/logs/sessions/history.jsonl")
        try FileManager.default.createDirectory(at: native.deletingLastPathComponent(), withIntermediateDirectories: true)
        let nativeLines = [
            #"{"type":"model.response.completed","request_id":"request-1","ts":"\#(Fixtures.iso(day))","data":{"model":"qoder-max","input_tokens":100,"cache_read_input_tokens":50,"cache_creation_input_tokens":10,"output_tokens":20}}"#,
            #"{"type":"turn.finished","ts":"\#(Fixtures.iso(day))","data":{"input_tokens":100,"cache_read_input_tokens":50,"cache_creation_input_tokens":10,"output_tokens":20}}"#
        ]
        try nativeLines.joined(separator: "\n").write(to: native, atomically: true, encoding: .utf8)

        let desktop = root.appendingPathComponent("Library/Application Support/Qoder/SharedClientCache/cli/projects/task", isDirectory: true)
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        let duplicate = #"{"type":"assistant","timestamp":"\#(Fixtures.iso(day))","message":{"id":"message-1","usage":{"input_tokens":10,"cache_read_input_tokens":3,"cache_creation_input_tokens":0,"output_tokens":2}}}"#
        try duplicate.write(to: desktop.appendingPathComponent("main.jsonl"), atomically: true, encoding: .utf8)
        try duplicate.write(to: desktop.appendingPathComponent("subagent.jsonl"), atomically: true, encoding: .utf8)

        let client = QoderSessionTokenClient(home: root)
        let snapshot = try await client.fetchSnapshot()

        // Native event: 100 + 50 + 10 + 20 = 180; duplicated desktop message: 10 + 3 + 2 = 15.
        #expect(snapshot.history.first?.total == 195)
        #expect(snapshot.buckets.filter { $0.client == .desktop }.count == 1)
        #expect(snapshot.buckets.contains { $0.model == "qoder-max" && $0.client == .cli })
    }

    @Test func appendsOnlyNewQoderJSONLLines() async throws {
        let root = try Fixtures.makeTempDir("qoder-append")
        defer { Fixtures.remove(root) }
        let day = Fixtures.iso(Fixtures.noon(yesterdayOffset: 0))
        let file = root.appendingPathComponent(".qoder/logs/sessions/history.jsonl")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let first = #"{"type":"model.response.completed","request_id":"r1","ts":"\#(day)","data":{"model":"qoder-max","input_tokens":10,"output_tokens":2}}"#
        let second = #"{"type":"model.response.completed","request_id":"r2","ts":"\#(day)","data":{"model":"qoder-max","input_tokens":20,"output_tokens":3}}"#
        try (first + "\n").write(to: file, atomically: true, encoding: .utf8)

        let client = QoderSessionTokenClient(home: root)
        #expect(try await client.fetchSnapshot().history.first?.total == 12)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data((second + "\n").utf8))
        try handle.close()
        #expect(try await client.fetchSnapshot().history.first?.total == 35)
    }
}
