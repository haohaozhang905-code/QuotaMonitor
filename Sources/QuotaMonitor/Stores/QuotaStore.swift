import Foundation
import Observation
import OSLog

@MainActor @Observable
final class QuotaStore {
    private(set) var providers: [ProviderUsage] = []
    private(set) var lastUpdated: Date?
    private(set) var errorMessageKey: String?
    private(set) var isRefreshing = false
    var isRefreshingTokenSources = false
    var localTokenRefreshProgress: LocalTokenRefreshProgress?
    var lastTokenUpdatedAt: Date?
    private(set) var hasCompletedInitialRefresh = false
    /// 额度或 Token 完成一轮刷新后递增，提醒协调器只在完整快照上判断规则。
    var reminderRevision = 0
    private(set) var codexResetCredits: CodexResetCredits?
    /// 按日期、平台、客户端和模型拆分的原始聚合桶，供 Token 看板的模型维度查询。
    var tokenBuckets: [TokenUsageBucket] = []
    private(set) var codexRoute: CodexRoute = .unknown
    /// Claude 走官方还是 DeepSeek 路由（由本地 settings 推断）。
    private(set) var claudeRoute: ClaudeRoute = .unknown
    /// Claude Desktop 独立路由；不能与 Claude Code 的 provider 合并判断。
    private(set) var claudeDesktopRoute: ClaudeRoute = .unknown
    private var lastDeepSeekBalance: DeepSeekBalanceSnapshot?
    /// Claude 桌面版依赖 cc-switch 本地代理；cc-switch 未运行时数据可能缺失。
    var claudeDesktopStale = false
    /// 兼容现有调用方的历史视图，统一从唯一来源 tokenBuckets 派生。
    var tokenHistory: [DailyTokenUsage] { dailyHistory(platform: .codex, client: .cli) }
    var claudeHistory: [DailyTokenUsage] { dailyHistory(platform: .claude, client: .cli) }
    var claudeDesktopHistory: [DailyTokenUsage] { dailyHistory(platform: .claude, client: .desktop) }
    var workBuddyHistory: [DailyTokenUsage] { dailyHistory(platform: .workbuddy, client: .desktop) }
    var deepSeekHistory: [DailyTokenUsage] {
        TokenSourceSnapshot(buckets: tokenBuckets.filter { $0.provider == .deepseek }).history
    }
    /// 逐来源诊断状态。失败时保留 last-good 数据，并在展示快照中标记 stale。
    var sourceStates: [DataSourceID: TokenSourceRuntimeState] = [:]

    private let codexDirectClient = CodexDirectClient()
    private let deepSeekBalanceClient = DeepSeekBalanceClient()
    let codexSessionTokenClient = CodexSessionTokenClient()
    let claudeSessionTokenClient = ClaudeSessionTokenClient()
    let workBuddyTraceClient = WorkBuddyTraceClient()
    let ccSwitchUsageClient = CCSwitchUsageClient()
    let additionalLocalTokenClient = AdditionalLocalTokenClient()
    let qoderSessionTokenClient = QoderSessionTokenClient()
    let logger = Logger(subsystem: "com.cmsjcm.QuotaMonitor", category: "quota")
    let tokenSnapshotURL: URL?
    var lastSavedTokenSnapshot: TokenHistorySnapshot?
    var tokenTask: Task<Void, Never>?
    var tokenProgressRevealTask: Task<Void, Never>?
    var tokenChangeMonitor: LocalTokenChangeMonitor?
    var tokenChangeDebounceTask: Task<Void, Never>?
    var tokenRefreshWakeupState = TokenRefreshWakeupState()

    private static let quotaRefreshInterval: Duration = .seconds(60)
    static let tokenRefreshInterval: Duration = .seconds(5 * 60)
    static let tokenSourceTimeout: Duration = .seconds(15)

    convenience init() {
        self.init(tokenSnapshotURL: Self.defaultTokenSnapshotURL())
    }

    init(tokenSnapshotURL: URL?) {
        self.tokenSnapshotURL = tokenSnapshotURL
        let detectedClaudeRoutes = ClaudeRouteDetector.detectRoutes()
        codexRoute = CodexRouteDetector.detect()
        claudeRoute = detectedClaudeRoutes.code
        claudeDesktopRoute = detectedClaudeRoutes.desktop
        loadTokenSnapshot()
    }

