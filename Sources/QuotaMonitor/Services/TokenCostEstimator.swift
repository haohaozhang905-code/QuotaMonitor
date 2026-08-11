import Foundation

/// 用本地 token 明细估算 DeepSeek 花费与余额可支撑天数。
///
/// 单价来自 DeepSeek 官方定价页（人民币，元/百万 token，2026-08 版本）：
/// deepseek-v4-flash：缓存命中 0.02 / 未命中 1 / 输出 2；
/// deepseek-v4-pro：缓存命中 0.025 / 未命中 3 / 输出 6。
/// 思考模式按输出价计费；cache_write 未单列计费（input_tokens 已包含写入部分）。
enum TokenCostEstimator {
    struct Price: Sendable {
        var inputPerMillion: Double        // 未命中缓存
        var cachedInputPerMillion: Double  // 命中缓存
        var cacheWritePerMillion: Double   // 写入缓存
        var outputPerMillion: Double
        var reasoningPerMillion: Double
    }

    static let flashPrice = Price(
        inputPerMillion: 1.0,
        cachedInputPerMillion: 0.02,
        cacheWritePerMillion: 0.0,
        outputPerMillion: 2.0,
        reasoningPerMillion: 2.0
    )

    static let proPrice = Price(
        inputPerMillion: 3.0,
        cachedInputPerMillion: 0.025,
        cacheWritePerMillion: 0.0,
        outputPerMillion: 6.0,
        reasoningPerMillion: 6.0
    )

    static func price(for model: String?) -> Price {
        let name = (model ?? "").lowercased()
        return name.contains("pro") ? proPrice : flashPrice
    }

    static func estimatedCost(tokens: TokenTotals, model: String? = nil) -> Double {
        let price = price(for: model)
        // input_tokens 已包含缓存命中部分，未命中 = input - cached，避免重复计费。
        let miss = max(Double(tokens.input) - Double(tokens.cachedInput), 0)
        let total = miss * price.inputPerMillion
            + Double(tokens.cachedInput) * price.cachedInputPerMillion
            + Double(tokens.output) * price.outputPerMillion
            + Double(tokens.reasoning) * price.reasoningPerMillion
        return total / 1_000_000
    }

    static func estimatedCost(tokens: DailyTokenUsage, model: String? = nil) -> Double {
        estimatedCost(
            tokens: TokenTotals(
                input: tokens.input,
                cachedInput: tokens.cachedInput,
                cacheWriteInput: tokens.cacheWriteInput,
                output: tokens.output,
                reasoning: tokens.reasoning
            ),
            model: model
        )
    }

    /// 缓存命中率：命中 ÷ (未命中 + 命中)。
    static func cacheHitRate(tokens: DailyTokenUsage) -> Double? {
        let hit = tokens.cachedInput
        let total = tokens.input
        guard total > 0 else { return nil }
        return Double(hit) / Double(total)
    }

    /// 余额能支撑的天数：余额 ÷ 近 7 日日均消耗，向下取整，封顶 30。
    static func daysSupported(balance: Double, history: [DailyTokenUsage], model: String? = nil) -> Int? {
        let recent = Array(history.suffix(7))
        guard !recent.isEmpty else { return nil }
        let dailyAverage = recent.reduce(0.0) { $0 + estimatedCost(tokens: $1, model: model) } / Double(recent.count)
        guard dailyAverage > 0 else { return nil }
        return min(Int((balance / dailyAverage).rounded(.down)), 30)
    }
}
