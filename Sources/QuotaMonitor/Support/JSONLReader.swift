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
        containingAnyOf markerSets: [[Data]] = [],
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
        // 记录当前未完成行已经检查到的位置。超长 JSON 单行跨越多个 chunk 时，
        // 下一轮只检查新追加的字节，避免每个 chunk 都从行首重扫形成 O(n²)。
        var newlineSearchOffset = 0
        do {
            while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                guard !Task.isCancelled else { return false }
                buffer.append(chunk)
                var lineStart = buffer.startIndex
                var newlineSearchStart = buffer.index(buffer.startIndex, offsetBy: newlineSearchOffset)
                while let newline = buffer[newlineSearchStart...].firstIndex(of: 0x0A) {
                    guard !Task.isCancelled else { return false }
                    if newline > lineStart {
                        let line = buffer[lineStart..<newline]
                        if Self.matches(line, markerSets: markerSets) {
                            body(Data(line))
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
                body(buffer)
            }
            return true
        } catch {
            return false
        }
    }

    private static func matches(_ line: Data.SubSequence, markerSets: [[Data]]) -> Bool {
        markerSets.isEmpty || markerSets.contains { markers in
            markers.allSatisfy { line.range(of: $0) != nil }
        }
    }
}
