import SwiftUI

/// 下拉框宽度（与设计稿一致）。
enum DropdownLayout {
    static let width: CGFloat = 360
    static let horizontalPadding: CGFloat = 12
    static let cornerRadius: CGFloat = 20
}

struct DropdownHeader: View {
    let title: String
    let updated: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(PanelTheme.text)
                Spacer(minLength: 8)
                Text(updated)
                    .font(.system(size: 10, design: .monospaced))
                    .fontDesign(.monospaced)
                    .foregroundStyle(PanelTheme.text2)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, DropdownLayout.horizontalPadding)
            .padding(.top, 15)
            .padding(.bottom, 1)
        }
        .frame(width: DropdownLayout.width, alignment: .leading)
    }
}

struct DropdownHero: View {
    let value: String
    let label: String
    let comparison: String?
    let comparisonColor: Color

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text)
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(PanelTheme.text2)
            if let comparison {
                Text(comparison)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .fontDesign(.monospaced)
                    .foregroundStyle(comparisonColor)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(comparisonColor.opacity(0.14), in: Capsule())
                    .fixedSize()
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DropdownLayout.horizontalPadding)
        .padding(.top, 4)
        .padding(.bottom, 13)
        .frame(width: DropdownLayout.width, alignment: .leading)
    }
}

enum DropdownStatusTone {
    case neutral
    case success
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral: PanelTheme.text2
        case .success: PanelTheme.ok
        case .warning: PanelTheme.warn
        case .danger: PanelTheme.danger
        }
    }
}

/// 只在读取中、过期、连接但未读到额度或失败时出现；正常状态不额外占空间。
struct DropdownStatusRow: View {
    let text: String
    let tone: DropdownStatusTone

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(PanelTheme.text2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DropdownLayout.horizontalPadding)
        .padding(.top, 1)
        .padding(.bottom, 8)
        .frame(width: DropdownLayout.width, alignment: .leading)
    }
}

// MARK: - 区块标题

struct DropdownSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(PanelTheme.text2)
            .padding(.horizontal, DropdownLayout.horizontalPadding)
            .padding(.vertical, 3)
            .frame(width: DropdownLayout.width, alignment: .leading)
    }
}

struct DropdownQuotaLine: View {
    struct Metric: Identifiable {
        let label: String
        let value: String
        let detail: String
        let health: QuotaHealth

        var id: String { label }
    }

    let icon: BrandIconKind
    let title: String
    let route: String?
    let metrics: [Metric]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                BrandIconView(kind: icon, size: 18)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(PanelTheme.text)
                    if let route {
                        Text(route)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(PanelTheme.text2)
                    }
                }
            }
            .frame(width: 100, alignment: .leading)
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(metric.label)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(PanelTheme.text2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                        Spacer(minLength: 4)
                        HStack(spacing: 4) {
                            if metric.health == .warning || metric.health == .critical {
                                Image(systemName: metric.health == .critical ? "exclamationmark.circle.fill" : "exclamationmark.circle")
                                    .font(.system(size: 8, weight: .semibold))
                                    .accessibilityHidden(true)
                            }
                            Text(metric.value)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .fontDesign(.monospaced)
                        }
                        .foregroundStyle(PanelTheme.quotaValueColor(metric.health))
                    }
                    if !metric.detail.isEmpty {
                        Text(metric.detail)
                            .font(.system(size: 9, design: .monospaced))
                            .fontDesign(.monospaced)
                            // 日期与上方百分比保持同一健康度颜色，不再重复显示状态文案。
                            .foregroundStyle(PanelTheme.quotaValueColor(metric.health))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(metric.label), \(metric.value), \(metric.detail)")
            }
        }
        .padding(.horizontal, DropdownLayout.horizontalPadding)
        .padding(.vertical, 8)
        .frame(width: DropdownLayout.width, alignment: .leading)
    }
}

struct DropdownQuotaStatusLine: View {
    let icon: BrandIconKind
    let title: String
    let status: String
    let tone: DropdownStatusTone

    var body: some View {
        HStack(spacing: 8) {
            BrandIconView(kind: icon, size: 18)
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(PanelTheme.text)
            Spacer(minLength: 8)
            Text(status)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(tone.color)
                .lineLimit(1)
        }
        .padding(.horizontal, DropdownLayout.horizontalPadding)
        .padding(.vertical, 10)
        .frame(width: DropdownLayout.width, alignment: .leading)
    }
}

// MARK: - 用量区

struct DropdownCompactRow: View {
    let name: String
    let amount: String
    let share: String

