import Foundation

/// Codex 当前走哪条模型路由。
enum CodexRoute: Sendable, Equatable {
    /// ChatGPT 官方额度（Keychain 或旧 auth.json 里有 OpenAI access token）。
    case official
    /// cc-switch 切到 DeepSeek（auth.json 只有 OPENAI_API_KEY，config.toml 指向 api.deepseek.com）。
    case deepseek
    /// 识别不出来：不显示额度，只保留 token 统计。
    case unknown
}

/// 读取本地 Codex 配置判断当前路由。
/// 判定依据用 Codex 真正读取的配置与认证存储，不依赖 cc-switch 的数据库。
enum CodexRouteDetector {
    static func detect() -> CodexRoute {
        let home = codexHome()
        let authData = try? Data(contentsOf: home.appendingPathComponent("auth.json"))
        let configText = try? String(contentsOf: home.appendingPathComponent("config.toml"), encoding: .utf8)
        // DeepSeek 配置优先，避免切换器保留官方 Keychain 凭证时误判为官方。
        if configText?.contains("api.deepseek.com") == true { return .deepseek }
        if let authData, detect(authData: authData, configText: nil) == .official { return .official }
        if CodexAuthStore.hasOfficialAccessToken() { return .official }
        // New Codex versions keep OAuth credentials in an encrypted local
        // secrets file. The app-server owns decryption, so the file's
        // presence is enough to select the official refresh path.
        let encryptedAuth = home.appendingPathComponent("secrets/codex_auth.age")
        if FileManager.default.fileExists(atPath: encryptedAuth.path) { return .official }
        if let accessToken = ProcessInfo.processInfo.environment["CODEX_ACCESS_TOKEN"], !accessToken.isEmpty {
            return .official
        }
        return .unknown
    }

    static func detect(authData: Data?, configText: String?) -> CodexRoute {
        // 先看路由配置：config.toml 指向 DeepSeek 就按 DeepSeek 处理，
        // 即使 auth.json 里残留官方 token（cc-switch 保留官方凭据的场景）。
        if let configText, configText.contains("api.deepseek.com") {
            return .deepseek
        }
        if let authData,
           let envelope = try? JSONDecoder().decode(AuthEnvelope.self, from: authData),
           envelope.hasOpenAIToken {
            return .official
        }
        return .unknown
    }

    /// 从 config.toml 解析当前模型名（用于单价估算），取不到返回 nil。
    static func currentModel() -> String? {
        guard let text = try? String(contentsOf: codexHome().appendingPathComponent("config.toml"), encoding: .utf8) else {
            return nil
        }
        return currentModel(configText: text)
    }

    static func currentModel(configText: String?) -> String? {
        guard let configText else { return nil }
        for line in configText.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("model =") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            let value = parts[1]
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                return String(value.dropFirst().dropLast())
            }
            return value
        }
        return nil
    }

    private static func codexHome() -> URL {
        ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    private struct AuthEnvelope: Decodable {
        let tokens: Tokens?
        let accessToken: String?
        let openAIAPIKey: String?

        struct Tokens: Decodable {
            let accessToken: String?
            enum CodingKeys: String, CodingKey { case accessToken = "access_token" }
        }

        var hasOpenAIToken: Bool {
            let candidates = [tokens?.accessToken, accessToken, openAIAPIKey].compactMap { $0 }
            return candidates.contains { !$0.isEmpty }
        }

        enum CodingKeys: String, CodingKey {
            case tokens
            case accessToken = "access_token"
            case openAIAPIKey = "OPENAI_API_KEY"
        }
    }
}
