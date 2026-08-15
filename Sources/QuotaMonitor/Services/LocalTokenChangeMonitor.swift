import CoreServices
import Foundation

/// 递归监听本地 Token 来源目录；事件只负责唤醒刷新，具体文件解析仍由各 client 的缓存负责。
final class LocalTokenChangeMonitor: @unchecked Sendable {
    private let watchedPaths: [String]
    private let onChange: @Sendable () -> Void
    private let queue = DispatchQueue(label: "com.cmsjcm.QuotaMonitor.token-events", qos: .utility)
    private var stream: FSEventStreamRef?

    init(paths: [URL], onChange: @escaping @Sendable () -> Void) {
        watchedPaths = paths
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map(\.path)
        self.onChange = onChange
    }

    func start() {
        guard stream == nil, !watchedPaths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let monitor = Unmanaged<LocalTokenChangeMonitor>
                .fromOpaque(info)
                .takeUnretainedValue()
            monitor.onChange()
        }

        guard let created = FSEventStreamCreate(
            nil,
            callback,
            &context,
            watchedPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents
                    | kFSEventStreamCreateFlagNoDefer
            )
        ) else { return }

        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
    }

    func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit {
        stop()
    }
}
