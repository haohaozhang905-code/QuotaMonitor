import SwiftUI

extension MainPanelView {
    var overviewPage: some View {
        VStack(alignment: .leading, spacing: 14) {
            overviewHeading
            overviewRiskCard
            overviewHeroCard
            overviewQuotaGrid
            overviewBottomGrid
        }
    }

    /// 首页新增的唯一主状态，保留原有额度、Token 与排行模块顺序不变。
    private var overviewRiskCard: some View {
        let risk = OverviewRiskResolver.resolve(store: store)
        let isActionable = risk.actionPage != .overview
        let title = overviewRiskTitle(risk)
        let detail = overviewRiskDetail(risk)
        let color: Color = switch risk.level {
        case .healthy: PanelTheme.ok
        case .reminder: PanelTheme.warn
        case .critical: PanelTheme.danger
        case .trustWarning: PanelTheme.warn
        case .unavailable: PanelTheme.text2
        }
        let background: Color = switch risk.level {
        case .healthy: PanelTheme.okSoft
        case .reminder, .trustWarning: PanelTheme.warnSoft
        case .critical: PanelTheme.dangerSoft
        case .unavailable: PanelTheme.surface2
        }
        return Button {
            guard isActionable else { return }
            selectPage(.settings)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: risk.level == .healthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    overviewRiskHeadline(risk, color: color)
                    overviewRiskDetailView(risk, color: color)
                }
                Spacer(minLength: 8)
                if isActionable {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PanelTheme.text2)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue("\(detail). \(language.text("overview.risk.sourceSummary", readySourceCount, overviewFreshnessText))")
        .accessibilityHint(isActionable ? language.text("overview.risk.actionHint") : "")
    }

    @ViewBuilder
    private func overviewRiskHeadline(_ risk: OverviewRiskResolution, color: Color) -> some View {
        if let signal = risk.signal,
           signal.metric != .sharedBalance,
           let remaining = signal.remainingPercent,
           remaining > 0 {
            Text(language.text(
                "overview.risk.quota.remaining.prefix",
                overviewRiskProviderName(signal.provider),
                overviewRiskMetricName(signal.metric)
            ))
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(PanelTheme.text)
            + Text(QuotaFormatters.percent(remaining))
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        } else {
            Text(overviewRiskTitle(risk))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(PanelTheme.text)
        }
    }

    @ViewBuilder
    private func overviewRiskDetailView(_ risk: OverviewRiskResolution, color: Color) -> some View {
        if let reset = risk.signal?.resetsAt {
            Text(language.text(
                "overview.risk.resetDetail",
                QuotaFormatters.reset(reset, language: language.language),
                overviewRiskResetCountdown(reset)
            ))
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(color)
            .lineLimit(1)
        } else {
            Text(overviewRiskDetail(risk))
                .font(.system(size: 11))
                .foregroundStyle(PanelTheme.text2)
                .lineLimit(2)
        }
    }

    private func overviewRiskResetCountdown(_ reset: Date) -> String {
        let countdown = QuotaFormatters.relativeReset(from: reset, language: language)
        guard language.language == .simplifiedChinese else { return countdown }
        return countdown.replacingOccurrences(of: " ", with: "")
    }

    private func overviewRiskTitle(_ risk: OverviewRiskResolution) -> String {
        guard let signal = risk.signal else {
            return language.text(risk.level == .trustWarning
                ? "overview.risk.trust.title"
                : "overview.risk.unavailable.title")
        }
        if signal.metric == .sharedBalance {
            if signal.balanceAmount.map({ $0 <= 0 }) == true {
                return language.text("overview.risk.balance.depleted", overviewRiskProviderName(signal.provider))
            }
            guard let days = signal.estimatedDays else {
                return language.text("overview.risk.unavailable.title")
            }
            return language.text("overview.risk.balance.days", overviewRiskProviderName(signal.provider), days)
        }
        let provider = overviewRiskProviderName(signal.provider)
        let metric = overviewRiskMetricName(signal.metric)
        if signal.remainingPercent == 0 {
            return language.text("overview.risk.quota.exhausted", provider, metric)
        }
        return language.text(
            "overview.risk.quota.remaining",
            provider,
            metric,
            QuotaFormatters.percent(signal.remainingPercent)
        )
    }

