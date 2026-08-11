import Foundation
import SQLite3

/// Claude（Code）当前走哪条模型路由。
enum ClaudeRoute: Sendable, Equatable {
    /// Anthropic 官方（settings 里没有指向 DeepSeek 的模型/网关）。
    case official
    /// 通过 cc-switch 切到 DeepSeek（model 含 deepseek，或 ANTHROPIC_BASE_URL 指向 api.deepseek.com）。
    case deepseek
    /// 识别不出来（未装 Claude Code / 没有本地配置）。
    case unknown
}

/// 读取本地 Claude 配置判断当前路由。
///
/// 判定依据与 Claude Code 实际生效的文件一致：`~/.claude/settings.json` 与
/// `settings.local.json`。cc-switch 切换 Claude 模型时会写入 model 或
/// ANTHROPIC_BASE_URL，因此不依赖 cc-switch 自身是否在运行。
enum ClaudeRouteDetector {
    static func detect() -> ClaudeRoute {
        // cc-switch 是实际路由的“开关”：桌面版与 CLI 的活动 provider 才是用户看到的当前状态。
        let ccSwitchRoute = detectFromCCSwitchDB()
        if ccSwitchRoute != .unknown { return ccSwitchRoute }
        // cc-switch 未安装/未配置时，回退到 Claude Code 本地 settings。
        return detectFromClaudeSettings()
    }

    /// 从 cc-switch 数据库读活动 provider（claude / claude-desktop 两个通道）。
    /// cc-switch 的菜单栏显示“Claude → DeepSeek”时，数据库里就是 is_current=1 的 DeepSeek。
    static func detectFromCCSwitchDB() -> ClaudeRoute {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbURL = home.appendingPathComponent(".cc-switch/cc-switch.db")
        return detectFromCCSwitchDB(at: dbURL)
    }

    static func detectFromCCSwitchDB(at dbURL: URL) -> ClaudeRoute {
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return .unknown }

        var db: OpaquePointer?
        guard sqlite3_open(dbURL.path, &db) == SQLITE_OK, let db else { return .unknown }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT name, category, settings_config
        FROM providers
        WHERE is_current = 1 AND app_type IN ('claude', 'claude-desktop')
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return .unknown
        }
        defer { sqlite3_finalize(statement) }

        var sawProvider = false
        var anyOfficial = false
        while sqlite3_step(statement) == SQLITE_ROW {
            sawProvider = true
            let name = columnString(statement, 0) ?? ""
            let category = columnString(statement, 1) ?? ""
            let configText = columnString(statement, 2) ?? ""

            if isDeepSeekProvider(name: name, category: category, configText: configText) {
                return .deepseek
            }
            if category.lowercased() == "official" {
                anyOfficial = true
            }
        }
        // 没有 DeepSeek 路由时：全部为官方则视为官方，否则（第三方网关等）无法识别。
        return sawProvider && anyOfficial ? .official : .unknown
    }

    private static func columnString(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: text)
    }

    private static func isDeepSeekProvider(name: String, category: String, configText: String) -> Bool {
        let combined = "\(name) \(category) \(configText)".lowercased()
        if combined.contains("api.deepseek.com") { return true }
        if combined.contains("deepseek") { return true }
        return false
    }

    /// 从 Claude Code 本地 settings 推断（cc-switch 未接管时的兜底）。
    private static func detectFromClaudeSettings() -> ClaudeRoute {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURLs = [
            home.appendingPathComponent(".claude/settings.json"),
            home.appendingPathComponent(".claude/settings.local.json"),
        ]
        for url in settingsURLs {
            guard let data = try? Data(contentsOf: url),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            let route = detect(settings: object)
            if route != .unknown { return route }
        }
        return .unknown
    }

    static func detect(settings: [String: Any]) -> ClaudeRoute {
        if let model = settings["model"] as? String,
           model.lowercased().contains("deepseek") {
            return .deepseek
        }
        if let env = settings["env"] as? [String: Any],
           let baseURL = env["ANTHROPIC_BASE_URL"] as? String,
           baseURL.lowercased().contains("deepseek") {
            return .deepseek
        }
        if settings["model"] as? String != nil {
            return .official
        }
        return .unknown
    }

    /// 返回当前 Claude DeepSeek provider 的 API key。Claude 单独走 DeepSeek
    /// 时，余额接口必须从这里取凭证，不能再假设 Codex 也切到了 DeepSeek。
    static func currentDeepSeekAPIKey() -> String? {
        if let key = apiKeyFromCCSwitchDB(), !key.isEmpty { return key }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let settingsURLs = [
            home.appendingPathComponent(".claude/settings.json"),
            home.appendingPathComponent(".claude/settings.local.json"),
        ]
        for url in settingsURLs {
            guard let data = try? Data(contentsOf: url),
                  let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  detect(settings: settings) == .deepseek,
                  let key = deepSeekAPIKey(settings: settings), !key.isEmpty else {
                continue
            }
            return key
        }
        return nil
    }

    private static func apiKeyFromCCSwitchDB() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dbURL = home.appendingPathComponent(".cc-switch/cc-switch.db")
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT name, category, settings_config
        FROM providers
        WHERE is_current = 1 AND app_type IN ('claude', 'claude-desktop')
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW {
            let name = columnString(statement, 0) ?? ""
            let category = columnString(statement, 1) ?? ""
            let configText = columnString(statement, 2) ?? ""
            guard isDeepSeekProvider(name: name, category: category, configText: configText),
                  let data = configText.data(using: .utf8),
                  let config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let key = deepSeekAPIKey(settings: config), !key.isEmpty else {
                continue
            }
            return key
        }
        return nil
    }

    /// cc-switch 的 provider 设置会随版本变化；只从明确的 token/key 字段取值，
    /// 不扫描任意字符串，避免把 base URL 或其他配置误作为凭证。
    static func deepSeekAPIKey(settings: [String: Any]) -> String? {
        apiKey(in: settings)
    }

    private static func apiKey(in object: [String: Any]) -> String? {
        let candidates = [
            "ANTHROPIC_AUTH_TOKEN",
            "DEEPSEEK_API_KEY",
            "OPENAI_API_KEY",
            "api_key",
            "apiKey",
            "auth_token",
            "authToken",
        ]
        for key in candidates {
            if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        for value in object.values {
            if let nested = value as? [String: Any], let key = apiKey(in: nested) { return key }
        }
        return nil
    }
}
