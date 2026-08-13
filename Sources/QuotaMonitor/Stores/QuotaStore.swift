import Foundation
import Observation
import OSLog

struct LocalTokenRefreshProgress: Equatable, Sendable {
    let completedSources: Int
    let totalSources: Int

    var fraction: Double {
        guard totalSources > 0 else { return 0 }
        return Double(completedSources) / Double(totalSources)
    }
}

@MainActor @Observable
final class QuotaStore {
    private struct TokenHistorySnapshot: Codable, Equatable {
        let version: Int
        let tokenHistory: [DailyTokenUsage]
        let claudeHistory: [DailyTokenUsage]
        let claudeDesktopHistory: [DailyTokenUsage]
        let workBuddyHistory: [DailyTokenUsage]
        let codexDeepSeekHistory: [DailyTokenUsage]
        let claudeDeepSeekHistory: [DailyTokenUsage]
        let desktopDeepSeekHistory: [DailyTokenUsage]
        let workbuddyDeepSeekHistory: [DailyTokenUsage]
        let tokenBuckets: [TokenUsageBucket]
        let claudeDesktopStale: Bool
        let tokenUpdatedAt: Date?
    }

    private enum TokenRefreshResult: Sendable {
        case codex(TokenSourceSnapshot?)
        case claude(TokenSourceSnapshot?)
        case workBuddy(TokenSourceSnapshot?)
        case desktop(TokenSourceSnapshot?)
        case claudeCrossCheck(TokenSourceSnapshot?)
        case additional([TokenSourceSnapshot]?)
        case qoder(TokenSourceSnapshot?)
    }

    private(set) var providers: [ProviderUsage] = []
    private(set) var lastUpdated: Date?
    private(set) var errorMessageKey: String?
    private(set) var isRefreshing = false
    private(set) var isRefreshingTokenSources = false
    private(set) var localTokenRefreshProgress: LocalTokenRefreshProgress?
    private(set) var lastTokenUpdatedAt: Date?
    private(set) var hasCompletedInitialRefresh = false
    private(set) var codexResetCredits: CodexResetCredits?
    private(set) var tokenHistory: [DailyTokenUsage] = []
    /// 按日期、平台、客户端和模型拆分的原始聚合桶，供 Token 看板的模型维度查询。
    private(set) var tokenBuckets: [TokenUsageBucket] = []
    private(set) var codexRoute: CodexRoute = .unknown
    /// Claude 走官方还是 DeepSeek 路由（由本地 settings 推断）。
    private(set) var claudeRoute: ClaudeRoute = .unknown
    /// Claude Desktop 独立路由；不能与 Claude Code 的 provider 合并判断。
    private(set) var claudeDesktopRoute: ClaudeRoute = .unknown
    private var lastDeepSeekBalance: DeepSeekBalanceSnapshot?
    /// 各工具按天用量（Codex / Claude 命令行 / Claude 桌面版 / WorkBuddy）。
    private(set) var claudeHistory: [DailyTokenUsage] = []
    private(set) var claudeDesktopHistory: [DailyTokenUsage] = []
    private(set) var workBuddyHistory: [DailyTokenUsage] = []
    /// Claude 桌面版依赖 cc-switch 本地代理；cc-switch 未运行时数据可能缺失。
    private(set) var claudeDesktopStale = false
    /// 各工具内部仅含 DeepSeek 模型的用量（稀疏，不做补零）。
    private(set) var codexDeepSeekHistory: [DailyTokenUsage] = []
    private(set) var claudeDeepSeekHistory: [DailyTokenUsage] = []
    private(set) var desktopDeepSeekHistory: [DailyTokenUsage] = []
    private(set) var workbuddyDeepSeekHistory: [DailyTokenUsage] = []
    /// 跨工具汇总的 DeepSeek 用量（稀疏），用于余额消耗估算与官方/DeepSeek 拆分。
    private(set) var deepSeekHistory: [DailyTokenUsage] = []

    private let codexDirectClient = CodexDirectClient()
    private let deepSeekBalanceClient = DeepSeekBalanceClient()
    private let codexSessionTokenClient = CodexSessionTokenClient()
    private let claudeSessionTokenClient = ClaudeSessionTokenClient()
    private let workBuddyTraceClient = WorkBuddyTraceClient()
    private let ccSwitchUsageClient = CCSwitchUsageClient()
    private let additionalLocalTokenClient = AdditionalLocalTokenClient()
    private let qoderSessionTokenClient = QoderSessionTokenClient()
    private let logger = Logger(subsystem: "com.cmsjcm.QuotaMonitor", category: "quota")
    private let tokenSnapshotURL: URL?
    private var lastSavedTokenSnapshot: TokenHistorySnapshot?
    private var tokenTask: Task<Void, Never>?
    private var tokenProgressRevealTask: Task<Void, Never>?