    private func overviewRiskDetail(_ risk: OverviewRiskResolution) -> String {
        var parts: [String] = []
        if let signal = risk.signal {
            if let reset = signal.resetsAt {
                parts.append(language.text(
                    "overview.risk.resetDetail",
                    QuotaFormatters.reset(reset, language: language.language),
                    overviewRiskResetCountdown(reset)
                ))
            } else if signal.metric == .sharedBalance {
                parts.append(language.text("overview.risk.balance.detail"))
            } else if risk.level == .reminder {
                parts.append(language.text("overview.risk.reminder.detail"))
            } else if risk.level == .critical {
                parts.append(language.text("overview.risk.critical.detail"))
            }
        } else {
            parts.append(language.text(risk.level == .trustWarning
                ? "overview.risk.trust.detail"
                : "overview.risk.unavailable.detail"))
        }
        if risk.unavailableQuotaSourceCount > 0, risk.signal != nil {
            parts.append(language.text("overview.risk.partialSources", risk.unavailableQuotaSourceCount))
        }
        return parts.joined(separator: " ")
    }

    private func overviewRiskProviderName(_ provider: OverviewRiskProvider) -> String {
        switch provider {
        case .codex: "Codex"
        case .claude: "Claude"
        case .deepSeek: "DeepSeek"
        }
    }

    private func overviewRiskMetricName(_ metric: OverviewRiskMetric) -> String {
        switch metric {
        case .session: language.text("panel.sessionLeft")
        case .weekly: language.text("overview.weekQuota")
        case .sharedBalance: language.text("overview.sharedBalance")
        }
    }

    private var readySourceCount: Int {
        store.dataSourceHealth.filter { $0.isInstalled && $0.state == .ready }.count
    }

    private var overviewFreshnessText: String {
        guard let date = store.latestUpdatedAt else { return "--" }
        return QuotaFormatters.clock(language: language.language).string(from: date)
    }

    private var overviewHeading: some View {
        Text(language.text("overview.pageTitle"))
            .font(.system(size: 22, weight: .bold, design: .monospaced))
            .kerning(-0.4)
            .foregroundStyle(PanelTheme.text)
    }

    /// 首页首卡只回答三个问题：今天用了多少、和昨天比如何、近7天的量级。
    private var overviewHeroCard: some View {
        let presentation = store.presentationSnapshot
        return panelCard(elevated: false) {
            VStack(alignment: .leading, spacing: 5) {
                Text(language.text("menu.todayTokensLabel"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(PanelTheme.text3)
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(QuotaFormatters.localizedTokens(presentation.today.total, language: language.language))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .fontDesign(.monospaced)
                        .foregroundStyle(PanelTheme.text)
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(heroYesterdayText)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(PanelTheme.text2)
                        if let delta = relativeDeltaText {
                            Text(delta)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .fontDesign(.monospaced)
                                .foregroundStyle(relativeDeltaColor)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(relativeDeltaColor.opacity(0.14), in: Capsule())
                                .fixedSize()
                        }
                    }
                }
            }
            HStack(spacing: 0) {
                overviewHeroMetric(language.text("overview.last7Total"), QuotaFormatters.localizedTokens(presentation.lastSevenDays.total, language: language.language))
                overviewHeroMetric(language.text("overview.todayPeakShare"), todayPeakShare)
                overviewHeroMetric(
                    language.text("overview.leadingModel"),
                    presentation.modelToday.first?.key.displayName() ?? "--"
                )
            }
            .padding(.top, 7)
        }
    }

    private var heroYesterdayText: String {
        let yesterday = store.yesterdayTokenUsage.map { QuotaFormatters.localizedTokens($0.total, language: language.language) } ?? "--"
        return language.text("overview.yesterdayComparison", yesterday)
    }

    private var todayPeakShare: String {
        let total = max(store.presentationSnapshot.lastSevenDays.total, 1)
        return String(format: "%.1f%%", Double(store.presentationSnapshot.today.total) / Double(total) * 100)
    }

