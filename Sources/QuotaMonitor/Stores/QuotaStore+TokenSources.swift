import Foundation
import OSLog

struct LocalTokenRefreshProgress: Equatable, Sendable {
    let completedSources: Int
    let totalSources: Int

    var fraction: Double {
        guard totalSources > 0 else { return 0 }
        return Double(completedSources) / Double(totalSources)
    }
}

/// 文件变化唤醒的轻量状态机。第一条事件确定刷新截止时间，后续事件只合并；
/// 扫描期间出现的新变化会在本轮结束后补一次刷新，不能取消正在执行的扫描。
struct TokenRefreshWakeupState: Equatable, Sendable {
    private(set) var isDebounceScheduled = false
    private(set) var needsRefreshAfterCurrentScan = false

    mutating func requestRefresh(isScanning: Bool) -> Bool {
        if isScanning {
            needsRefreshAfterCurrentScan = true
            return false
        }
        guard !isDebounceScheduled else { return false }
        isDebounceScheduled = true
        return true
    }

    mutating func debounceDidFire(isScanning: Bool) -> Bool {
        isDebounceScheduled = false
        if isScanning {
            needsRefreshAfterCurrentScan = true
            return false
        }
        return true
    }

    mutating func scanDidFinish() -> Bool {
        guard needsRefreshAfterCurrentScan else { return false }
        needsRefreshAfterCurrentScan = false
        guard !isDebounceScheduled else { return false }
        isDebounceScheduled = true
        return true
    }
}

private enum TokenRefreshTaskTimeout {
    static func run<T: Sendable>(
        _ timeout: Duration,
        operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}

struct TokenHistorySnapshot: Codable, Equatable {
    let version: Int
    let tokenBuckets: [TokenUsageBucket]
    let claudeDesktopStale: Bool
    let tokenUpdatedAt: Date?
}

private enum TokenRefreshResult: Sendable {
    case local(sourceID: DataSourceID, platform: TokenPlatform, client: TokenClient?, snapshot: TokenSourceSnapshot?)
    case desktop(TokenSourceSnapshot?)
    case claudeCrossCheck(TokenSourceSnapshot?)
    case additional(AdditionalLocalTokenScanResult?)
}

private struct TokenSourceDescriptor: Sendable {
    let sourceIDs: [DataSourceID]
    let timeout: Duration?
    let timeoutResult: TokenRefreshResult
    let operation: @Sendable () async -> TokenRefreshResult?

