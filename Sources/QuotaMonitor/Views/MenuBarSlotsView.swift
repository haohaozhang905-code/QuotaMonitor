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
    let balanceDays: Int?
    let balanceCurrency: String?
    var isLoading = false
    var loadingFrame = 0

    var body: some View {
        HStack(spacing: 7) {
            if isLoading {
                MenuBarLoadingGlyph(phase: loadingFrame)
            } else if codexRoute == .deepseek, claudeRoute == .deepseek {
                slot(icon: .deepSeek, value: balanceText, health: balanceHealth)
            } else {
                if codexRoute != .unknown {
                    slot(icon: .codex, value: codexValue, health: codexHealth)
                }
                if claudeRoute != .unknown || claudeRemaining != nil {
                    slot(icon: .claude, value: claudeValue, health: claudeHealth)
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

    private var codexHealth: QuotaHealth {
        if codexRoute == .deepseek { return balanceHealth }
        return QuotaHealth(remaining: codexRemaining)
    }

    private var claudeHealth: QuotaHealth {
        if claudeRoute == .deepseek { return balanceHealth }
        return QuotaHealth(remaining: claudeRemaining)
    }

    private var balanceHealth: QuotaHealth {
        QuotaHealth(balanceAmount: balanceAmount, estimatedDays: balanceDays)
    }

    private func slot(icon: BrandIconKind, value: String, health: QuotaHealth) -> some View {
        HStack(spacing: 4) {
            BrandIconView(
                kind: icon,
                size: icon == .codex ? 17 : 14,
                monochromeColor: .white
            )
                .frame(width: 18, height: 18)
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .fontDesign(.monospaced)
                // 菜单栏保持统一白色；健康度通过下拉面板和 VoiceOver 传达。
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }
}
