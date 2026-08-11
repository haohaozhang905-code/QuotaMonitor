import Foundation

/// 分块读取 JSONL，避免把几十 MB 的会话文件一次性复制成完整 String。
enum JSONLReader {
    static func forEachLine(
        at url: URL,
        chunkSize: Int = 64 * 1024,
        _ body: (Data) -> Void
    ) -> Bool {
        guard chunkSize > 0, let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

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