    func run() async -> TokenRefreshResult {
        let result: TokenRefreshResult?
        if let timeout {
            result = await TokenRefreshTaskTimeout.run(timeout, operation: operation)
        } else {
            result = await operation()
        }
        return result ?? timeoutResult
    }
}

extension QuotaStore {
    func monitorTokenSources() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.tokenRefreshInterval)
            await refreshTokenSources()
        }
    }

    func startTokenChangeMonitor() {
        tokenChangeMonitor?.stop()
        tokenChangeMonitor = LocalTokenChangeMonitor(paths: Self.defaultTokenWatchPaths()) { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleTokenRefresh()
            }
        }
        tokenChangeMonitor?.start()
    }

    private func scheduleTokenRefresh() {
        guard tokenRefreshWakeupState.requestRefresh(isScanning: isRefreshingTokenSources) else { return }
        scheduleTokenRefreshTask()
    }

    private func scheduleTokenRefreshTask() {
        tokenChangeDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, let self else { return }
            let shouldRefresh = self.tokenRefreshWakeupState.debounceDidFire(
                isScanning: self.isRefreshingTokenSources
            )
            self.tokenChangeDebounceTask = nil
            guard shouldRefresh else { return }
            await self.refreshTokenSources()
        }
    }

    private static func defaultTokenWatchPaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var paths = [
            CodexEnvironment.homeDirectory,
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(".workbuddy/traces", isDirectory: true),
            home.appendingPathComponent(".qoder", isDirectory: true),
            home.appendingPathComponent("Library/Application Support/Qoder/SharedClientCache/cli/projects", isDirectory: true),
            home.appendingPathComponent(".cc-switch", isDirectory: true)
        ]
        let environment = ProcessInfo.processInfo.environment
        paths.append(contentsOf: LocalToolTokenSource.additional.flatMap {
            $0.resolvedRoots(home: home, environment: environment)
        })
        var seen = Set<String>()
        return paths.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func localTokenSource(
        _ sourceID: DataSourceID,
        platform: TokenPlatform,
        client: TokenClient?,
        timeout: Duration?,
        fetch: @escaping @Sendable () async throws -> TokenSourceSnapshot
    ) -> TokenSourceDescriptor {
        TokenSourceDescriptor(
            sourceIDs: [sourceID],
            timeout: timeout,
            timeoutResult: .local(sourceID: sourceID, platform: platform, client: client, snapshot: nil),
            operation: {
                .local(sourceID: sourceID, platform: platform, client: client, snapshot: try? await fetch())
            }
        )
    }

    /// 拉取全部本地 Token 来源并落盘快照；后台每 5 分钟刷新一次。
    ///
    /// Codex / Claude 命令行 / WorkBuddy 直接解析本地文件，不依赖 cc-switch；
    /// Claude Desktop 使用 cc-switch 请求日志。
    func refreshTokenSources() async {
        guard !isRefreshingTokenSources else { return }
        isRefreshingTokenSources = true
        let codexClient = codexSessionTokenClient
        let claudeClient = claudeSessionTokenClient
        let workBuddyClient = workBuddyTraceClient
        let ccSwitchClient = ccSwitchUsageClient
        let additionalClient = additionalLocalTokenClient
        let qoderClient = qoderSessionTokenClient
        let sourceDescriptors: [TokenSourceDescriptor] = [
            Self.localTokenSource(DataSourceCatalog.codexToken, platform: .codex, client: nil, timeout: nil) {
                try await codexClient.fetchSnapshot()
            },
            Self.localTokenSource(DataSourceCatalog.claudeCode, platform: .claude, client: .cli, timeout: Self.tokenSourceTimeout) {
                try await claudeClient.fetchSnapshot()
            },
            Self.localTokenSource(DataSourceCatalog.workBuddy, platform: .workbuddy, client: nil, timeout: Self.tokenSourceTimeout) {
                try await workBuddyClient.fetchSnapshot()
            },
            TokenSourceDescriptor(
                sourceIDs: [DataSourceCatalog.claudeDesktop], timeout: Self.tokenSourceTimeout,
                timeoutResult: .desktop(nil), operation: {
                    .desktop(await ccSwitchClient.fetchSnapshot(appType: "claude-desktop"))
                }
            ),
            TokenSourceDescriptor(
                sourceIDs: [], timeout: Self.tokenSourceTimeout,
                timeoutResult: .claudeCrossCheck(nil), operation: {
                    .claudeCrossCheck(await ccSwitchClient.fetchSnapshot(appType: "claude", client: .cli))
                }
            ),
            TokenSourceDescriptor(
                sourceIDs: DataSourceCatalog.additional, timeout: Self.tokenSourceTimeout,
                timeoutResult: .additional(nil), operation: { .additional(try? await additionalClient.fetchScanResult()) }
            ),
            Self.localTokenSource(DataSourceCatalog.qoder, platform: .qoder, client: nil, timeout: Self.tokenSourceTimeout) {
                try await qoderClient.fetchSnapshot()
            },
        ]
        var seenSourceIDs: Set<DataSourceID> = []
        sourceDescriptors.flatMap(\.sourceIDs)
            .filter { seenSourceIDs.insert($0).inserted }
            .forEach { beginSourceAttempt($0) }
        let totalSources = sourceDescriptors.count
        tokenProgressRevealTask?.cancel()
        tokenProgressRevealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, self.isRefreshingTokenSources else { return }
            self.localTokenRefreshProgress = LocalTokenRefreshProgress(completedSources: 0, totalSources: totalSources)
        }
        defer {
            tokenProgressRevealTask?.cancel()
            tokenProgressRevealTask = nil
            localTokenRefreshProgress = nil
            isRefreshingTokenSources = false
            if tokenRefreshWakeupState.scanDidFinish() {
                scheduleTokenRefreshTask()
            }
        }

        var completed = 0
        await withTaskGroup(of: TokenRefreshResult.self) { group in
            for sourceTask in sourceDescriptors {
                group.addTask(priority: .utility) { await sourceTask.run() }
            }
            for await result in group {
                applyTokenRefreshResult(result)
                completed += 1
                if localTokenRefreshProgress != nil {
                    localTokenRefreshProgress = LocalTokenRefreshProgress(completedSources: completed, totalSources: totalSources)
                }
                await Task.yield()
            }
        }

        lastTokenUpdatedAt = .now
        saveTokenSnapshotIfNeeded()
        logger.info(
            "sources codex=\(Self.todayTotal(self.tokenHistory)) claude=\(Self.todayTotal(self.claudeHistory)) desktop=\(Self.todayTotal(self.claudeDesktopHistory)) workbuddy=\(Self.todayTotal(self.workBuddyHistory)) additional=\(Self.todayTotal(self.totalTokenHistory) - [Self.todayTotal(self.tokenHistory), Self.todayTotal(self.claudeHistory), Self.todayTotal(self.claudeDesktopHistory), Self.todayTotal(self.workBuddyHistory)].reduce(0, +)) deepseek=\(Self.todayTotal(self.deepSeekHistory)) desktopStale=\(self.claudeDesktopStale)"
        )
        refreshTokenDerivedState()
        reminderRevision &+= 1
    }

    private func applyTokenRefreshResult(_ result: TokenRefreshResult) {
        var freshBuckets = tokenBuckets
        switch result {
        case let .local(sourceID, platform, client, snapshot):
            guard let snapshot else {
                finishSource(sourceID, state: .failed)
                logger.warning("Local token refresh failed for \(sourceID.id, privacy: .public); retaining last good snapshot")
                break
            }
            Self.replaceBuckets(
                in: &freshBuckets,
                matching: { $0.platform == platform && (client == nil || $0.client == client) },
                with: snapshot.buckets
            )
            finishSource(sourceID, state: snapshot.buckets.isEmpty ? .noData : .ready, validRecordCount: snapshot.buckets.count)
        case let .desktop(snapshot):
            if let snapshot {
                Self.replaceBuckets(in: &freshBuckets, matching: { $0.platform == .claude && $0.client == .desktop }, with: snapshot.buckets)
                claudeDesktopStale = !CCSwitchUsageClient.isCCSwitchRunning()
                finishSource(
                    DataSourceCatalog.claudeDesktop,
                    state: snapshot.buckets.isEmpty ? .noData : (claudeDesktopStale ? .stale : .ready),
                    validRecordCount: snapshot.buckets.count
                )
            } else {
                claudeDesktopStale = true
                finishSource(DataSourceCatalog.claudeDesktop, state: .failed)
                logger.warning("Claude Desktop token refresh failed; retaining last good snapshot")
            }
        case let .claudeCrossCheck(snapshot):
            if let snapshot { crossCheckClaudeSource(cc: snapshot.history) }
        case let .additional(scanResult):
            guard let scanResult else {
                DataSourceCatalog.additional.forEach { finishSource($0, state: .failed) }
                logger.warning("Additional local token refresh failed; retaining last good snapshot")
                break
            }
            let platforms = Set(LocalToolTokenSource.additional.map(\.platform))
            Self.replaceBuckets(in: &freshBuckets, matching: { platforms.contains($0.platform) }, with: scanResult.snapshots.flatMap(\.buckets))
            for diagnostic in scanResult.diagnostics {
                finishSource(
                    diagnostic.id,
                    state: diagnostic.state,
                    candidateFileCount: diagnostic.candidateFileCount,
                    validRecordCount: diagnostic.validRecordCount,
                    usesLastGoodData: diagnostic.usesLastGoodData
                )
            }
        }
        tokenBuckets = TokenUsageBucket.combining(freshBuckets)
    }

    private static func replaceBuckets(
        in buckets: inout [TokenUsageBucket],
        matching predicate: (TokenUsageBucket) -> Bool,
        with replacement: [TokenUsageBucket]
    ) {
        buckets.removeAll(where: predicate)
        buckets.append(contentsOf: replacement)
    }

    func loadTokenSnapshot() {
        guard let tokenSnapshotURL, let data = try? Data(contentsOf: tokenSnapshotURL) else { return }
        let decoder = JSONDecoder()
        guard let snapshot = try? decoder.decode(TokenHistorySnapshot.self, from: data),
              snapshot.version == 2 || snapshot.version == 3 else { return }
        tokenBuckets = TokenUsageBucket.combining(snapshot.tokenBuckets)
        claudeDesktopStale = snapshot.claudeDesktopStale
        lastTokenUpdatedAt = snapshot.tokenUpdatedAt ?? Self.snapshotModificationDate(tokenSnapshotURL)
        restoreTokenSourceHealthFromCache()
        // Keep the old file intact until a successful refresh writes V3.
        lastSavedTokenSnapshot = snapshot.version == 3 ? snapshot : nil
    }

    private static func snapshotModificationDate(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    private func restoreTokenSourceHealthFromCache() {
        guard let cachedAt = lastTokenUpdatedAt else { return }
        let descriptors = DataSourceCatalog.all.filter { $0.kind == .localToken || $0.kind == .cloudToken }
        for descriptor in descriptors {
            let matchingBuckets = tokenBuckets.filter {
                $0.platform.rawValue == descriptor.id.platform && $0.client.rawValue == descriptor.id.client
            }
            guard !matchingBuckets.isEmpty else { continue }
            sourceStates[descriptor.id, default: TokenSourceRuntimeState()].restoreFromCache(
                at: cachedAt,
                validRecordCount: matchingBuckets.count,
                isStale: descriptor.id == DataSourceCatalog.claudeDesktop && claudeDesktopStale
            )
        }
    }

    private func saveTokenSnapshotIfNeeded() {
        guard let tokenSnapshotURL else { return }
        let snapshot = TokenHistorySnapshot(
            version: 3,
            tokenBuckets: tokenBuckets,
            claudeDesktopStale: claudeDesktopStale,
            tokenUpdatedAt: lastTokenUpdatedAt
        )
        guard snapshot != lastSavedTokenSnapshot,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        let directory = tokenSnapshotURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard (try? data.write(to: tokenSnapshotURL, options: .atomic)) != nil else { return }
        lastSavedTokenSnapshot = snapshot
    }

    private static func todayTotal(_ history: [DailyTokenUsage]) -> Int {
        let key = DailyTokenUsage.dayKey(for: .now)
        return history.first { $0.id == key }?.total ?? 0
    }

    private func crossCheckClaudeSource(cc: [DailyTokenUsage]) {
        let todayKey = DailyTokenUsage.dayKey(for: .now)
        guard let ccTotal = cc.first(where: { $0.id == todayKey })?.total,
              let transcriptTotal = claudeHistory.first(where: { $0.id == todayKey })?.total,
              transcriptTotal > 0, ccTotal > 0 else { return }
        let diff = abs(Double(ccTotal - transcriptTotal)) / Double(max(transcriptTotal, 1))
        if diff > 0.05 {
            logger.warning(
                "Claude transcript vs cc-switch mismatch \(String(format: "%.1f", diff * 100), privacy: .public)%"
            )
        }
    }
}