    var body: some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 11, design: .monospaced))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text2)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(amount)
                .font(.system(size: 10, design: .monospaced))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text)
                .frame(width: 70, alignment: .trailing)
            Text(share)
                .font(.system(size: 9, design: .monospaced))
                .fontDesign(.monospaced)
                .foregroundStyle(PanelTheme.text2)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, DropdownLayout.horizontalPadding)
        .padding(.vertical, 3)
        .frame(width: DropdownLayout.width, alignment: .leading)
    }
}

struct DropdownEmptyRow: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(PanelTheme.text2)
            .padding(.horizontal, DropdownLayout.horizontalPadding)
            .padding(.vertical, 5)
            .frame(width: DropdownLayout.width, alignment: .leading)
    }
}

// MARK: - 状态栏 Popover

struct DropdownPopoverView: View {
    let store: QuotaStore
    @Bindable var language: LanguageSettings
    let openPanel: () -> Void
    let refresh: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    private var presentation: DropdownPresentation { store.dropdownPresentation }

    var body: some View {
        VStack(spacing: 0) {
            DropdownHeader(title: QuotaMonitorIdentity.displayName, updated: updatedText)
            DropdownHero(
                value: heroValue,
                label: language.text("menu.todayTokensLabel"),
                comparison: heroComparison,
                comparisonColor: comparisonColor
            )
            if let status = statusRow {
                DropdownStatusRow(text: status.text, tone: status.tone)
            }
            if !presentation.quotaItems.isEmpty {
                DropdownSectionHeader(title: language.text("menu.quotaSection"))
                ForEach(presentation.quotaItems) { item in
                    quotaLine(item)
                }
            }
            DropdownSectionHeader(title: language.text("menu.platformSection"))
            if presentation.platformToday.isEmpty {
                DropdownEmptyRow(text: language.text("menu.noUsage"))
            } else {
                ForEach(presentation.platformToday) { row in
                    DropdownCompactRow(
                        name: row.key.displayName(claudeCode: language.text("panel.claudeCode")),
                        amount: QuotaFormatters.localizedTokens(row.total, language: language.language),
                        share: percentText(row.share)
                    )
                }
            }
            DropdownSectionHeader(title: language.text("menu.modelSection"))
            if presentation.topModels.isEmpty {
                DropdownEmptyRow(text: language.text("menu.noUsage"))
            } else {
                ForEach(presentation.topModels) { row in
                    DropdownCompactRow(
                        name: row.key.displayName(other: language.text("tokens.otherModel")),
                        amount: QuotaFormatters.localizedTokens(row.total, language: language.language),
                        share: percentText(row.share)
                    )
                }
            }
            DropdownHairline()
                .padding(.horizontal, DropdownLayout.horizontalPadding)
                .padding(.top, 6)
                .padding(.bottom, 2)
            DropdownActionButton(title: language.text("menu.openPanel"), icon: "rectangle.on.rectangle", shortcut: "⌘ O", action: openPanel)
                .keyboardShortcut("o", modifiers: .command)
            DropdownActionButton(title: language.text("menu.refresh"), icon: "arrow.clockwise", shortcut: "⌘ R", action: refresh)
                .keyboardShortcut("r", modifiers: .command)
            DropdownActionButton(title: language.text("menu.settings"), icon: "slider.horizontal.3", shortcut: "⌘ ,", action: openSettings)
                .keyboardShortcut(",", modifiers: .command)
            DropdownHairline()
                .padding(.horizontal, DropdownLayout.horizontalPadding)
                .padding(.vertical, 4)
            DropdownActionButton(title: language.text("menu.quit"), icon: "power", shortcut: "⌘ Q", role: .destructive, action: quit)
                .keyboardShortcut("q", modifiers: .command)
                .padding(.bottom, 5)
        }
        .frame(width: DropdownLayout.width)
        .background(PanelTheme.surfaceFloat, in: RoundedRectangle(cornerRadius: DropdownLayout.cornerRadius, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: DropdownLayout.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DropdownLayout.cornerRadius, style: .continuous)
                .stroke(PanelTheme.border, lineWidth: 0.5)
        )
    }

    private var updatedText: String {
        guard let date = presentation.updatedAt else { return language.text("menu.notUpdated") }
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return language.text("menu.updatedAt", formatter.string(from: date))
    }

    private var heroValue: String {
        switch presentation.availability {
        case .ready, .stale:
            QuotaFormatters.localizedTokens(presentation.today.total, language: language.language)
        case .loading, .connectedOnly, .unavailable, .error:
            "—"
        }
    }

    private var heroComparison: String? {
        guard presentation.availability == .ready || presentation.availability == .stale,
              let percent = presentation.today.trendPercent else { return nil }
        let key = percent >= 0 ? "menu.vsYesterdayUp" : "menu.vsYesterdayDown"
        return language.text(key, String(format: "%.1f", abs(percent)))
    }

