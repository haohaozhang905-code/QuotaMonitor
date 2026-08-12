import SwiftUI

/// 下拉框宽度（与设计稿一致）。
enum DropdownLayout {
    static let width: CGFloat = 360
    static let horizontalPadding: CGFloat = 14
}

struct DropdownHeader: View {
    let title: String
    let updated: String

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
                Text(updated)
                    .font(.system(size: 10.5))
                    .fontDesign(.monospaced)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, DropdownLayout.horizontalPadding)
            .padding(.top, 15)
            .padding(.bottom, 1)
        }
        .frame(width: DropdownLayout.width, alignment: .leading)
        .fontDesign(.monospaced)
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
                .font(.system(size: 34, weight: .semibold))
                .fontDesign(.monospaced)
                .foregroundStyle(.primary)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            if let comparison {
                Text(comparison)
                    .font(.system(size: 10, weight: .medium))
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
        case .neutral: .secondary
        case .success: PanelTheme.ok
        case .warning: PanelTheme.warn
        case .danger: PanelTheme.claude
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
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
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
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
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
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    if let route {
                        Text(route)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 100, alignment: .leading)
            ForEach(metrics) { metric in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(metric.label)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        Text(metric.value)
                            .font(.system(size: 12, weight: .semibold))
                            .fontDesign(.monospaced)
                            .foregroundStyle(.primary)
                    }
                    if !metric.detail.isEmpty {
                        Text(metric.detail)
                            .font(.system(size: 9.5))
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text(status)
                .font(.system(size: 10.5, weight: .medium))
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
                .font(.system(size: 11.5))
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(amount)
                .font(.system(size: 10.5))
                .fontDesign(.monospaced)
                .foregroundStyle(.primary)
                .frame(width: 70, alignment: .trailing)
            Text(share)
                .font(.system(size: 9.5))
                .fontDesign(.monospaced)
                .foregroundStyle(.secondary)
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
            .font(.system(size: 11.5))
            .foregroundStyle(.secondary)
            .padding(.horizontal, DropdownLayout.horizontalPadding)
            .padding(.vertical, 5)
            .frame(width: DropdownLayout.width, alignment: .leading)
    }
}

// MARK: - 工具函数

enum DropdownRows {
    /// 把 SwiftUI 行装进 NSMenuItem（固定宽度，按内容高度撑开菜单项）。
    @MainActor
    static func menuItem<Content: View>(_ row: Content, height: CGFloat? = nil) -> NSMenuItem {
        let item = NSMenuItem()
        let hosting = NSHostingView(rootView: row)
        let fitting = hosting.fittingSize
        hosting.frame = NSRect(
            x: 0,
            y: 0,
            width: max(fitting.width, DropdownLayout.width),
            height: height ?? max(fitting.height, 24)
        )
        item.view = hosting
        return item
    }

    @MainActor
    static func spacer(height: CGFloat) -> NSMenuItem {
        menuItem(Color.clear.frame(width: DropdownLayout.width, height: height), height: height)
    }
}
