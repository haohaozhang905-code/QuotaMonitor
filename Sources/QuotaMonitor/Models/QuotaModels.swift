import Foundation

extension JSONDecoder.DateDecodingStrategy {
    /// Codex 服务在不同端点会返回带或不带小数秒的 ISO-8601 时间。
    static let iso8601WithFractionalSeconds = custom { decoder in
        let value = try decoder.singleValueContainer().decode(String.self)
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }

        let basic = ISO8601DateFormatter()
        if let date = basic.date(from: value) { return date }
        throw DecodingError.dataCorruptedError(
            in: try decoder.singleValueContainer(),
            debugDescription: "Invalid ISO-8601 date"
        )
    }
}

struct UsageResponse: Decodable, Sendable {
    let providers: [ProviderUsage]
}

struct ProviderUsage: Decodable, Identifiable, Sendable {
    let providerId: String
    let displayName: String
    let plan: String?
    let lines: [UsageLine]
    let fetchedAt: Date?
    /// DeepSeek 模式下回填：余额货币（如 CNY）与当前模型名（用于单价估算）。
    let balanceCurrency: String?
    let model: String?

    init(
        providerId: String,
        displayName: String,
        plan: String?,
        lines: [UsageLine],
        fetchedAt: Date?,
        balanceCurrency: String? = nil,
        model: String? = nil
    ) {
        self.providerId = providerId
        self.displayName = displayName
        self.plan = plan
        self.lines = lines
        self.fetchedAt = fetchedAt
        self.balanceCurrency = balanceCurrency
        self.model = model
    }

    var id: String { providerId }
    private var rawSession: UsageLine? { progress(named: ["session", "5h", "five hour"]) }
    var session: UsageLine? {
        guard let line = rawSession else { return nil }
        return isReclassifiedWeekly(line) ? nil : line
    }
    var weekly: UsageLine? {
        if let line = rawSession, isReclassifiedWeekly(line) { return line }
        return progress(named: ["weekly", "week", "seven day", "spark"])
    }
    var credits: UsageLine? { progress(named: ["credits", "reset", "resets"]) }

    /// DeepSeek 模式的余额行（type == "balance"）。
    var balanceLine: UsageLine? { lines.first { $0.type == "balance" } }
    /// 余额金额（元）。
    var balanceAmount: Double? { balanceLine?.used }
    /// 余额预计可支撑的天数（由余额 ÷ 近 7 日日均消耗算出，封顶 30）。
    var balanceDays: Int? { balanceLine?.limit.map { Int($0.rounded(.down)) } }

    func effectiveResetAt(for line: UsageLine) -> Date? {
        guard let reset = line.resetsAt else { return nil }
        if rawSession?.id == line.id, isReclassifiedWeekly(line) { return reset }
        guard let durationMs = line.periodDurationMs, let fetchedAt else { return reset }
        let duration = durationMs / 1000
        if reset.timeIntervalSince(fetchedAt) > duration * 2 {
            return fetchedAt.addingTimeInterval(duration)
        }
        return reset
    }

    private func isReclassifiedWeekly(_ line: UsageLine) -> Bool {
        guard providerId.lowercased() == "codex", let fetchedAt, let reset = line.resetsAt else { return false }
        return reset.timeIntervalSince(fetchedAt) > 12 * 60 * 60
    }

    private func progress(named names: Set<String>) -> UsageLine? {
        lines.first { $0.type == "progress" && names.contains($0.label.lowercased()) }
    }

}

struct UsageLine: Decodable, Identifiable, Sendable {
    let type: String
    let label: String
    let used: Double?
    let limit: Double?
    let resetsAt: Date?
    let periodDurationMs: Double?
    let value: String?
    let subtitle: String?

    var id: String { "\(type)-\(label)" }
    var usedPercent: Double? {
        guard let used, let limit, limit > 0 else { return nil }
        return min(max(used / limit, 0), 1)
    }
    var remainingPercent: Double? { usedPercent.map { 1 - $0 } }
    var remainingCount: Int? {
        guard let used, let limit else { return nil }
        return max(Int((limit - used).rounded(.down)), 0)
    }
}

enum QuotaHealth: String, Sendable {
    case healthy = "健康"
    case warning = "警告"
    case critical = "危急"
    case unknown = "未知"

    init(remaining: Double?) {
        guard let remaining else { self = .unknown; return }
        if remaining <= 0.10 { self = .critical }
        else if remaining <= 0.50 { self = .warning }
        else { self = .healthy }
    }
}

struct CodexResetCredits: Sendable, Equatable {
    let availableCount: Int
    let expirations: [Date]
    let fetchedAt: Date
}