    var lowestRemaining: Double? {
        providers.flatMap { [$0.session?.remainingPercent, $0.weekly?.remainingPercent] }.compactMap { $0 }.min()
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

    private func dailyHistory(
        platform: TokenPlatform,
        client: TokenClient,
        provider: TokenProvider? = nil
    ) -> [DailyTokenUsage] {
        TokenSourceSnapshot(buckets: tokenBuckets.filter { bucket in
            bucket.platform == platform
                && bucket.client == client
                && (provider == nil || bucket.provider == provider)
        }).history
    }

    private func tokenUsage(for day: Date) -> DailyTokenUsage? {
        totalTokenHistory.first { $0.id == DailyTokenUsage.dayKey(for: day) }
    }

    var todayTokenUsage: DailyTokenUsage? { tokenUsage(for: .now) }

    var latestUpdatedAt: Date? {
        [lastUpdated, lastTokenUpdatedAt].compactMap { $0 }.max()
    }

    /// 统一的逐来源健康快照，供来源中心和风险首页共同使用。
    var dataSourceHealth: [DataSourceHealthSnapshot] {
        dataSourceHealth(at: .now)
    }

    func dataSourceHealth(at now: Date) -> [DataSourceHealthSnapshot] {
        DataSourceCatalog.all.map { descriptor in
            (sourceStates[descriptor.id] ?? TokenSourceRuntimeState()).snapshot(
                for: descriptor,
                at: now,
                isInstalled: isSourceInstalled(descriptor)
            )
        }
    }

    private func isSourceInstalled(_ descriptor: DataSourceDescriptor) -> Bool {
        let source = sourceStates[descriptor.id] ?? TokenSourceRuntimeState()
        if descriptor.usesObservedDataAsInstallationEvidence,
           source.lastSuccessAt != nil || source.validRecordCount > 0 {
            return true
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        switch descriptor.installationProbe {
        case .codexRoute:
            return codexRoute != .unknown
        case .deepSeekRoute:
            return codexRoute == .deepseek || claudeUsesDeepSeek || lastDeepSeekBalance != nil
        case .paths, .localTool:
            return descriptor.installationProbe.existingPaths(home: home, environment: environment).contains {
                FileManager.default.fileExists(atPath: $0.path)
            }
        }
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
        defer {
            tokenTask?.cancel()
            tokenChangeDebounceTask?.cancel()
            tokenChangeMonitor?.stop()
            tokenChangeMonitor = nil
        }
        await refreshAll()
        hasCompletedInitialRefresh = true
        startTokenChangeMonitor()
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.quotaRefreshInterval)
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
        defer {
            isRefreshing = false
            reminderRevision &+= 1
        }

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
        let shouldFetchCodexQuota = codexRoute == .official
        let shouldFetchDeepSeekBalance = codexRoute == .deepseek || claudeUsesDeepSeek
        if shouldFetchCodexQuota {
            beginSourceAttempt(DataSourceCatalog.codexQuota)
        }
        if shouldFetchDeepSeekBalance {
            beginSourceAttempt(DataSourceCatalog.deepSeekBalance)
        }

        let codexClient = codexDirectClient
        let balanceClient = deepSeekBalanceClient
        async let codexResult = Self.fetchCodexQuota(if: shouldFetchCodexQuota, using: codexClient)
        async let balanceResult = Self.fetchDeepSeekBalance(if: shouldFetchDeepSeekBalance, using: balanceClient)
        let (codexSnapshot, balanceSnapshot) = await (codexResult, balanceResult)

        if shouldFetchCodexQuota { applyDirectCodex(codexSnapshot) }
        if shouldFetchDeepSeekBalance { applyDeepSeekBalance(balanceSnapshot) }
        if !shouldFetchCodexQuota && !shouldFetchDeepSeekBalance {
            errorMessageKey = "error.quotaUnavailable"
        }
    }

    nonisolated private static func fetchCodexQuota(
        if enabled: Bool,
        using client: CodexDirectClient
    ) async -> CodexDirectSnapshot? {
        guard enabled else { return nil }
        return try? await client.fetch()
    }

    nonisolated private static func fetchDeepSeekBalance(
        if enabled: Bool,
        using client: DeepSeekBalanceClient
    ) async -> DeepSeekBalanceSnapshot? {
        guard enabled else { return nil }
        return try? await client.fetch()
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
            finishSource(DataSourceCatalog.deepSeekBalance, state: .failed)
            logger.info("DeepSeek balance refresh failed")
            setFailureMessageIfNeeded()
            return
        }

        lastDeepSeekBalance = result
        finishSource(DataSourceCatalog.deepSeekBalance, state: .ready)
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

    func refreshTokenDerivedState() {
        if (codexRoute == .deepseek || claudeUsesDeepSeek), lastDeepSeekBalance != nil {
            refreshDeepSeekProvider()
        }
    }

    func applyDirectCodex(_ result: CodexDirectSnapshot?) {
        guard let result else {
            finishSource(DataSourceCatalog.codexQuota, state: .failed)
            logger.info("Codex direct refresh failed")
            setFailureMessageIfNeeded()
            return
        }

        var fresh = providers
        replace(result.provider, in: &fresh)
        // A successful quota refresh owns the complete Codex snapshot. If this
        // batch has no reset-credit data, do not carry a previous batch forward.
        codexResetCredits = result.resetCredits
        commit(fresh)
        finishSource(DataSourceCatalog.codexQuota, state: .ready)
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

    func beginSourceAttempt(_ id: DataSourceID) {
        var source = sourceStates[id] ?? TokenSourceRuntimeState()
        source.begin(at: .now)
        sourceStates[id] = source
    }

    func finishSource(
        _ id: DataSourceID,
        state: DataSourceHealthState,
        candidateFileCount: Int? = nil,
        validRecordCount: Int = 0,
        usesLastGoodData: Bool = false
    ) {
        var source = sourceStates[id] ?? TokenSourceRuntimeState()
        source.finish(
            with: state,
            at: .now,
            candidateFileCount: candidateFileCount,
            validRecordCount: validRecordCount,
            usesLastGoodData: usesLastGoodData
        )
        sourceStates[id] = source
    }

    private static func defaultTokenSnapshotURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.cmsjcm.QuotaMonitor", isDirectory: true)
            .appendingPathComponent("token-history-snapshot-v2.json")
    }

}
