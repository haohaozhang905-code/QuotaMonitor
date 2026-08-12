import Foundation

/// Token 看板的业务维度。平台回答“通过哪个工具使用”，模型回答“实际调用了什么模型”，
/// 路由回答“请求最终由哪一方提供服务”。三者保持独立，避免把 DeepSeek 路由误当成一个工具。
enum TokenPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
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

enum TokenClient: String, CaseIterable, Codable, Identifiable, Sendable {
    case cli
    case desktop
    case plugin
    case unknown

    var id: String { rawValue }
}

enum TokenProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case official
    case deepseek
    case unknown

    var id: String { rawValue }
}

enum TokenModelName {
    static let unknown = "unknown"

    /// 模型维度只保留可识别的实际模型名。日志里的空值、auto 和 unknown
    /// 都表示没有可靠模型归属，因此统一进入同一个 unknown 桶。
    static func canonical(_ rawValue: String?) -> String {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch trimmed.lowercased() {
        case "", "auto", unknown:
            return unknown
        default:
            return trimmed
        }
    }
}

/// 用于历史看板的最小聚合单元。第一版按小时保存，查询近 7/30 日时再按天汇总。
/// 这样“今日”可以继续细分到小时，同时不会把每一条请求永久存成大体量事件日志。
struct TokenUsageBucket: Codable, Equatable, Identifiable, Sendable {
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

/// 单个本地来源一次扫描产生的完整结果。总量、DeepSeek 子集和模型桶共享同一批输入，
/// 避免同一目录在一次刷新中被重复遍历，也避免三个结果来自不同写入时刻。
struct TokenSourceSnapshot: Equatable, Sendable {
    let history: [DailyTokenUsage]
    let deepSeekHistory: [DailyTokenUsage]
    let buckets: [TokenUsageBucket]

    init(buckets: [TokenUsageBucket]) {
        let combined = TokenUsageBucket.combining(buckets)
        self.buckets = combined
        self.history = Self.dailyHistory(from: combined)
        self.deepSeekHistory = Self.dailyHistory(from: combined.filter { $0.provider == .deepseek })
    }

    private static func dailyHistory(from buckets: [TokenUsageBucket]) -> [DailyTokenUsage] {
        var byDay: [String: (day: Date, totals: TokenTotals)] = [:]
        for bucket in buckets {
            let day = Calendar.current.startOfDay(for: bucket.bucketStart)
            let key = DailyTokenUsage.dayKey(for: day)
            let current = byDay[key]?.totals ?? TokenTotals()
            byDay[key] = (day, current.adding(bucket.totals))
        }
        return byDay.values
            .map { DailyTokenUsage(day: $0.day, totals: $0.totals) }
            .sorted { $0.day < $1.day }
    }
}

enum TokenSourceReadError: Error {
    case unreadableRoot(URL)
}

extension TokenUsageBucket {
    static func combining(_ buckets: [TokenUsageBucket]) -> [TokenUsageBucket] {
        var grouped: [String: TokenUsageBucket] = [:]
        for bucket in buckets {
            let normalized = TokenUsageBucket(
                bucketStart: bucket.bucketStart,
                platform: bucket.platform,
                client: bucket.client,
                model: TokenModelName.canonical(bucket.model),
                provider: bucket.provider,
                totals: bucket.totals
            )
            let key = normalized.id
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
                grouped[key] = normalized
            }
        }
        return grouped.values.sorted {
            if $0.bucketStart != $1.bucketStart { return $0.bucketStart < $1.bucketStart }
            return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending
        }
    }
}
