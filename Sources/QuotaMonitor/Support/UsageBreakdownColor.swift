import SwiftUI

/// 平台 / 模型在全 App 中的统一分类色。
/// 柱状图、hover 标签、排行卡、下拉框行共用同一索引映射，
/// 保证同一个平台或模型在任何位置都是同一种颜色。
enum UsageBreakdownColor {
    /// FNV-1a 稳定哈希索引（与原 stablePaletteIndex 算法一致）
    static func stableIndex(for value: String) -> Int {
        let hash = value.utf8.reduce(UInt32(2166136261)) { partial, byte in
            (partial ^ UInt32(byte)) &* 16777619
        }
        return Int(hash % UInt32(PanelTheme.categoryPalette.count))
    }

    /// 平台 / 模型 → 分类色板索引。
    /// 知名平台固定索引（与 Token 看板柱状图 chartCategory 的映射一致）；
    /// 其余平台与模型按稳定哈希索引。other 类返回 -1（调用方使用 fallback 色）。
    static func categoryIndex(for key: UsageBreakdownKey) -> Int {
        let paletteCount = PanelTheme.categoryPalette.count
        switch key {
        case let .platformClient(platform, client):
            switch (platform, client) {
            case (.codex, _): return 0 % paletteCount
            case (.claude, .cli): return 2 % paletteCount
            case (.claude, _): return 1 % paletteCount
            case (.workbuddy, _): return 3 % paletteCount
            default: return stableIndex(for: platform.rawValue)
            }
        case let .model(model): return stableIndex(for: model)
        case .otherModels, .otherPlatforms: return -1
        }
    }

    static func color(for key: UsageBreakdownKey) -> Color {
        let index = categoryIndex(for: key)
        guard index >= 0 else { return PanelTheme.modelFallback }
        return PanelTheme.categoryPalette[index]
    }
}
