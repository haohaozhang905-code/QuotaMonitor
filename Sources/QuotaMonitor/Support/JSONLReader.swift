import Foundation

/// 分块读取 JSONL，避免把几十 MB 的会话文件一次性复制成完整 String。
enum JSONLReader {
    /// 只有上次游标正好落在换行符之后，才可安全从文件尾继续；
    /// 否则末行可能仍在写入，下一次改为全文件重算，避免漏掉被补全的 JSON。
    static func isLineBoundary(at offset: Int, in url: URL) -> Bool {
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
        _ body: (Data) -> Void
    ) -> Bool {
        guard chunkSize > 0, let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: startingAt)
        } catch {
            return false
        }

        var buffer = Data()
        do {
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                buffer.append(chunk)
                var lineStart = buffer.startIndex
                while let newline = buffer[lineStart...].firstIndex(of: 0x0A) {
                    if newline > lineStart {
                        body(Data(buffer[lineStart..<newline]))
                    }
                    lineStart = buffer.index(after: newline)
                }
                if lineStart > buffer.startIndex {
                    buffer.removeSubrange(buffer.startIndex..<lineStart)
                }
            }
            if !buffer.isEmpty { body(buffer) }
            return true
        } catch {
            return false
        }
    }
}
