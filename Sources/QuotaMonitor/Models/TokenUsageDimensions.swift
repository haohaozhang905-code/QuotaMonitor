import Foundation

/// Token 看板的业务维度。平台回答“通过哪个工具使用”，模型回答“实际调用了什么模型”，
/// 路由回答“请求最终由哪一方提供服务”。三者保持独立，避免把 DeepSeek 路由误当成一个工具。
enum TokenPlatform: String, CaseIterable, Codable, Identifiable, Sendable {
    case codex
    case claude
    case workbuddy
    case kimi
    case opencode
    case hermes
    case openclaw
    case cursor
    case antigravity
    case cline
    case qwen
    case qwenWork
    case traeWork
    case grok
    case copilot
    case pi
    case zed
    case kilo
    case mimo
    case zcode
    case kiro
    case codebuddy
    case qoder
    case proma
    case reasonix

    var id: String { rawValue }
}

extension TokenPlatform {
    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude"
        case .workbuddy: "WorkBuddy"
        case .kimi: "Kimi"
        case .opencode: "OpenCode"
        case .hermes: "Hermes Agent"
        case .openclaw: "OpenClaw"
        case .cursor: "Cursor"
        case .antigravity: "Antigravity"
        case .cline: "Cline"
        case .qwen: "Qwen CLI"
        case .qwenWork: "千问办公"
        case .traeWork: "Trae Work"
        case .grok: "Grok Build"
        case .copilot: "GitHub Copilot"
        case .pi: "Pi"
        case .zed: "Zed"
        case .kilo: "Kilo Code"
        case .mimo: "MiMo Code"
        case .zcode: "ZCode / GLM"
        case .kiro: "Kiro"
        case .codebuddy: "CodeBuddy"
        case .qoder: "Qoder"
        case .proma: "Proma"
        case .reasonix: "Reasonix"
        }
    }
}

enum TokenClient: String, CaseIterable, Codable, Identifiable, Sendable {
    case cli
    case desktop
    case estimated
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

    /// 模型维度统一使用小写，避免同一模型只因大小写不同被拆成多个桶。
    /// 日志里的空值、auto 和 unknown 都表示没有可靠模型归属，因此统一进入同一个 unknown 桶。
    static func canonical(_ rawValue: String?) -> String {
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let normalized = trimmed.lowercased()
        switch normalized {
        case "", "auto", unknown:
            return unknown
        default:
            return normalized
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

    /// Cache keys historically used a day-only string. New scans retain the
    /// local hour so the overview can render a real 24-hour distribution while
    /// still accepting old cached entries.
    static func bucketKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HH"
        return formatter.string(from: date)
    }

    static func date(fromBucketKey key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = key.count > 10 ? "yyyy-MM-dd-HH" : "yyyy-MM-dd"
        return formatter.date(from: key)
    }
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
