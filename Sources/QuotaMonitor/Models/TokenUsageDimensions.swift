import Foundation

/// Token 看板的业务维度。平台回答“通过哪个工具使用”，模型回答“实际调用了什么模型”，
/// 路由回答“请求最终由哪一方提供服务”。三者保持独立，避免把 DeepSeek 路由误当成一个工具。
enum TokenPlatform: String, CaseIterable, Identifiable, Sendable {
    case codex
    case claude
    case workbuddy
    case kimi

    var id: String { rawValue }
}

extension TokenPlatform {
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .workbuddy: "WorkBuddy"
        case .kimi: "Kimi"
        }
    }
}

enum TokenClient: String, CaseIterable, Identifiable, Sendable {
    case cli
    case desktop
    case plugin
    case unknown

    var id: String { rawValue }
}

enum TokenProvider: String, CaseIterable, Identifiable, Sendable {
    case official
    case deepseek
    case unknown

    var id: String { rawValue }
}

/// 用于历史看板的最小聚合单元。第一版按小时保存，查询近 7/30 日时再按天汇总。
/// 这样“今日”可以继续细分到小时，同时不会把每一条请求永久存成大体量事件日志。
struct TokenUsageBucket: Identifiable, Sendable {
    let bucketStart: Date
    let platform: TokenPlatform
    let client: TokenClient
    let model: String
    let provider: TokenProvider
    let totals: TokenTotals

    var id: String {
        [
            String(bucketStart.timeIntervalSince1970),
            platform.rawValue,
            client.rawValue,
            model,
            provider.rawValue
        ].joined(separator: "|")
    }

    var total: Int { totals.input + totals.output }
}

extension TokenUsageBucket {
    static func combining(_ buckets: [TokenUsageBucket]) -> [TokenUsageBucket] {
        var grouped: [String: TokenUsageBucket] = [:]
        for bucket in buckets {
            let key = bucket.id
            if let existing = grouped[key] {
                grouped[key] = TokenUsageBucket(
                    bucketStart: existing.bucketStart,
                    platform: existing.platform,
                    client: existing.client,
                    model: existing.model,
                    provider: existing.provider,
                    totals: existing.totals.adding(bucket.totals)
                )
            } else {
                grouped[key] = bucket
            }
        }
        return grouped.values.sorted {
            if $0.bucketStart != $1.bucketStart { return $0.bucketStart < $1.bucketStart }
            return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending
        }
    }
}
