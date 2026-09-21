import Foundation

/// 首页只展示一个额度主风险；来源与窗口保留在结果里，供界面生成事实型文案。
enum OverviewRiskLevel: String, Sendable {
    case unavailable
    case critical
    case trustWarning
    case reminder
    case healthy
}

enum OverviewRiskProvider: String, Sendable {
    case codex
    case claude
    case deepSeek
}

enum OverviewRiskMetric: String, Sendable {
    case session
    case weekly
    case sharedBalance
}

struct OverviewRiskCandidate: Equatable, Sendable {
    let provider: OverviewRiskProvider
    let metric: OverviewRiskMetric
    let remainingPercent: Double?
    let resetsAt: Date?
    let balanceAmount: Double?
    let estimatedDays: Int?

    static func quota(
        provider: OverviewRiskProvider,
        metric: OverviewRiskMetric,
        line: UsageLine
    ) -> Self {
        .init(
            provider: provider,
            metric: metric,
            remainingPercent: line.remainingPercent,
            resetsAt: line.resetsAt,
            balanceAmount: nil,
            estimatedDays: nil
        )
    }

    static func quotaLines(from usage: ProviderUsage, provider: OverviewRiskProvider) -> [Self] {
        [
            usage.session.map { quota(provider: provider, metric: .session, line: $0) },
            usage.weekly.map { quota(provider: provider, metric: .weekly, line: $0) }
        ].compactMap { $0 }
    }

    static func balance(amount: Double?, estimatedDays: Int?) -> Self {
        .init(
            provider: .deepSeek,
            metric: .sharedBalance,
            remainingPercent: nil,
            resetsAt: nil,
            balanceAmount: amount,
            estimatedDays: estimatedDays
        )
    }
}

struct OverviewRiskSignal: Equatable, Sendable {
    let provider: OverviewRiskProvider
    let metric: OverviewRiskMetric
    let level: OverviewRiskLevel
    let remainingPercent: Double?
    let resetsAt: Date?
    let balanceAmount: Double?
    let estimatedDays: Int?
    let urgencyScore: Double
}

struct OverviewRiskInput: Equatable, Sendable {
    let candidates: [OverviewRiskCandidate]
    let unavailableQuotaSourceCount: Int
    let hasConnectedQuotaRoute: Bool
}

struct OverviewRiskResolution: Equatable, Sendable {
    let level: OverviewRiskLevel
    let signal: OverviewRiskSignal?
    let unavailableQuotaSourceCount: Int
    let actionPage: OverviewRiskActionPage

    enum OverviewRiskActionPage: String, Sendable {
        case overview
        case settings
    }
}

/// 额度状态的唯一判定入口。概览页、额度卡片和状态栏下拉框都使用这套规则，
/// 避免同一个百分比在不同界面显示成不同颜色。
struct QuotaRiskAssessment: Equatable, Sendable {
    let level: OverviewRiskLevel
    let urgencyScore: Double
}

enum QuotaRiskPolicy {
    static let criticalDisplayedPercent = 5
    static let reminderDisplayedPercent = 30

    static func displayedPercent(_ remainingPercent: Double) -> Int {
        Int((min(max(remainingPercent, 0), 1) * 100).rounded())
    }

    static func assess(remainingPercent: Double?) -> QuotaRiskAssessment? {
        guard let remainingPercent else { return nil }
        let percent = displayedPercent(remainingPercent)
        let level: OverviewRiskLevel
        if percent <= criticalDisplayedPercent {
            level = .critical
        } else if percent <= reminderDisplayedPercent {
            level = .reminder
        } else {
            level = .healthy
        }
        return .init(
            level: level,
            urgencyScore: Double(percent) / 100
        )
    }
}

enum OverviewRiskResolver {
    private static let quotaRecoveryStates: Set<DataSourceHealthState> = [
        .failed, .needsPermission, .unsupportedFormat, .stale
    ]

