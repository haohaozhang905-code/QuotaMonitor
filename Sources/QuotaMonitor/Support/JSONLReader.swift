import Foundation
import CZstd

/// 分块读取普通或 Zstandard 压缩的 JSONL，不把整个会话展开为字符串或临时文件。
enum JSONLReader {
    /// 只有上次游标正好落在换行符之后，才可安全从文件尾继续；
    /// 否则末行可能仍在写入，下一次改为全文件重算，避免漏掉被补全的 JSON。
    static func isLineBoundary(at offset: Int, in url: URL) -> Bool {
        guard url.pathExtension != "zst" else { return false }
        guard offset > 0, let handle = try? FileHandle(forReadingFrom: url) else { return offset == 0 }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset - 1))
            return try handle.read(upToCount: 1)?.first == 0x0A
        } catch {
            return false
        }
    }

    static func forEachLine(
        at url: URL,
        chunkSize: Int = 64 * 1024,
        startingAt: UInt64 = 0,
        containingAnyOf markerSets: [[Data]] = [],
        _ body: (Data) -> Void
    ) -> Bool {
        readLines(at: url, chunkSize: chunkSize, startingAt: startingAt, containingAnyOf: markerSets) {
            body($0)
            return true
        }
    }

    /// 读取首个非空行后即停止；用于探测身份，不代表整份压缩文件已通过完整性校验。
    static func firstLine(at url: URL) -> Data? {
        var first: Data?
        let success = readLines(at: url, chunkSize: 64 * 1024) {
            first = $0
            return false
        }
        return success ? first : nil
    }

    private static func readLines(
        at url: URL,
        chunkSize: Int,
        startingAt: UInt64 = 0,
        containingAnyOf markerSets: [[Data]] = [],
        _ body: (Data) -> Bool
    ) -> Bool {
        guard chunkSize > 0, let input = try? Input(url: url, startingAt: startingAt) else { return false }

        var buffer = Data()
        // 记录当前未完成行已经检查到的位置。超长 JSON 单行跨越多个 chunk 时，
        // 下一轮只检查新追加的字节，避免每个 chunk 都从行首重扫形成 O(n²)。
        var newlineSearchOffset = 0
        do {
            while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
                guard !Task.isCancelled else { return false }
                buffer.append(chunk)
                var lineStart = buffer.startIndex
                var newlineSearchStart = buffer.index(buffer.startIndex, offsetBy: newlineSearchOffset)
                while let newline = buffer[newlineSearchStart...].firstIndex(of: 0x0A) {
                    guard !Task.isCancelled else { return false }
                    if newline > lineStart {
                        let line = buffer[lineStart..<newline]
                        if Self.matches(line, markerSets: markerSets) {
                            if !body(Data(line)) { return true }
                        }
                    }
                    lineStart = buffer.index(after: newline)
                    newlineSearchStart = lineStart
                }
                if lineStart > buffer.startIndex {
                    buffer.removeSubrange(buffer.startIndex..<lineStart)
                }
                // 当前 buffer 剩余内容已经确认不含换行；下个 chunk 从旧末尾继续。
                newlineSearchOffset = buffer.count
            }
            if !buffer.isEmpty,
               Self.matches(buffer[buffer.startIndex..<buffer.endIndex], markerSets: markerSets) {
                _ = body(buffer)
            }
            return true
        } catch {
            return false
        }
    }

    /// 使用应用内置的只读解码器，不启动外部进程或落盘解压内容。
    private final class Input {
        private var file: FileHandle?
        private var compressed: OpaquePointer?

        init(url: URL, startingAt: UInt64) throws {
            if url.pathExtension == "zst" {
                guard startingAt == 0, let reader = url.withUnsafeFileSystemRepresentation({ path in
                    path.flatMap(qm_zstd_open)
                }) else { throw CocoaError(.fileReadCorruptFile) }
                compressed = reader
            } else {
                let handle = try FileHandle(forReadingFrom: url)
                do { try handle.seek(toOffset: startingAt) }
                catch { try? handle.close(); throw error }
                file = handle
            }
        }

        deinit {
            if let compressed { qm_zstd_close(compressed) }
            try? file?.close()
        }

        func read(upToCount count: Int) throws -> Data? {
            guard let compressed else { return try file?.read(upToCount: count) }
            var data = Data(count: count)
            let size = data.withUnsafeMutableBytes { bytes in
                qm_zstd_read(compressed, bytes.baseAddress, count)
            }
            guard size >= 0 else { throw CocoaError(.fileReadCorruptFile) }
            data.count = Int(size)
            return data
        }
    }

    private static func matches(_ line: Data.SubSequence, markerSets: [[Data]]) -> Bool {
        markerSets.isEmpty || markerSets.contains { markers in
            markers.allSatisfy { line.range(of: $0) != nil }
        }
    }
}