    private func overviewHeroMetric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.text3)
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .monospaced))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var relativeDeltaText: String? {
        guard let today = store.todayTokenUsage?.total,
              let yesterday = store.yesterdayTokenUsage?.total,
              let percent = DailyTokenUsage.trendPercent(today: today, yesterday: yesterday) else { return nil }
        return String(format: "%@ %.1f%%", percent >= 0 ? "↑" : "↓", abs(percent))
    }

    private var relativeDeltaColor: Color {
        guard let today = store.todayTokenUsage?.total,
              let yesterday = store.yesterdayTokenUsage?.total else { return PanelTheme.text2 }
        return today >= yesterday ? PanelTheme.claude : PanelTheme.ok
    }

    private var overviewQuotaGrid: some View {
        Group {
            if overviewQuotaItems.isEmpty {
                panelCard(height: 76) {
                    Text(language.text("overview.noQuotaSources"))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(PanelTheme.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(overviewQuotaItems) { item in
                        overviewQuotaCard(
                            icon: item.platform.brandIconKind,
                            name: item.name,
                            route: item.route,
                            facts: item.facts,
                            state: item.state
                        )
                    }
                }
            }
        }
    }

    private var overviewQuotaItems: [OverviewQuotaItem] {
        var items: [OverviewQuotaItem] = []
        if store.codexRoute != .unknown {
            items.append(.init(
                platform: .codex,
                name: TokenPlatform.codex.displayName,
                route: codexOverviewRoute,
                facts: codexOverviewFacts,
                state: codexOverviewState
            ))
        }
        if store.claudeDisplayRoute != .unknown {
            items.append(.init(
                platform: .claude,
                name: TokenPlatform.claude.displayName,
                route: claudeOverviewRoute,
                facts: claudeOverviewFacts,
                state: claudeOverviewState
            ))
        }
        return items
    }

    private struct OverviewQuotaItem: Identifiable {
        let platform: TokenPlatform
        let name: String
        let route: String
        let facts: [OverviewQuotaFact]
        let state: BalanceState?

        var id: String { platform.rawValue }
    }

    private struct OverviewQuotaFact {
        let label: String
        let value: String
        let detail: String
        let health: QuotaHealth
    }

    private var codexOverviewRoute: String {
        switch store.codexRoute {
        case .deepseek: language.text("panel.deepSeekRouteTag")
        case .official: codexProvider?.plan ?? language.text("panel.official")
        case .unknown: language.text("settings.notConnected")
        }
    }

    private var claudeOverviewRoute: String {
        switch store.claudeDisplayRoute {
        case .deepseek: language.text("panel.deepSeekRouteTag")
        case .official: "Pro"
        case .other: language.text("panel.routeOther")
        case .mixed: language.text("panel.routeMixed")
        case .unknown: language.text("settings.notConnected")
        }
    }

    private var codexOverviewFacts: [OverviewQuotaFact] {
        if QuotaPresentationPolicy.mode(for: store.codexRoute) == .sharedBalance { return sharedOverviewFacts }
        return [
            quotaFact(label: language.text("panel.sessionLeft"), line: codexProvider?.session),
            quotaFact(label: language.text("overview.weekQuota"), line: codexProvider?.weekly)
        ]
    }

    private var claudeOverviewFacts: [OverviewQuotaFact] {
        if store.claudeUsesDeepSeek { return sharedOverviewFacts }
        let detail = store.claudeRouteSummary == .unknown
            ? language.text("settings.notConnected")
            : language.text("overview.quotaUnavailable")
        return [
            .init(label: language.text("overview.sessionQuota"), value: "--", detail: detail, health: .unknown),
            .init(label: language.text("overview.weekQuota"), value: "--", detail: detail, health: .unknown)
        ]
    }

    private var sharedOverviewFacts: [OverviewQuotaFact] {
        let health = QuotaHealth(balanceAmount: store.deepSeekBalance, estimatedDays: store.deepSeekDays)
        return [
            .init(label: language.text("overview.sharedBalance"), value: sharedBalanceText, detail: balanceStatusDetail(health), health: health),
            .init(label: language.text("overview.estimatedDays"), value: store.deepSeekDays.map { language.text("panel.daysShortLabel", "\($0)") } ?? "--", detail: language.text("overview.estimateNote"), health: health)
        ]
    }

    private func quotaFact(label: String, line: UsageLine?) -> OverviewQuotaFact {
        let health = QuotaHealth(quotaLine: line)
        return .init(
            label: label,
            value: line?.remainingPercent.map(QuotaFormatters.percent) ?? "--",
            detail: codexResetText(line),
            health: health
        )
    }

    private var codexOverviewState: BalanceState? {
        switch store.codexRoute {
        case .deepseek: BalanceState(balanceAmount: store.deepSeekBalance, days: store.deepSeekDays)
        case .official:
            codexOfficialRiskResolution.map { balanceState(for: $0.level) } ?? .unknown
        case .unknown: nil
        }
    }

    private var codexOfficialRiskResolution: OverviewRiskResolution? {
        guard let provider = codexProvider else { return nil }
        let candidates = OverviewRiskCandidate.quotaLines(from: provider, provider: .codex)
        guard !candidates.isEmpty else { return nil }
        return OverviewRiskResolver.resolve(
            input: .init(
                candidates: candidates,
                unavailableQuotaSourceCount: 0,
                hasConnectedQuotaRoute: true
            )
        )
    }

    private func balanceState(for level: OverviewRiskLevel) -> BalanceState {
        switch level {
        case .healthy: .normal
        case .reminder: .low
        case .critical: .critical
        case .trustWarning, .unavailable: .unknown
        }
    }

    private var claudeOverviewState: BalanceState? {
        if store.claudeUsesDeepSeek { return BalanceState(balanceAmount: store.deepSeekBalance, days: store.deepSeekDays) }
        return switch store.claudeRouteSummary {
        case .official, .other, .mixed: BalanceState.unknown
        case .deepseek: BalanceState(balanceAmount: store.deepSeekBalance, days: store.deepSeekDays)
        case .unknown: nil
        }
    }

    private func codexResetText(_ line: UsageLine?) -> String {
        guard let line else { return language.text("overview.noResetData") }
        guard let reset = line.resetsAt else { return language.text("overview.noResetData") }
        return language.text("overview.resetAfter", QuotaFormatters.reset(reset, language: language.language))
    }

    private func balanceStatusDetail(_ health: QuotaHealth) -> String {
        let status = switch health {
        case .healthy: language.text("quota.status.healthy")
        case .warning: language.text("quota.status.warning")
        case .critical: language.text("quota.status.critical")
        case .unknown: language.text("quota.status.pendingEstimate")
        }
        return "\(status) · \(language.text("overview.balanceNoReset"))"
    }

    private func overviewQuotaCard(
        icon: BrandIconKind,
        name: String,
        route: String,
        facts: [OverviewQuotaFact],
        state: BalanceState?
    ) -> some View {
        let status = overviewStatus(for: state)
        return panelCard {
            HStack(spacing: 8) {
                BrandIconView(kind: icon, size: icon == .codex ? 22 : 18)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PanelTheme.text)
                    HStack(spacing: 5) {
                        Text(route)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(PanelTheme.text3)
                        if icon == .codex,
                           let resetCredits = store.codexResetCredits,
                           resetCredits.availableCount > 0 {
                            codexResetCreditsInline(resetCredits)
                        }
                    }
                }
                Spacer(minLength: 8)
                Text(status.label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(status.background, in: Capsule())
            }
            HStack(spacing: 0) {
                ForEach(Array(facts.enumerated()), id: \.offset) { index, fact in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(fact.label)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(PanelTheme.text3)
                        Text(fact.value)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.quotaValueColor(fact.health))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(fact.detail)
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text2)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 10)
                    if index == 0 {
                        Rectangle()
                            .fill(PanelTheme.separator)
                            .frame(width: 1, height: 57)
                            .padding(.horizontal, 13)
                    }
                }
            }
            .overlay(alignment: .top) {
                Rectangle().fill(PanelTheme.separator).frame(height: 0.5).padding(.top, 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func codexResetCreditsInline(_ resetCredits: CodexResetCredits) -> some View {
        let label = language.text("overview.resetCredits.inline", resetCredits.availableCount)
        let help = codexResetCreditsHelp(resetCredits)
        return HStack(spacing: 3) {
            (
                Text(language.text("overview.resetCredits.inline.prefix"))
                    .foregroundStyle(PanelTheme.text2)
                + Text(language.text("overview.resetCredits.inline.value", resetCredits.availableCount))
                    .foregroundStyle(PanelTheme.chartAccent)
                + Text(language.text("overview.resetCredits.inline.suffix"))
                    .foregroundStyle(PanelTheme.text2)
            )
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1)
            Button {
                showCodexResetCreditsPopover.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(PanelTheme.text3)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showCodexResetCreditsPopover, arrowEdge: .bottom) {
                codexResetCreditsPopover(resetCredits)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(help)
            .accessibilityHint(language.text("overview.resetCredits.clickHint"))
        }
        .accessibilityElement(children: .contain)
    }

    private func codexResetCreditsPopover(_ resetCredits: CodexResetCredits) -> some View {
        let missingCount = max(resetCredits.availableCount - resetCredits.expirations.count, 0)
        return VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 0) {
                Text(language.text("overview.resetCredits.title.prefix"))
                    .foregroundStyle(PanelTheme.text)
                Text(language.text("overview.resetCredits.title.value", resetCredits.availableCount))
                    .foregroundStyle(PanelTheme.chartAccent)
                Text(language.text("overview.resetCredits.title.suffix"))
                    .foregroundStyle(PanelTheme.text)
            }
            .font(.system(size: 12, weight: .semibold))
            ForEach(Array(resetCredits.expirations.enumerated()), id: \.offset) { index, expiration in
                HStack(alignment: .firstTextBaseline, spacing: 18) {
                    Text(language.text("overview.resetCredits.item", index + 1))
                        .foregroundStyle(PanelTheme.text2)
                    Spacer(minLength: 12)
                    HStack(spacing: 0) {
                        Text(language.text("overview.resetCredits.expiresAt.prefix"))
                            .foregroundStyle(PanelTheme.text3)
                        Text(QuotaFormatters.reset(expiration, language: language.language))
                            .foregroundStyle(PanelTheme.chartAccent)
                        Text(language.text("overview.resetCredits.expiresAt.suffix"))
                            .foregroundStyle(PanelTheme.text3)
                    }
                    .fontDesign(.monospaced)
                }
                .font(.system(size: 10))
            }
            if missingCount > 0 {
                Text(language.text("overview.resetCredits.missingExpirations", missingCount))
                    .font(.system(size: 10))
                    .foregroundStyle(PanelTheme.text2)
            }
            if resetCredits.expirations.isEmpty, missingCount == 0 {
                Text(language.text("overview.resetCredits.noExpirations"))
                    .font(.system(size: 10))
                    .foregroundStyle(PanelTheme.text2)
            }
        }
        .padding(12)
        .frame(minWidth: 228)
    }

    private func codexResetCreditsHelp(_ resetCredits: CodexResetCredits) -> String {
        var lines = [language.text("overview.resetCredits.title", resetCredits.availableCount)]
        lines.append(contentsOf: resetCredits.expirations.enumerated().map { index, expiration in
            language.text(
                "overview.resetCredits.helpRow",
                index + 1,
                QuotaFormatters.reset(expiration, language: language.language)
            )
        })
        let missingCount = max(resetCredits.availableCount - resetCredits.expirations.count, 0)
        if missingCount > 0 {
            lines.append(language.text("overview.resetCredits.missingExpirations", missingCount))
        }
        if resetCredits.expirations.isEmpty, missingCount == 0 {
            lines.append(language.text("overview.resetCredits.noExpirations"))
        }
        return lines.joined(separator: "\n")
    }

    private var overviewBottomGrid: some View {
        VStack(alignment: .leading, spacing: 14) {
            overviewHourlyTokenCard
            HStack(alignment: .top, spacing: 14) {
                overviewListCard(title: language.text("overview.platform"), values: platformSummaries)
                overviewListCard(title: language.text("overview.model"), values: modelSummaries)
            }
        }
    }

    private func overviewStatus(for state: BalanceState?) -> (label: String, color: Color, background: Color) {
        guard let state else {
            return (language.text("settings.notConnected"), PanelTheme.text2, PanelTheme.surface2)
        }
        switch state {
        case .normal:
            return (language.text("overview.healthy"), PanelTheme.ok, PanelTheme.okSoft)
        case .low:
            return (language.text("overview.low"), PanelTheme.warn, PanelTheme.warnSoft)
        case .critical:
            return (language.text("overview.critical"), PanelTheme.danger, PanelTheme.dangerSoft)
        case .unknown:
            return (language.text("overview.quotaUnavailable"), PanelTheme.text2, PanelTheme.surface2)
        }
    }

    private var overviewHourlyTokenCard: some View {
        let chart = hourlyTokenChartSnapshot()
        let axisIndices = hourlyChartAxisIndices
        // Let the card size itself from the plot and tick labels so
        // the bottom axis is never clipped by a fixed outer height.
        return panelCard {
            HStack {
                Text(language.text("overview.todayHourlyTitle"))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
            }
            StackedBarChart(
                rows: chart.rows,
                todayLabel: language.text("panel.today"),
                tokenLabel: language.text("panel.totalTokens"),
                language: language.language
            )
                .frame(height: 92)
                .padding(.top, 4)
            GeometryReader { proxy in
                let plotWidth = max(proxy.size.width - 52, 1)
                ZStack(alignment: .topLeading) {
                    ForEach(axisIndices, id: \.self) { index in
                        let row = chart.rows[index]
                        let x = 44 + (CGFloat(index) + 0.5) / CGFloat(max(chart.rows.count, 1)) * plotWidth
                        // 横轴只显示开始时间；完整区间（开始-结束）见 hover 数据标签
                        Text(String(row.label.prefix(5)))
                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .fixedSize()
                            .position(x: x, y: 5)
                    }
                }
            }
            .frame(height: 10)
        }
    }

    private var platformSummaries: [BreakdownItem] {
        store.presentationSnapshot.topPlatforms(limit: 4).map(platformBreakdownItem)
    }

    func platformBreakdownItem(_ row: UsageBreakdownSnapshot) -> BreakdownItem {
        BreakdownItem(
            name: row.key.displayName(
                claudeCode: language.text("panel.claudeCode"),
                other: language.text("tokens.otherPlatform")
            ),
            value: row.total,
            share: row.share,
            color: breakdownColor(for: row.key)
        )
    }

    private var modelSummaries: [BreakdownItem] {
        let rows = store.presentationSnapshot.topModels(limit: 4)
        let colors = modelColors(for: rows)
        return rows.map { row in
            BreakdownItem(
                name: row.key.displayName(other: language.text("tokens.otherModel")),
                value: row.total,
                share: row.share,
                color: colors[row.id] ?? PanelTheme.modelFallback
            )
        }
    }

    private func modelColors(for rows: [UsageBreakdownSnapshot]) -> [String: Color] {
        let categories = rows.map { row in
            TokenChartCategory(
                id: row.id,
                name: row.key.displayName(),
                preferredPaletteIndex: UsageBreakdownColor.stableIndex(for: row.id)
            )
        }
        return categoryColors(for: categories)
    }

    func breakdownColor(for key: UsageBreakdownKey) -> Color {
        // 与 Token 看板柱状图、下拉框行共用同一索引映射（见 UsageBreakdownColor）。
        UsageBreakdownColor.color(for: key)
    }

    private func overviewListCard(title: String, values: [BreakdownItem]) -> some View {
        let rowHeight: CGFloat = 17
        let rowSpacing: CGFloat = 5

        // Keep overview and dashboard breakdown cards on the same compact grid.
        return panelCard(height: 170) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
                Spacer()
                Text(language.text("panel.today"))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(PanelTheme.text3)
            }
            VStack(spacing: rowSpacing) {
                ForEach(values) { item in
                    HStack(spacing: 8) {
                        HStack(spacing: 7) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(item.color)
                                .frame(width: 8, height: 8)
                            Text(item.name)
                                .font(.system(size: 10, weight: .regular, design: .monospaced))
                                .foregroundStyle(PanelTheme.text)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(QuotaFormatters.localizedTokens(item.value, language: language.language))
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text2)
                        Text(String(format: "%.1f%%", item.share * 100))
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .fontDesign(.monospaced)
                            .foregroundStyle(PanelTheme.text3)
                            .frame(width: 40, alignment: .trailing)
                    }
                    .frame(height: rowHeight)
                }
                if values.isEmpty {
                    Text(language.text("overview.noData"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(PanelTheme.text3)
                        .frame(height: rowHeight, alignment: .leading)
                }
            }
            .padding(.top, 3)
        }
    }


}