    init() {
        tokenSnapshotURL = Self.defaultTokenSnapshotURL()
        let detectedClaudeRoutes = ClaudeRouteDetector.detectRoutes()
        codexRoute = CodexRouteDetector.detect()
        claudeRoute = detectedClaudeRoutes.code
        claudeDesktopRoute = detectedClaudeRoutes.desktop
        loadTokenSnapshot()
    }

    var lowestRemaining: Double? {
        providers.flatMap { [$0.session?.remainingPercent, $0.weekly?.remainingPercent] }.compactMap { $0 }.min()
    }

    /// 菜单栏文字：额度（DeepSeek 余额或官方剩余百分比）+ 今日跨工具总用量。
    var menuBarText: String {
        let quota: String
        if codexRoute == .deepseek, let provider = deepSeekProvider {
            quota = QuotaFormatters.money(provider.balanceAmount ?? 0, currency: provider.balanceCurrency)
        } else {
            quota = QuotaFormatters.percent(lowestRemaining)
        }
        let today = todayTokenUsage?.total ?? 0
        guard today > 0 else { return quota }
        return "\(quota) · \(QuotaFormatters.tokens(today))"
    }

    /// DeepSeek 余额行。Codex 走 DeepSeek 时它挂在 Codex provider；
    /// Claude 单独走 DeepSeek 时则使用独立的 deepseek provider。
    private var deepSeekProvider: ProviderUsage? {
        providers.first { $0.providerId.lowercased() == "deepseek" && $0.balanceLine != nil }
            ?? providers.first { $0.providerId.lowercased() == "codex" && $0.balanceLine != nil }
    }

    var health: QuotaHealth { QuotaHealth(remaining: lowestRemaining) }

    /// DeepSeek 共享余额（跨 Codex / Claude 通道），未获取时为 nil。
    var deepSeekBalance: Double? { deepSeekProvider?.balanceAmount }
    var deepSeekCurrency: String? { deepSeekProvider?.balanceCurrency }
    var deepSeekDays: Int? { deepSeekProvider?.balanceDays }

    /// 是否双通道都走 DeepSeek（菜单栏合并为单槽位）。
    var bothRoutesDeepSeek: Bool {
        codexRoute == .deepseek && claudeUsesDeepSeek
    }

    var claudeUsesDeepSeek: Bool {
        claudeRoute == .deepseek || claudeDesktopRoute == .deepseek
    }

    var claudeRouteSummary: ClaudeRoute {
        ClaudeRouteSnapshot(code: claudeRoute, desktop: claudeDesktopRoute).summary
    }

    /// 对用户展示的 Claude 路由：只要任一 Claude 通道使用 DeepSeek，
    /// 下拉框、菜单栏与主面板统一显示 DeepSeek 路由。
    var claudeDisplayRoute: ClaudeRoute {
        ClaudeRouteSnapshot(code: claudeRoute, desktop: claudeDesktopRoute).displayRoute
    }

    /// 全部工具的按天合计。来源保留完整可用历史，视图层再按今日/7 日/30 日取窗口。
    var totalTokenHistory: [DailyTokenUsage] {
        // 以 buckets 为唯一汇总来源，使新接入工具自动进入总量、趋势和热力图，
        // 不再要求为每一种平台增加一组专用 history 属性。
        TokenSourceSnapshot(buckets: tokenBuckets).history
    }

    private func tokenUsage(for day: Date) -> DailyTokenUsage? {
        totalTokenHistory.first { $0.id == DailyTokenUsage.dayKey(for: day) }
    }

    var todayTokenUsage: DailyTokenUsage? { tokenUsage(for: .now) }

    var latestUpdatedAt: Date? {
        [lastUpdated, lastTokenUpdatedAt].compactMap { $0 }.max()
    }

    var yesterdayTokenUsage: DailyTokenUsage? {
        Calendar.current.date(byAdding: .day, value: -1, to: .now).flatMap { tokenUsage(for: $0) }
    }

