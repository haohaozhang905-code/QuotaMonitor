import CryptoKit
import Foundation
import Security

/// 读取 Codex CLI 的当前认证状态。
///
/// 新版 Codex 默认将认证信息保存到 macOS Keychain，并在成功保存后删除
/// `CODEX_HOME/auth.json`。这里先读取 Keychain，旧版或明确使用文件存储时
/// 再回退到 auth.json，避免为了看额度而重新落盘明文凭证。
enum CodexAuthStore {
    struct Credentials: Decodable, Sendable {
        struct Tokens: Decodable, Sendable {
            let accessToken: String?
            let accountId: String?

            enum CodingKeys: String, CodingKey {
                case accessToken = "access_token"
                case accountId = "account_id"
            }
        }

        let tokens: Tokens?
        let accessToken: String?
        let accountId: String?
        let openAIAPIKey: String?

        enum CodingKeys: String, CodingKey {
            case tokens
            case accessToken = "access_token"
            case accountId = "account_id"
            case openAIAPIKey = "OPENAI_API_KEY"
        }

        var resolvedAccessToken: String? {
            [tokens?.accessToken, accessToken].compactMap { $0 }.first { !$0.isEmpty }
        }

        var resolvedAccountId: String? {
            [tokens?.accountId, accountId].compactMap { $0 }.first { !$0.isEmpty }
        }
    }

    private static let keychainService = "Codex Auth"
    private static let maximumPayloadSize = 262_144

    static func load() throws -> Credentials {
        let home = codexHome()
        if let accessToken = ProcessInfo.processInfo.environment["CODEX_ACCESS_TOKEN"], !accessToken.isEmpty {
            return Credentials(
                tokens: Credentials.Tokens(accessToken: accessToken, accountId: nil),
                accessToken: nil,
                accountId: nil,
                openAIAPIKey: nil
            )
        }
        if let credentials = try loadFromKeychain(home: home) {
            return credentials
        }
        if let credentials = try loadFromFile(home: home) {
            return credentials
        }
        throw AuthError.unavailable
    }

    static func hasOfficialAccessToken() -> Bool {
        (try? load().resolvedAccessToken) != nil
    }

    /// 与 Codex CLI 的 `compute_store_key` 保持一致，避免猜测 Keychain account。
    static func keychainAccount(for home: URL) -> String {
        let canonical = home.standardizedFileURL.resolvingSymlinksInPath().path
        let digest = SHA256.hash(data: Data(canonical.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "cli|\(hex.prefix(16))"
    }

    private static func loadFromKeychain(home: URL) throws -> Credentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount(for: home),
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw AuthError.keychain(status)
        }
        return try decode(data)
    }

    private static func loadFromFile(home: URL) throws -> Credentials? {
        let url = home.appendingPathComponent("auth.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard (attributes[.size] as? NSNumber)?.intValue ?? 0 <= maximumPayloadSize else {
            throw AuthError.unavailable
        }
        return try decode(Data(contentsOf: url))
    }

    private static func decode(_ data: Data) throws -> Credentials {
        guard data.count <= maximumPayloadSize else { throw AuthError.unavailable }
        return try JSONDecoder().decode(Credentials.self, from: data)
    }

    private static func codexHome() -> URL {
        ProcessInfo.processInfo.environment["CODEX_HOME"]
            .map(URL.init(fileURLWithPath:))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    enum AuthError: Error {
        case unavailable
        case keychain(OSStatus)
    }
}
