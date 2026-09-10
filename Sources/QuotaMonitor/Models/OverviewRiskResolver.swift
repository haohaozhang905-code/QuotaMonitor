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
    let periodDuration: TimeInterval?
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
            periodDuration: line.periodDurationMs.map { $0 / 1_000 },
            balanceAmount: nil,
            estimatedDays: nil
        )
    }

    static func balance(amount: Double?, estimatedDays: Int?) -> Self {
        .init(
            provider: .deepSeek,
            metric: .sharedBalance,
            remainingPercent: nil,
            resetsAt: nil,
            periodDuration: nil,
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
    let coverageRatio: Double?
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

enum OverviewRiskResolver {
    private static let quotaRecoveryStates: Set<DataSourceHealthState> = [
        .failed, .needsPermission, .unsupportedFormat, .stale
    ]

    @MainActor
    static func resolve(store: QuotaStore, now: Date = .now) -> OverviewRiskResolution {
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
            if let session = provider.session {
                candidates.append(.quota(provider: .codex, metric: .session, line: session))
            }
            if let weekly = provider.weekly {
                candidates.append(.quota(provider: .codex, metric: .weekly, line: weekly))
            }
        }

        // 当前 Claude 官方额度没有独立来源；若未来 provider 开始返回真实额度，
        // 这里会自动纳入，而不会从 Token 日志反推或伪造额度。
        if [.official, .mixed].contains(store.claudeRouteSummary),
           let provider = store.providers.first(where: { $0.providerId.lowercased() == "claude" }) {
            if let session = provider.session {
                candidates.append(.quota(provider: .claude, metric: .session, line: session))
            }
            if let weekly = provider.weekly {
                candidates.append(.quota(provider: .claude, metric: .weekly, line: weekly))
            }
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
            ),
            now: now
        )
    }

    /// 纯计算入口：额度事实先于辅助 Token 来源状态，便于覆盖所有边界场景。
    static func resolve(input: OverviewRiskInput, now: Date) -> OverviewRiskResolution {
        let signals = input.candidates.compactMap { signal(for: $0, now: now) }
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

    private static func signal(for candidate: OverviewRiskCandidate, now: Date) -> OverviewRiskSignal? {
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

        guard let remaining = candidate.remainingPercent else { return nil }
        let clampedRemaining = min(max(remaining, 0), 1)
        let coverage = coverageRatio(
            remainingPercent: clampedRemaining,
            resetsAt: candidate.resetsAt,
            periodDuration: candidate.periodDuration,
            now: now
        )
        let level: OverviewRiskLevel
        if clampedRemaining == 0 || coverage.map({ $0 < 0.5 }) == true {
            level = .critical
        } else if coverage.map({ $0 < 1 }) == true {
            level = .reminder
        } else if coverage == nil, clampedRemaining <= 0.30 {
            level = .critical
        } else if coverage == nil, clampedRemaining <= 0.50 {
            level = .reminder
        } else {
            level = .healthy
        }
        return .init(
            provider: candidate.provider,
            metric: candidate.metric,
            level: level,
            remainingPercent: clampedRemaining,
            resetsAt: candidate.resetsAt,
            balanceAmount: nil,
            estimatedDays: nil,
            coverageRatio: coverage,
            urgencyScore: coverage ?? clampedRemaining
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
            coverageRatio: nil,
            urgencyScore: urgency
        )
    }

    private static func coverageRatio(
        remainingPercent: Double,
        resetsAt: Date?,
        periodDuration: TimeInterval?,
        now: Date
    ) -> Double? {
        guard let resetsAt, let periodDuration, periodDuration > 0 else { return nil }
        let remainingTime = resetsAt.timeIntervalSince(now)
        guard remainingTime > 0, remainingTime <= periodDuration * 1.05 else { return nil }
        let remainingWindowFraction = min(max(remainingTime / periodDuration, 0.01), 1)
        return remainingPercent / remainingWindowFraction
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