    /// 主面板和下拉框共享的展示快照。任何百分比、Top N 与可用性判断都在模型层统一完成。
    var presentationSnapshot: QuotaPresentationSnapshot {
        QuotaPresentationSnapshot.make(
            providers: providers,
            updatedAt: latestUpdatedAt,
            errorMessageKey: errorMessageKey,
            isRefreshing: isRefreshing,
            codexRoute: codexRoute,
            claudeRoute: claudeRouteSummary,
            totalHistory: totalTokenHistory,
            buckets: tokenBuckets
        )
    }

    /// 下拉框只读取这份快照，避免在菜单组装处重新判断路由、额度字段和统计窗口。
    var dropdownPresentation: DropdownPresentation {
        QuotaPresentationSnapshot.makeDropdown(
            presentation: presentationSnapshot,
            providers: providers,
            codexRoute: codexRoute,
            claudeRoute: claudeDisplayRoute,
            deepSeekBalance: deepSeekBalance,
            deepSeekCurrency: deepSeekCurrency,
            deepSeekDays: deepSeekDays
        )
    }

    func tokenDashboardSnapshot(for period: TokenDashboardPeriod) -> TokenDashboardPresentation {
        QuotaPresentationSnapshot.makeTokenDashboard(
            period: period,
            totalHistory: totalTokenHistory,
            buckets: tokenBuckets
        )
    }

