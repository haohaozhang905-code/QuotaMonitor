import Foundation

/// DeepSeek 开放平台的余额快照。
struct DeepSeekBalanceSnapshot: Codable, Equatable, Sendable {
    let balance: Double
    let currency: String
    let isAvailable: Bool
    let fetchedAt: Date
}

/// 从 DeepSeek 官方接口读取账户余额。
///
/// 数据来源：`GET https://api.deepseek.com/user/balance`
/// 凭证优先从 Codex 的兼容认证存储读取；Claude 单独走 DeepSeek 时，
/// 则读取 cc-switch / Claude settings 中当前 DeepSeek provider 的 token。
struct DeepSeekBalanceClient: Sendable {
    private let balanceURL = URL(string: "https://api.deepseek.com/user/balance")!
    private let maximumPayloadSize = 262_144

    func fetch() async throws -> DeepSeekBalanceSnapshot {
        let key = try loadAPIKey()
        var request = URLRequest(url: balanceURL)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BalanceError.requestFailed
        }
        guard data.count <= maximumPayloadSize else { throw BalanceError.payloadTooLarge }

        let envelope = try JSONDecoder().decode(BalanceEnvelope.self, from: data)
        guard let info = envelope.balanceInfos.first,
              let total = Double(info.totalBalance) else {
            throw BalanceError.malformed
        }
        return DeepSeekBalanceSnapshot(
            balance: total,
            currency: info.currency,
            isAvailable: envelope.isAvailable ?? true,
            fetchedAt: .now
        )
    }

    private func loadAPIKey() throws -> String {
        if CodexRouteDetector.detect() == .deepseek,
           let credentials = try? CodexAuthStore.load(),
           let key = credentials.openAIAPIKey, !key.isEmpty {
            return key
        }
        if let key = ClaudeRouteDetector.currentDeepSeekAPIKey(), !key.isEmpty { return key }
        if let credentials = try? CodexAuthStore.load(),
           let key = credentials.openAIAPIKey, !key.isEmpty {
            return key
        }
        throw BalanceError.authUnavailable
    }

    private enum BalanceError: Error {
        case authUnavailable
        case requestFailed
        case payloadTooLarge
        case malformed
    }

    private struct BalanceEnvelope: Decodable {
        let isAvailable: Bool?
        let balanceInfos: [BalanceInfo]
        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }

    private struct BalanceInfo: Decodable {
        let currency: String
        let totalBalance: String
        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
        }
    }
}
