import Foundation
import Testing
@testable import QuotaMonitor

struct CompressedCodexHistoryTests {
    private let actualCompressedFixture = "KLUv/QRYhQQAEkofHXAlbgOQ/xKVhI3ivu5aPfpVhY1CHGpsuFR9+mICw3vvYeplfxCJPPfimh6KF6PpwLaRqN7+ebM2anc8n+ha9ia/Am14791UUQ4tZVbFsQ14fiFv8kttwij3c9XKjLYIs/Lz6pj+OUBBJIEpwEKR0AARIWF63jHVrAzpNwEFADe5xxmyHq9qkDPQ+OAzgmuAbQ=="

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("qm-compressed-\(UUID())")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("archived_sessions"), withIntermediateDirectories: true)
        return root
    }

    private func metadata(_ id: String, parent: String? = nil) -> String {
        let parentField = parent.map { ",\"forked_from_id\":\"\($0)\"" } ?? ""
        return "{\"type\":\"session_meta\",\"payload\":{\"id\":\"\(id)\"\(parentField)}}\n"
    }

    private func usage(_ input: Int, day: String = "2026-05-28") -> String {
        "{\"timestamp\":\"\(day)T04:01:18Z\",\"payload\":{\"info\":{\"model\":\"gpt-test\",\"total_token_usage\":{\"input_tokens\":\(input),\"output_tokens\":20}}}}\n"
    }

    /// 用原始块构造有效 Zstandard 帧，测试运行时无需编码器或外部程序。
    /// 上方固定夹具另行覆盖实际压缩块和校验和。
    private func frame(_ string: String) -> Data {
        let bytes = Data(string.utf8)
        var result = Data([0x28, 0xB5, 0x2F, 0xFD, 0xA0])
        let size = UInt32(bytes.count)
        result.append(contentsOf: (0..<4).map { UInt8(truncatingIfNeeded: size >> ($0 * 8)) })
        var offset = 0
        repeat {
            let count = min(128 * 1024, bytes.count - offset)
            let header = UInt32(count << 3) | (offset + count == bytes.count ? 1 : 0)
            result.append(contentsOf: (0..<3).map { UInt8(truncatingIfNeeded: header >> ($0 * 8)) })
            result.append(bytes[offset..<(offset + count)])
            offset += count
        } while offset < bytes.count
        return result
    }

    @Test func readsRealCompressedHistoryAndDoesNotTouchSource() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("archived_sessions/rollout-2026-05-28-example.jsonl.zst")
        let original = try #require(Data(base64Encoded: actualCompressedFixture))
        try original.write(to: file)
        let before = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let history = try await CodexSessionTokenClient(root: root).fetchSnapshot().history
        #expect(history.map(\.id) == ["2026-05-28"])
        #expect(history.first?.total == 120)
        #expect(try Data(contentsOf: file) == original)
        let after = try file.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        #expect(before.contentModificationDate == after.contentModificationDate)
        #expect(before.fileSize == after.fileSize)
        #expect(!FileManager.default.fileExists(atPath: file.deletingPathExtension().path))
    }

    @Test func prefersPlainCopyAndDeduplicatesAcrossDirectoriesAndSessionIDs() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = root.appendingPathComponent("sessions/rollout-2026-05-28-a.jsonl")
        let content = metadata("same-session") + usage(100)
        try (content + usage(200)).write(to: plain, atomically: true, encoding: .utf8)
        try frame(content).write(to: plain.appendingPathExtension("zst"))
        try frame(content).write(to: root.appendingPathComponent("archived_sessions/renamed-copy.jsonl.zst"))
        let client = CodexSessionTokenClient(root: root)
        #expect(try await client.fetchSnapshot().history.first?.total == 220)
        let handle = try FileHandle(forWritingTo: plain)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(usage(300).utf8))
        try handle.close()
        #expect(try await client.fetchSnapshot().history.first?.total == 320)
    }

    @Test func deduplicatesFilesWithoutMetadataAndKeepsForkBoundaryAcrossFormats() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = root.appendingPathComponent("sessions/rollout-2026-05-28-no-meta.jsonl")
        try usage(50).write(to: plain, atomically: true, encoding: .utf8)
        try frame(usage(50)).write(to: root.appendingPathComponent("archived_sessions/rollout-2026-05-28-no-meta.jsonl.zst"))
        let parent = metadata("parent") + usage(100) + usage(200)
        try frame(parent).write(to: root.appendingPathComponent("archived_sessions/parent.jsonl.zst"))
        let child = metadata("child", parent: "parent") + usage(100) + usage(200) + usage(250, day: "2026-05-29")
        try child.write(to: root.appendingPathComponent("sessions/child.jsonl"), atomically: true, encoding: .utf8)
        let grandchild = metadata("grandchild", parent: "child") + usage(100) + usage(200) + usage(250) + usage(300, day: "2026-05-30")
        try frame(grandchild).write(to: root.appendingPathComponent("sessions/grandchild.jsonl.zst"))
        let history = try await CodexSessionTokenClient(root: root).fetchSnapshot().history
        #expect(history.first { $0.id == "2026-05-28" }?.total == 290)
        #expect(history.first { $0.id == "2026-05-29" }?.total == 50)
        #expect(history.first { $0.id == "2026-05-30" }?.total == 50)
    }

    @Test func joinsPathAndSessionAliasesEvenWhenOneCopyHasAnUnreadableHeader() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("sessions/rollout-2026-05-28-first.jsonl")
        let second = root.appendingPathComponent("archived_sessions/rollout-2026-05-28-second.jsonl")
        let content = metadata("alias-session") + usage(100)
        try content.write(to: first, atomically: true, encoding: .utf8)
        let client = CodexSessionTokenClient(root: root)
        #expect(try await client.fetchSnapshot().history.first?.total == 120)
        try content.write(to: second, atomically: true, encoding: .utf8)
        try frame(content).write(to: second.appendingPathExtension("zst"))
        try Data("corrupt compressed header".utf8).write(to: first.appendingPathExtension("zst"))
        #expect(try await client.fetchSnapshot().history.first?.total == 120)
    }

    @Test func survivesCacheReloadAndFormatRoundTripWithoutAddingOldTotals() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = root.appendingPathComponent("sessions/rollout-round-trip.jsonl")
        let compressed = plain.appendingPathExtension("zst")
        let cache = root.appendingPathComponent("cache.json")
        let content = metadata("round-trip") + usage(100)
        try content.write(to: plain, atomically: true, encoding: .utf8)
        let first = CodexSessionTokenClient(root: root, persistentCacheURL: cache)
        #expect(try await first.fetchSnapshot().history.first?.total == 120)
        // 模拟旧 V5 缓存缺少新增可选字段，确认升级时仍能读取并重算。
        let old = String(decoding: try Data(contentsOf: cache), as: UTF8.self)
            .replacingOccurrences(of: "\"isCompressed\":false,", with: "")
            .replacingOccurrences(of: ",\"isCompressed\":false", with: "")
        try Data(old.utf8).write(to: cache)
        try frame(content + usage(200)).write(to: compressed)
        try FileManager.default.removeItem(at: plain) // 仅模拟临时夹具的格式迁移
        let second = CodexSessionTokenClient(root: root, persistentCacheURL: cache)
        #expect(try await second.fetchSnapshot().history.first?.total == 220)
        let reloaded = CodexSessionTokenClient(root: root, persistentCacheURL: cache)
        #expect(try await reloaded.fetchSnapshot().history.first?.total == 220)
        try (content + usage(300)).write(to: plain, atomically: true, encoding: .utf8)
        #expect(try await reloaded.fetchSnapshot().history.first?.total == 320)
    }

    @Test func rejectsTruncatedAndCorruptFramesWithoutSavingPartialTotals() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/rollout-broken.jsonl.zst")
        let complete = frame(metadata("broken") + usage(100) + usage(200))
        try complete.dropLast(5).write(to: file)
        let client = CodexSessionTokenClient(root: root, persistentCacheURL: root.appendingPathComponent("cache.json"))
        await #expect(throws: (any Error).self) { try await client.fetchSnapshot() }
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("cache.json").path))
        try complete.write(to: file)
        #expect(try await client.fetchSnapshot().history.first?.total == 220)
        try frame(metadata("broken") + usage(500)).dropLast(5).write(to: file)
        #expect(try await client.fetchSnapshot().history.first?.total == 220)
        var corrupt = try #require(Data(base64Encoded: actualCompressedFixture))
        corrupt[corrupt.count - 1] ^= 0xFF // 破坏末尾校验和，检查已读用量不会作为成功结果保留
        try corrupt.write(to: file)
        #expect(try await client.fetchSnapshot().history.first?.total == 220)
        try Data().write(to: file)
        #expect(try await client.fetchSnapshot().history.first?.total == 220)
    }

    @Test func rebuildsLegacyIncrementalCacheInsteadOfReusingInflatedTotals() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let plain = root.appendingPathComponent("sessions/rollout-legacy.jsonl")
        let cacheURL = root.appendingPathComponent("cache.json")
        try (metadata("legacy") + usage(100)).write(to: plain, atomically: true, encoding: .utf8)
        #expect(try await CodexSessionTokenClient(root: root, persistentCacheURL: cacheURL).fetchSnapshot().history.first?.total == 120)
        var envelope = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: cacheURL)) as? [String: Any])
        var entries = try #require(envelope["entries"] as? [String: [String: Any]])
        let entryKey = try #require(entries.keys.first)
        var entry = try #require(entries[entryKey])
        entry.removeValue(forKey: "aggregationRevision")
        for name in ["modelByDay", "totalsByDay"] {
            var values = try #require(entry[name] as? [String: [String: Int]])
            for key in values.keys { values[key]?["input", default: 0] += 186_539 }
            entry[name] = values
        }
        entries[entryKey] = entry
        envelope["entries"] = entries
        try JSONSerialization.data(withJSONObject: envelope).write(to: cacheURL)
        let migrated = CodexSessionTokenClient(root: root, persistentCacheURL: cacheURL)
        #expect(try await migrated.fetchSnapshot().history.first?.total == 120)
        #expect(try await CodexSessionTokenClient(root: root, persistentCacheURL: cacheURL).fetchSnapshot().history.first?.total == 120)
    }

    @Test func compressedReaderHandlesLongLinesConcatenatedFramesAndMissingFinalNewline() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/stream.jsonl.zst")
        let long = String(repeating: "中", count: 100_000)
        try (frame(long + "\n") + frame("last")).write(to: file)
        var lines: [Data] = []
        #expect(JSONLReader.forEachLine(at: file, chunkSize: 7) { lines.append($0) })
        #expect(lines == [Data(long.utf8), Data("last".utf8)])
        #expect(JSONLReader.firstLine(at: file) == Data(long.utf8))
        #expect(!JSONLReader.forEachLine(at: file, startingAt: 5) { _ in })
        #expect(!JSONLReader.isLineBoundary(at: 0, in: file))
    }

    @Test func rejectsUnreadableCompressedSourceAndHonorsCancellation() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("sessions/rollout-unreadable.jsonl.zst")
        try frame(metadata("unreadable") + usage(100)).write(to: file)
        let client = CodexSessionTokenClient(root: root)
        #expect(try await client.fetchSnapshot().history.first?.total == 120)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: file.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path) }
        #expect(try await client.fetchSnapshot().history.first?.total == 120)
        await #expect(throws: (any Error).self) {
            try await CodexSessionTokenClient(root: root).fetchSnapshot()
        }
        let cancelled = Task { () throws -> TokenSourceSnapshot in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await client.fetchSnapshot()
        }
        await #expect(throws: CancellationError.self) { try await cancelled.value }
    }
}
