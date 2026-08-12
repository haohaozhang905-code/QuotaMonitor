import Foundation

/// 用本地 token 明细估算 DeepSeek 花费与余额可支撑天数。
///
/// 单价来自 DeepSeek 官方定价页（每百万 token，2026-08 版本）：
/// deepseek-v4-flash：缓存命中 0.02 / 未命中 1 / 输出 2；
/// deepseek-v4-pro：缓存命中 0.025 / 未命中 3 / 输出 6。
/// 美元账户对应价格为 flash 0.0028 / 0.14 / 0.28，pro 0.003625 / 0.435 / 0.87。
/// reasoning_tokens 是 completion_tokens 的明细，不再次计费；cache_write 未单列计费。
enum TokenCostEstimator {
    struct Price: Sendable {
        var inputPerMillion: Double        // 未命中缓存
        var cachedInputPerMillion: Double  // 命中缓存
        var outputPerMillion: Double
    }

    private static func price(for model: String?, currency: String) -> Price? {
        let name = (model ?? "").lowercased()
        switch currency.uppercased() {
        case "CNY":
            return name.contains("pro")
                ? Price(inputPerMillion: 3.0, cachedInputPerMillion: 0.025, outputPerMillion: 6.0)
                : Price(inputPerMillion: 1.0, cachedInputPerMillion: 0.02, outputPerMillion: 2.0)
        case "USD":
            return name.contains("pro")
                ? Price(inputPerMillion: 0.435, cachedInputPerMillion: 0.003625, outputPerMillion: 0.87)
                : Price(inputPerMillion: 0.14, cachedInputPerMillion: 0.0028, outputPerMillion: 0.28)
        default:
            return nil
        }
    }

    static func estimatedCost(tokens: TokenTotals, model: String? = nil, currency: String = "CNY") -> Double? {
        guard let price = price(for: model, currency: currency) else { return nil }
        // input_tokens 已包含缓存命中部分，未命中 = input - cached，避免重复计费。
        let miss = max(Double(tokens.input) - Double(tokens.cachedInput), 0)
        let total = miss * price.inputPerMillion
            + Double(tokens.cachedInput) * price.cachedInputPerMillion
            + Double(tokens.output) * price.outputPerMillion
        return total / 1_000_000
    }

    static func estimatedCost(tokens: DailyTokenUsage, model: String? = nil, currency: String = "CNY") -> Double? {
        estimatedCost(
            tokens: TokenTotals(
                input: tokens.input,
                cachedInput: tokens.cachedInput,
                cacheWriteInput: tokens.cacheWriteInput,
                output: tokens.output,
                reasoning: tokens.reasoning
            ),
            model: model,
            currency: currency
        )
    }

    /// 缓存命中率：命中 ÷ (未命中 + 命中)。
    static func cacheHitRate(tokens: DailyTokenUsage) -> Double? {
        let hit = tokens.cachedInput
        let total = tokens.input
        guard total > 0 else { return nil }
        return Double(hit) / Double(total)
    }

    /// 余额能支撑的天数：余额 ÷ 最近七个自然日的日均消耗，向下取整，封顶 30。
    /// 每个桶使用自己的模型定价；没有请求的日期也进入七日分母。
    static func daysSupported(
        balance: Double,
        currency: String,
        buckets: [TokenUsageBucket],
        endingAt endDate: Date = .now,
        calendar: Calendar = .current
    ) -> Int? {
        let end = calendar.startOfDay(for: endDate)
        guard let start = calendar.date(byAdding: .day, value: -6, to: end) else { return nil }
        let recent = buckets.filter { bucket in
            guard bucket.provider == .deepseek else { return false }
            let day = calendar.startOfDay(for: bucket.bucketStart)
            return day >= start && day <= end
        }
        guard !recent.isEmpty else { return nil }
        var totalCost = 0.0
        for bucket in recent {
            guard let cost = estimatedCost(tokens: bucket.totals, model: bucket.model, currency: currency) else {
                return nil
            }
            totalCost += cost
        }
        let dailyAverage = totalCost / 7
        guard dailyAverage > 0 else { return nil }
        return min(Int((balance / dailyAverage).rounded(.down)), 30)
    }
}