    private var comparisonColor: Color {
        guard let percent = presentation.today.trendPercent else { return PanelTheme.text2 }
        return percent >= 0 ? PanelTheme.claude : PanelTheme.ok
    }

    private var statusRow: (text: String, tone: DropdownStatusTone)? {
        return switch presentation.availability {
        case .ready: nil
        case .loading: (language.text("menu.statusLoading"), .neutral)
        case .connectedOnly: (language.text("menu.statusConnectedNoQuota"), .warning)
        case .unavailable: (language.text("menu.statusUnavailable"), .warning)
        case .stale: (language.text("menu.statusStale"), .warning)
        case .error: (language.text("menu.statusError"), .danger)
        }
    }

    @ViewBuilder
    private func quotaLine(_ item: DropdownQuotaPresentation) -> some View {
        let icon = icon(for: item.platform)
        switch item.state {
        case let .official(plan, session, weekly):
            let sessionLabel = item.platform == .codex
                ? language.text("panel.sessionLeft")
                : language.text("overview.sessionQuota")
            DropdownQuotaLine(
                icon: icon,
                title: item.platform.displayName,
                route: plan ?? language.text("panel.official"),
                metrics: [
                    quotaMetric(label: sessionLabel, metric: session),
                    quotaMetric(label: language.text("panel.weeklyLeft"), metric: weekly)
                ]
            )
        case let .sharedBalance(amount, currency, estimatedDays):
            let health = QuotaHealth(balanceAmount: amount, estimatedDays: estimatedDays)
            DropdownQuotaLine(
                icon: icon,
                title: item.platform.displayName,
                route: language.text("panel.deepSeekRouteTag"),
                metrics: [
                    .init(
                        label: language.text("menu.balance"),
                        value: QuotaFormatters.money(amount, currency: currency),
                        detail: quotaStatusText(health),
                        health: health
                    ),
                    .init(
                        label: language.text("menu.daysLeft"),
                        value: estimatedDays.map { language.text("panel.daysShortLabel", "\($0)") } ?? "—",
                        detail: language.text("overview.estimateNote"),
                        health: health
                    )
                ]
            )
        case .connectedWithoutQuota:
            DropdownQuotaStatusLine(
                icon: icon,
                title: item.platform.displayName,
                status: language.text("menu.quotaConnectedNoData"),
                tone: .warning
            )
        case .unavailable:
            DropdownQuotaStatusLine(
                icon: icon,
                title: item.platform.displayName,
                status: language.text("menu.quotaUnavailable"),
                tone: .neutral
            )
        }
    }

    private func quotaMetric(label: String, metric: DropdownQuotaMetricPresentation?) -> DropdownQuotaLine.Metric {
        let health = QuotaHealth(remaining: metric?.remainingPercent)
        let detail = metric?.resetsAt.map {
            language.text(
                "overview.resetAfter",
                QuotaFormatters.reset($0, language: language.language)
            )
        } ?? ""
        return .init(
            label: label,
            value: metric?.remainingPercent.map(QuotaFormatters.percent) ?? "—",
            detail: detail,
            health: health
        )
    }

    private func quotaStatusText(_ health: QuotaHealth) -> String {
        switch health {
        case .healthy: language.text("quota.status.healthy")
        case .warning: language.text("quota.status.warning")
        case .critical: language.text("quota.status.critical")
        case .unknown: language.text("quota.status.pendingEstimate")
        }
    }

    private func icon(for platform: TokenPlatform) -> BrandIconKind {
        switch platform {
        case .codex: .codex
        case .claude: .claude
        case .workbuddy: .workBuddy
        default: .deepSeek
        }
    }

    private func percentText(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}

private struct DropdownHairline: View {
    var body: some View {
        Rectangle()
            .fill(PanelTheme.hairlineStrong)
            .frame(height: 1)
    }
}

private struct DropdownActionButton: View {
    let title: String
    let icon: String
    let shortcut: String
    var role: ButtonRole?
    let action: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .frame(width: 14)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                Spacer(minLength: 8)
                Text(shortcut)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(PanelTheme.text2)
                    .frame(width: 30, alignment: .trailing)
            }
            .foregroundStyle(role == .destructive ? PanelTheme.danger : PanelTheme.text)
            .padding(.horizontal, DropdownLayout.horizontalPadding)
            .frame(height: 30)
            .background {
                // 参考 iOS 快捷面板行 hover：背景左右留边，hover 时浮起（投影蒙版）。
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        hovered
                            ? (role == .destructive ? PanelTheme.danger.opacity(0.10) : PanelTheme.surface2)
                            : .clear
                    )
                    .padding(.horizontal, 6)
                    .shadow(
                        color: hovered ? Color.black.opacity(0.12) : .clear,
                        radius: hovered ? 3 : 0,
                        y: hovered ? 1 : 0
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
