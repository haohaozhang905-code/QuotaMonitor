import AppKit
import SwiftUI

/// 菜单栏双槽位：Codex / Claude 各自展示产品图标 + 数值。
///
/// 规则（对应设计稿四种组合）：
/// - 官方路由：产品图标 + 剩余百分比；
/// - DeepSeek 路由：产品图标右上角加 DeepSeek 蓝点角标 + 共享余额；
/// - 双 DeepSeek：合并为一个鲸鱼槽位，只显示余额（“保留一个即可”）。
struct MenuBarSlotsView: View {
    let codexRoute: CodexRoute
    let claudeRoute: ClaudeRoute
    let codexRemaining: Double?
    let claudeRemaining: Double?
    let balanceAmount: Double?
    let balanceCurrency: String?
    var isLoading = false
    var loadingFrame = 0

    var body: some View {
        HStack(spacing: 7) {
            if isLoading {
                MenuBarLoadingGlyph(phase: loadingFrame)
            } else if codexRoute == .deepseek, claudeRoute == .deepseek {
                slot(icon: .deepSeek, value: balanceText, routed: false)
            } else {
                if codexRoute != .unknown {
                    slot(icon: .codex, value: codexValue, routed: codexRoute == .deepseek)
                }
                if claudeRoute != .unknown || claudeRemaining != nil {
                    slot(icon: .claude, value: claudeValue, routed: claudeRoute == .deepseek)
                }
                if codexRoute == .unknown, claudeRoute == .unknown, claudeRemaining == nil {
                    MenuBarQuotaGlyph()
                }
            }
        }
        .fixedSize()
        .fontDesign(.monospaced)
    }

    private var codexValue: String {
        codexRoute == .deepseek ? balanceText : QuotaFormatters.percent(codexRemaining)
    }

    private var claudeValue: String {
        if claudeRoute == .deepseek { return balanceText }
        if let claudeRemaining { return QuotaFormatters.percent(claudeRemaining) }
        return "--"
    }

    private var balanceText: String {
        guard let balanceAmount else { return "--" }
        return QuotaFormatters.money(balanceAmount, currency: balanceCurrency)
    }

    private func slot(icon: BrandIconKind, value: String, routed: Bool) -> some View {
        HStack(spacing: 4) {
            BrandIconView(
                kind: icon,
                size: icon == .codex ? 17 : 14,
                monochromeColor: .white
            )
                .frame(width: 18, height: 18)
                .overlay(alignment: .topTrailing) {
                    if routed {
                        Circle()
                            .fill(PanelTheme.deepseek)
                            .frame(width: 6, height: 6)
                            .overlay(Circle().stroke(.white, lineWidth: 1))
                            .offset(x: 1, y: 1)
                    }
                }
            Text(value)
                .font(.system(size: 12.5, weight: .regular))
                .fontDesign(.monospaced)
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}