    @MainActor
    static func resolve(store: QuotaStore) -> OverviewRiskResolution {
        let sourceHealth = Dictionary(
            uniqueKeysWithValues: store.dataSourceHealth.map { ($0.id, $0) }
        )
        let usesSharedBalance = store.codexRoute == .deepseek || store.claudeUsesDeepSeek
        var relevantQuotaSources: Set<DataSourceID> = []
        if store.codexRoute != .deepseek {
            relevantQuotaSources.insert(DataSourceCatalog.codexQuota)
        }
        if usesSharedBalance {
            relevantQuotaSources.insert(DataSourceCatalog.deepSeekBalance)
        }
        let unavailableSourceCount = sourceHealth.values.filter {
            $0.isInstalled
                && relevantQuotaSources.contains($0.id)
                && quotaRecoveryStates.contains($0.state)
        }.count

        var candidates: [OverviewRiskCandidate] = []
        let codexQuotaIsReliable = sourceHealth[DataSourceCatalog.codexQuota].map {
            !quotaRecoveryStates.contains($0.state)
        } ?? true
        if store.codexRoute == .official, codexQuotaIsReliable,
           let provider = store.providers.first(where: { $0.providerId.lowercased() == "codex" }) {
            candidates.append(contentsOf: OverviewRiskCandidate.quotaLines(from: provider, provider: .codex))
        }

        // 当前 Claude 官方额度没有独立来源；若未来 provider 开始返回真实额度，
        // 这里会自动纳入，而不会从 Token 日志反推或伪造额度。
        if [.official, .mixed].contains(store.claudeRouteSummary),
           let provider = store.providers.first(where: { $0.providerId.lowercased() == "claude" }) {
            candidates.append(contentsOf: OverviewRiskCandidate.quotaLines(from: provider, provider: .claude))
        }

        let deepSeekBalanceIsReliable = sourceHealth[DataSourceCatalog.deepSeekBalance].map {
            !quotaRecoveryStates.contains($0.state)
        } ?? true
        if usesSharedBalance, deepSeekBalanceIsReliable,
           store.deepSeekBalance != nil || store.deepSeekDays != nil {
            candidates.append(.balance(amount: store.deepSeekBalance, estimatedDays: store.deepSeekDays))
        }

        return resolve(
            input: OverviewRiskInput(
                candidates: candidates,
                unavailableQuotaSourceCount: unavailableSourceCount,
                hasConnectedQuotaRoute: store.codexRoute != .unknown || store.claudeRouteSummary != .unknown
            )
        )
    }

    /// 纯计算入口：额度事实先于辅助 Token 来源状态，便于覆盖所有边界场景。
    static func resolve(input: OverviewRiskInput) -> OverviewRiskResolution {
        let signals = input.candidates.compactMap(signal)
        if let primary = signals.min(by: isMoreUrgent) {
            return .init(
                level: primary.level,
                signal: primary,
                unavailableQuotaSourceCount: input.unavailableQuotaSourceCount,
                actionPage: .overview
            )
        }

        if input.unavailableQuotaSourceCount > 0 {
            return .init(
                level: .trustWarning,
                signal: nil,
                unavailableQuotaSourceCount: input.unavailableQuotaSourceCount,
                actionPage: .settings
            )
        }

        return .init(
            level: .unavailable,
            signal: nil,
            unavailableQuotaSourceCount: 0,
            actionPage: input.hasConnectedQuotaRoute ? .overview : .settings
        )
    }

    private static func signal(for candidate: OverviewRiskCandidate) -> OverviewRiskSignal? {
        if candidate.metric == .sharedBalance {
            if let amount = candidate.balanceAmount, amount <= 0 {
                return balanceSignal(candidate, level: .critical, urgency: 0)
            }
            guard let days = candidate.estimatedDays else { return nil }
            let level: OverviewRiskLevel = if days <= 2 {
                .critical
            } else if days <= 7 {
                .reminder
            } else {
                .healthy
            }
            return balanceSignal(candidate, level: level, urgency: Double(days) / 7)
        }

        guard let assessment = QuotaRiskPolicy.assess(remainingPercent: candidate.remainingPercent) else { return nil }
        let clampedRemaining = min(max(candidate.remainingPercent ?? 0, 0), 1)
        return .init(
            provider: candidate.provider,
            metric: candidate.metric,
            level: assessment.level,
            remainingPercent: clampedRemaining,
            resetsAt: candidate.resetsAt,
            balanceAmount: nil,
            estimatedDays: nil,
            urgencyScore: assessment.urgencyScore
        )
    }

    private static func balanceSignal(
        _ candidate: OverviewRiskCandidate,
        level: OverviewRiskLevel,
        urgency: Double
    ) -> OverviewRiskSignal {
        .init(
            provider: candidate.provider,
            metric: candidate.metric,
            level: level,
            remainingPercent: nil,
            resetsAt: nil,
            balanceAmount: candidate.balanceAmount,
            estimatedDays: candidate.estimatedDays,
            urgencyScore: urgency
        )
    }

    private static func isMoreUrgent(_ lhs: OverviewRiskSignal, _ rhs: OverviewRiskSignal) -> Bool {
        let leftRank = severityRank(lhs.level)
        let rightRank = severityRank(rhs.level)
        if leftRank != rightRank { return leftRank < rightRank }
        if lhs.urgencyScore != rhs.urgencyScore { return lhs.urgencyScore < rhs.urgencyScore }
        if lhs.provider.rawValue != rhs.provider.rawValue {
            return lhs.provider.rawValue < rhs.provider.rawValue
        }
        return lhs.metric.rawValue < rhs.metric.rawValue
    }

    private static func severityRank(_ level: OverviewRiskLevel) -> Int {
        switch level {
        case .critical: 0
        case .reminder: 1
        case .healthy: 2
        case .trustWarning: 3
        case .unavailable: 4
        }
    }
}