    func start() async {
        // 快照已在 init 同步恢复；本地 token 与网络额度并行更新，互不阻塞首屏。
        tokenTask = Task { await monitorTokenSources() }
        defer { tokenTask?.cancel() }
        await refreshAll()
        hasCompletedInitialRefresh = true
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            await refresh()
        }
    }

    func refreshAll() async {
        async let local: Void = refreshTokenSources()
        async let quota: Void = refresh()
        _ = await (local, quota)
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let previousCodexRoute = codexRoute
        let previousClaudeRoute = claudeRoute
        let previousDesktopRoute = claudeDesktopRoute
        let detectedClaudeRoutes = ClaudeRouteDetector.detectRoutes()
        claudeRoute = detectedClaudeRoutes.code
        claudeDesktopRoute = detectedClaudeRoutes.desktop
        let detectedRoute = CodexRouteDetector.detect()
        if detectedRoute != previousCodexRoute
            || claudeRoute != previousClaudeRoute
            || claudeDesktopRoute != previousDesktopRoute {
            resetRouteDependentState(
                codexRoute: detectedRoute,
                previousCodexRoute: previousCodexRoute,
                previousClaudeUsesDeepSeek: previousClaudeRoute == .deepseek || previousDesktopRoute == .deepseek
            )
        }
        switch codexRoute {
        case .official:
            applyDirectCodex(try? await codexDirectClient.fetch())
            if claudeUsesDeepSeek {
                applyDeepSeekBalance(try? await deepSeekBalanceClient.fetch())
            }
        case .deepseek:
            applyDeepSeekBalance(try? await deepSeekBalanceClient.fetch())
        case .unknown:
            if claudeUsesDeepSeek {
                applyDeepSeekBalance(try? await deepSeekBalanceClient.fetch())
            } else {
                errorMessageKey = "error.quotaUnavailable"
            }
        }
    }

    /// 路由切换时立即撤下上一条路由的数据，避免官方额度和 DeepSeek 余额短暂混显。
    private func resetRouteDependentState(
        codexRoute route: CodexRoute,
        previousCodexRoute: CodexRoute,
        previousClaudeUsesDeepSeek: Bool
    ) {
        let codexChanged = route != previousCodexRoute
        let deepSeekTopologyChanged = (route == .deepseek) != (previousCodexRoute == .deepseek)
            || claudeUsesDeepSeek != previousClaudeUsesDeepSeek
        codexRoute = route
        if codexChanged {
            providers.removeAll { $0.providerId.lowercased() == "codex" }
            codexResetCredits = nil
        }
        if deepSeekTopologyChanged {
            providers.removeAll { $0.providerId.lowercased() == "deepseek" }
            lastDeepSeekBalance = nil
        }
        errorMessageKey = nil
    }

    private func applyDeepSeekBalance(_ result: DeepSeekBalanceSnapshot?) {
        guard let result else {
            logger.info("DeepSeek balance refresh failed")
            setFailureMessageIfNeeded()
            return
        }

        lastDeepSeekBalance = result
        refreshDeepSeekProvider()
        logger.info("DeepSeek balance refresh succeeded")
    }

    /// 用最新余额 + token 历史重建 DeepSeek provider（余额金额、可用天数）。
    /// Codex 自身走 DeepSeek 时沿用 Codex 卡；否则保留官方 Codex 卡并新增独立余额卡。
    private func refreshDeepSeekProvider() {
        guard let balance = lastDeepSeekBalance else { return }
        let days = TokenCostEstimator.daysSupported(
            balance: balance.balance,
            currency: balance.currency,
            buckets: tokenBuckets
        )
        let model = dominantDeepSeekModel
        let line = UsageLine(
            type: "balance",
            label: "balance",
            used: balance.balance,
            limit: days.map(Double.init),
            resetsAt: nil,
            periodDurationMs: nil,
            value: QuotaFormatters.money(balance.balance, currency: balance.currency),
            subtitle: days.map { "\($0)" }
        )
        let provider = ProviderUsage(
            providerId: codexRoute == .deepseek ? "codex" : "deepseek",
            displayName: "DeepSeek",
            plan: nil,
            lines: [line],
            fetchedAt: balance.fetchedAt,
            balanceCurrency: balance.currency,
            model: model
        )
        var fresh = providers
        fresh.removeAll { $0.providerId.lowercased() == provider.providerId.lowercased() }
        fresh.append(provider)
        commit(fresh)
    }

    /// 仅用于余额卡的说明字段；实际费用始终按每个 bucket 自己的模型计算。
    private var dominantDeepSeekModel: String? {
        tokenBuckets
            .filter { $0.provider == .deepseek }
            .reduce(into: [String: Int]()) { totals, bucket in
                totals[TokenModelName.canonical(bucket.model), default: 0] += bucket.total
            }
            .max { lhs, rhs in lhs.value < rhs.value }?
            .key
    }

    private func refreshTokenDerivedState() {
        if (codexRoute == .deepseek || claudeUsesDeepSeek), lastDeepSeekBalance != nil {
            refreshDeepSeekProvider()
        }
    }

    private func applyDirectCodex(_ result: CodexDirectSnapshot?) {
        guard let result else {
            logger.info("Codex direct refresh failed")
            setFailureMessageIfNeeded()
            return
        }

        var fresh = providers
        replace(result.provider, in: &fresh)
        if let resetCredits = result.resetCredits { codexResetCredits = resetCredits }
        commit(fresh)
        logger.info("Codex direct refresh succeeded")
    }

    private func replace(_ provider: ProviderUsage, in providers: inout [ProviderUsage]) {
        providers.removeAll { $0.providerId.caseInsensitiveCompare(provider.providerId) == .orderedSame }
        providers.append(provider)
    }

    private func commit(_ fresh: [ProviderUsage]) {
        let sorted = fresh.sorted {
            if $0.providerId.lowercased() == "codex" { return true }
            if $1.providerId.lowercased() == "codex" { return false }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
        providers = sorted
        lastUpdated = .now
        errorMessageKey = nil
    }

    private func setFailureMessageIfNeeded() {
        guard providers.isEmpty else { return }
        errorMessageKey = "error.quotaUnavailable"
    }

    private func monitorTokenSources() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            await refreshTokenSources()
        }
    }

    /// 拉取全部本地 token 来源并落盘快照；按设计稿约定每 60 秒刷新。
    ///
    /// 数据来源分工：Codex / Claude 命令行 / WorkBuddy 直接解析本地文件，
    /// 不依赖 cc-switch；Claude 桌面版唯一来源是 cc-switch 请求日志，
    /// 它退出时该列显示「未采集」，其余工具不受影响。
    private func refreshTokenSources() async {
        guard !isRefreshingTokenSources else { return }
        isRefreshingTokenSources = true
        let totalSources = 7
        tokenProgressRevealTask?.cancel()
        tokenProgressRevealTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled, let self, self.isRefreshingTokenSources else { return }
            self.localTokenRefreshProgress = LocalTokenRefreshProgress(
                completedSources: 0,
                totalSources: totalSources
            )
        }
        defer {
            tokenProgressRevealTask?.cancel()
            tokenProgressRevealTask = nil
            localTokenRefreshProgress = nil
            isRefreshingTokenSources = false
        }

        let codexClient = codexSessionTokenClient
        let claudeClient = claudeSessionTokenClient
        let workBuddyClient = workBuddyTraceClient
        let ccSwitchClient = ccSwitchUsageClient
        let additionalClient = additionalLocalTokenClient
        let qoderClient = qoderSessionTokenClient
        var completed = 0

        await withTaskGroup(of: TokenRefreshResult.self) { group in
            group.addTask { .codex(try? await codexClient.fetchSnapshot()) }
            group.addTask { .claude(try? await claudeClient.fetchSnapshot()) }
            group.addTask { .workBuddy(try? await workBuddyClient.fetchSnapshot()) }
            group.addTask { .desktop(await ccSwitchClient.fetchSnapshot(appType: "claude-desktop")) }
            group.addTask { .claudeCrossCheck(await ccSwitchClient.fetchSnapshot(appType: "claude", client: .cli)) }
            group.addTask { .additional(try? await additionalClient.fetchSnapshots()) }
            group.addTask { .qoder(try? await qoderClient.fetchSnapshot()) }

            for await result in group {
                applyTokenRefreshResult(result)
                completed += 1
                if localTokenRefreshProgress != nil {
                    localTokenRefreshProgress = LocalTokenRefreshProgress(
                        completedSources: completed,
                        totalSources: totalSources
                    )
                }
                await Task.yield()
            }
        }

        lastTokenUpdatedAt = .now
        saveTokenSnapshotIfNeeded()
        logger.info(
            "sources codex=\(Self.todayTotal(self.tokenHistory)) claude=\(Self.todayTotal(self.claudeHistory)) desktop=\(Self.todayTotal(self.claudeDesktopHistory)) workbuddy=\(Self.todayTotal(self.workBuddyHistory)) additional=\(Self.todayTotal(self.totalTokenHistory) - Self.todayTotal(Self.combineByDay([self.tokenHistory, self.claudeHistory, self.claudeDesktopHistory, self.workBuddyHistory]))) deepseek=\(Self.todayTotal(self.deepSeekHistory)) desktopStale=\(self.claudeDesktopStale)"
        )
        refreshTokenDerivedState()
    }

    private func applyTokenRefreshResult(_ result: TokenRefreshResult) {
        var freshBuckets = tokenBuckets
        switch result {
        case let .codex(snapshot):
            if let snapshot {
                tokenHistory = snapshot.history
                codexDeepSeekHistory = snapshot.deepSeekHistory
                Self.replaceBuckets(in: &freshBuckets, matching: { $0.platform == .codex }, with: snapshot.buckets)
            } else {
                logger.warning("Codex token refresh failed; retaining last good snapshot")
            }
        case let .claude(snapshot):
            if let snapshot {
                claudeHistory = snapshot.history
                claudeDeepSeekHistory = snapshot.deepSeekHistory
                Self.replaceBuckets(
                    in: &freshBuckets,
                    matching: { $0.platform == .claude && $0.client == .cli },
                    with: snapshot.buckets
                )
            } else {
                logger.warning("Claude Code token refresh failed; retaining last good snapshot")
            }
        case let .workBuddy(snapshot):
            if let snapshot {
                workBuddyHistory = snapshot.history
                workbuddyDeepSeekHistory = snapshot.deepSeekHistory
                Self.replaceBuckets(in: &freshBuckets, matching: { $0.platform == .workbuddy }, with: snapshot.buckets)
            } else {
                logger.warning("WorkBuddy token refresh failed; retaining last good snapshot")
            }
        case let .desktop(snapshot):
            if let snapshot {
                claudeDesktopHistory = snapshot.history
                desktopDeepSeekHistory = snapshot.deepSeekHistory
                Self.replaceBuckets(
                    in: &freshBuckets,
                    matching: { $0.platform == .claude && $0.client == .desktop },
                    with: snapshot.buckets
                )
                claudeDesktopStale = !CCSwitchUsageClient.isCCSwitchRunning()
            } else {
                claudeDesktopStale = true
                logger.warning("Claude Desktop token refresh failed; retaining last good snapshot")
            }
        case let .claudeCrossCheck(snapshot):
            if let snapshot { crossCheckClaudeSource(cc: snapshot.history) }
        case let .additional(snapshots):
            guard let snapshots else {
                logger.warning("Additional local token refresh failed; retaining last good snapshot")
                break
            }
            let platforms = Set(LocalToolTokenSource.additional.map(\.platform))
            Self.replaceBuckets(in: &freshBuckets, matching: { platforms.contains($0.platform) }, with: snapshots.flatMap(\.buckets))
        case let .qoder(snapshot):
            guard let snapshot else {
                logger.warning("Qoder token refresh failed; retaining last good snapshot")
                break
            }
            Self.replaceBuckets(in: &freshBuckets, matching: { $0.platform == .qoder }, with: snapshot.buckets)
        }
        tokenBuckets = TokenUsageBucket.combining(freshBuckets)
        deepSeekHistory = TokenSourceSnapshot(buckets: tokenBuckets.filter { $0.provider == .deepseek }).history
    }

    private static func replaceBuckets(
        in buckets: inout [TokenUsageBucket],
        matching predicate: (TokenUsageBucket) -> Bool,
        with replacement: [TokenUsageBucket]
    ) {
        buckets.removeAll(where: predicate)
        buckets.append(contentsOf: replacement)
    }

    private func loadTokenSnapshot() {
        guard let tokenSnapshotURL,
              let data = try? Data(contentsOf: tokenSnapshotURL),
              let snapshot = try? JSONDecoder().decode(TokenHistorySnapshot.self, from: data),
              snapshot.version == 1 else { return }

        tokenHistory = snapshot.tokenHistory
        claudeHistory = snapshot.claudeHistory
        claudeDesktopHistory = snapshot.claudeDesktopHistory
        workBuddyHistory = snapshot.workBuddyHistory
        codexDeepSeekHistory = snapshot.codexDeepSeekHistory
        claudeDeepSeekHistory = snapshot.claudeDeepSeekHistory
        desktopDeepSeekHistory = snapshot.desktopDeepSeekHistory
        workbuddyDeepSeekHistory = snapshot.workbuddyDeepSeekHistory
        tokenBuckets = TokenUsageBucket.combining(snapshot.tokenBuckets)
        claudeDesktopStale = snapshot.claudeDesktopStale
        deepSeekHistory = TokenSourceSnapshot(buckets: tokenBuckets.filter { $0.provider == .deepseek }).history
        lastTokenUpdatedAt = snapshot.tokenUpdatedAt
            ?? (try? tokenSnapshotURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        lastSavedTokenSnapshot = snapshot
    }

    private func saveTokenSnapshotIfNeeded() {
        guard let tokenSnapshotURL else { return }
        let snapshot = TokenHistorySnapshot(
            version: 1,
            tokenHistory: tokenHistory,
            claudeHistory: claudeHistory,
            claudeDesktopHistory: claudeDesktopHistory,
            workBuddyHistory: workBuddyHistory,
            codexDeepSeekHistory: codexDeepSeekHistory,
            claudeDeepSeekHistory: claudeDeepSeekHistory,
            desktopDeepSeekHistory: desktopDeepSeekHistory,
            workbuddyDeepSeekHistory: workbuddyDeepSeekHistory,
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

    /// 用 Claude 命令行转录数字对账 cc-switch 的同源记录；差异超 5% 记日志，
    /// 展示仍以转录为准。
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

    /// 把多个稀疏的按天列表按日相加（DeepSeek 跨工具汇总用，不做补零）。
    private static func mergeSparse(_ histories: [[DailyTokenUsage]]) -> [DailyTokenUsage] {
        var byDay: [String: DailyTokenUsage] = [:]
        for history in histories {
            for usage in history {
                if let existing = byDay[usage.id] {
                    byDay[usage.id] = existing.adding(usage)
                } else {
                    byDay[usage.id] = usage
                }
            }
        }
        return byDay.values.sorted { $0.day < $1.day }
    }

    /// 把多个按天列表按日相加。历史来源现在保留完整日期范围，不能再依赖第一个数组的长度。
    private static func combineByDay(_ histories: [[DailyTokenUsage]]) -> [DailyTokenUsage] {
        var byDay: [String: (day: Date, totals: TokenTotals)] = [:]
        for history in histories {
            for usage in history {
                let current = byDay[usage.id]?.totals ?? TokenTotals()
                byDay[usage.id] = (
                    day: usage.day,
                    totals: current.adding(TokenTotals(
                        input: usage.input,
                        cachedInput: usage.cachedInput,
                        cacheWriteInput: usage.cacheWriteInput,
                        output: usage.output,
                        reasoning: usage.reasoning
                    ))
                )
            }
        }
        return byDay.values
            .map { DailyTokenUsage(day: $0.day, totals: $0.totals) }
            .sorted { $0.day < $1.day }
    }

    private static func defaultTokenSnapshotURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.cmsjcm.QuotaMonitor", isDirectory: true)
            .appendingPathComponent("token-history-snapshot-v1.json")
    }

}
