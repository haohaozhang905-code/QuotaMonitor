import Foundation

struct CodexDirectSnapshot: Sendable {
    let provider: ProviderUsage
    let resetCredits: CodexResetCredits?
}

struct CodexDirectClient: Sendable {
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let resetCreditsURL = URL(string: "https://chatgpt.com/backend-api/wham/rate-limit-reset-credits")!
    private let maximumPayloadSize = 1_048_576
    private let appServerTimeout: TimeInterval = 8

    func fetch() async throws -> CodexDirectSnapshot {
        do {
            return try await fetchDirect()
        } catch {
            // New Codex releases may keep credentials in the encrypted
            // `~/.codex/secrets/codex_auth.age` store. The official app-server
            // owns decryption and token refresh, so use it as the fallback
            // instead of trying to reimplement Codex's secret storage here.
            return try await fetchFromAppServer(fallbackError: error)
        }
    }

    private func fetchDirect() async throws -> CodexDirectSnapshot {
        let auth = try loadAuth()
        async let usageRequest = request(usageURL, auth: auth)
        async let creditsRequest = try? request(resetCreditsURL, auth: auth)

        let usageData = try await usageRequest
        let creditsData = await creditsRequest
        let usage = try JSONDecoder().decode(UsageEnvelope.self, from: usageData)
        let now = Date.now

        let windows = [usage.rateLimit?.primaryWindow, usage.rateLimit?.secondaryWindow]
            .compactMap { $0 }
            .compactMap { usageLine(from: $0, now: now) }
        guard !windows.isEmpty else { throw DirectError.malformedUsage }

        let uniqueLines = windows.reduce(into: [String: UsageLine]()) { result, line in
            result[line.label] = line
        }.values.sorted { $0.label < $1.label }

        let provider = ProviderUsage(
            providerId: "codex",
            displayName: "Codex",
            plan: usage.planType?.uppercased(),
            lines: uniqueLines,
            fetchedAt: now
        )

        let endpointCredits = creditsData.flatMap { try? JSONDecoder().decode(CreditEnvelope.self, from: $0) }
        let creditPayload = endpointCredits ?? usage.rateLimitResetCredits
        let resetCredits = creditPayload.flatMap { payload -> CodexResetCredits? in
            guard let count = payload.availableCount else { return nil }
            let expirations = payload.credits
                .filter { $0.redeemedAt == nil }
                .compactMap { parseISO8601($0.expiresAt) }
                .filter { $0 > now }
                .sorted()
            return CodexResetCredits(availableCount: count, expirations: expirations, fetchedAt: now)
        }

        return CodexDirectSnapshot(provider: provider, resetCredits: resetCredits)
    }

    private func fetchFromAppServer(fallbackError: Error) async throws -> CodexDirectSnapshot {
        guard let executable = codexExecutable() else { throw fallbackError }

        let result: AppServerRateLimits = try await Task.detached(priority: .utility) {
            try Self.runAppServerRateLimits(executable: executable, timeout: self.appServerTimeout)
        }.value

        let now = Date.now
        let windows = [result.rateLimits.primary, result.rateLimits.secondary]
            .compactMap { $0 }
            .compactMap { appServerUsageLine(from: $0, now: now) }
        guard !windows.isEmpty else { throw DirectError.malformedUsage }

        let uniqueLines = windows.reduce(into: [String: UsageLine]()) { values, line in
            values[line.label] = line
        }.values.sorted { $0.label < $1.label }
        let provider = ProviderUsage(
            providerId: "codex",
            displayName: "Codex",
            plan: result.planType?.uppercased(),
            lines: uniqueLines,
            fetchedAt: now
        )

        let resetCredits = result.rateLimitResetCredits.flatMap { payload -> CodexResetCredits? in
            guard let count = payload.availableCount else { return nil }
            let expirations = payload.credits
                .filter { $0.redeemedAt == nil && $0.status?.lowercased() == "available" }
                .compactMap { parseISO8601($0.expiresAt) }
                .filter { $0 > now }
                .sorted()
            return CodexResetCredits(availableCount: count, expirations: expirations, fetchedAt: now)
        }
        return CodexDirectSnapshot(provider: provider, resetCredits: resetCredits)
    }

    private static func runAppServerRateLimits(executable: String, timeout: TimeInterval) throws -> AppServerRateLimits {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = Pipe()

        let collector = AppServerCollector()

        defer {
            output.fileHandleForReading.readabilityHandler = nil
            input.fileHandleForWriting.closeFile()
            if process.isRunning { process.terminate() }
            process.waitUntilExit()
        }

        output.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                collector.signal()
                return
            }
            collector.append(chunk)
        }

        do {
            try process.run()
            let requests = [
                #"{"method":"initialize","id":1,"params":{"clientInfo":{"name":"quota_monitor","title":"QuotaMonitor","version":"0.1.0"}}}"#,
                #"{"method":"initialized","params":{}}"#,
                #"{"method":"account/rateLimits/read","id":2,"params":{}}"#,
            ].joined(separator: "\n") + "\n"
            try input.fileHandleForWriting.write(contentsOf: Data(requests.utf8))
            if collector.wait(timeout: timeout) == .timedOut {
                throw DirectError.appServerTimeout
            }
            let finalResponse = collector.response
            let finalError = collector.error
            if let finalResponse { return finalResponse }
            if let finalError { throw finalError }
            throw DirectError.appServerAuthUnavailable
        } catch let error as DirectError {
            throw error
        } catch {
            throw DirectError.appServerUnavailable
        }
    }

    private func codexExecutable() -> String? {
        let environment = ProcessInfo.processInfo.environment
        var candidates: [String] = []
        if let configured = environment["CODEX_BIN"], !configured.isEmpty { candidates.append(configured) }
        if let home = environment["HOME"] {
            candidates.append("\(home)/.npm-global/bin/codex")
            candidates.append("\(home)/.local/bin/codex")
        }
        candidates += [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func usageLine(from window: DirectWindow, now: Date) -> UsageLine? {
        guard let usedPercent = window.usedPercent else { return nil }
        let duration = window.limitWindowSeconds
        let resetAt = window.resetAt.map(Date.init(timeIntervalSince1970:))
        let isShortWindow: Bool
        if let duration {
            isShortWindow = duration <= 12 * 60 * 60
        } else if let resetAt {
            isShortWindow = resetAt.timeIntervalSince(now) <= 12 * 60 * 60
        } else {
            return nil
        }

        return UsageLine(
            type: "progress",
            label: isShortWindow ? "Session" : "Weekly",
            used: min(max(usedPercent, 0), 100),
            limit: 100,
            resetsAt: resetAt,
            periodDurationMs: duration.map { $0 * 1_000 },
            value: nil,
            subtitle: nil
        )
    }

    private func loadAuth() throws -> DirectAuth {
        let credentials = try CodexAuthStore.load()
        guard let accessToken = credentials.resolvedAccessToken else {
            throw DirectError.authUnavailable
        }
        let accountId = credentials.resolvedAccountId ?? accountId(from: accessToken)
        return DirectAuth(accessToken: accessToken, accountId: accountId)
    }

    private func request(_ url: URL, auth: DirectAuth) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Codex Desktop", forHTTPHeaderField: "originator")
        request.setValue("CODEX", forHTTPHeaderField: "OAI-Product-Sku")
        if let accountId = auth.accountId {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let (data, response) = try await URLSession(configuration: configuration).data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw DirectError.requestFailed
        }
        guard data.count <= maximumPayloadSize else { throw DirectError.payloadTooLarge }
        return data
    }

    private func accountId(from token: String) -> String? {
        let segments = token.split(separator: ".")
        guard segments.count > 1 else { return nil }
        var payload = String(segments[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["https://api.openai.com/auth.chatgpt_account_id"] as? String
            ?? json["chatgpt_account_id"] as? String
    }

    private func parseISO8601(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func appServerUsageLine(from window: AppServerWindow, now: Date) -> UsageLine? {
        let duration = window.windowDurationMins.map { $0 * 60 }
        let resetAt = window.resetsAt.map(Date.init(timeIntervalSince1970:))
        guard let usedPercent = window.usedPercent,
              duration != nil || resetAt != nil else { return nil }
        let isShortWindow = duration.map { $0 <= 12 * 60 * 60 }
            ?? resetAt.map { $0.timeIntervalSince(now) <= 12 * 60 * 60 }
            ?? false
        return UsageLine(
            type: "progress",
            label: isShortWindow ? "Session" : "Weekly",
            used: min(max(usedPercent, 0), 100),
            limit: 100,
            resetsAt: resetAt,
            periodDurationMs: duration.map { $0 * 1_000 },
            value: nil,
            subtitle: nil
        )
    }
}

private extension CodexDirectClient {
    final class AppServerCollector: @unchecked Sendable {
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)
        private var buffer = Data()
        private var storedResponse: AppServerRateLimits?
        private var storedError: DirectError?

        var response: AppServerRateLimits? {
            lock.lock(); defer { lock.unlock() }
            return storedResponse
        }

        var error: DirectError? {
            lock.lock(); defer { lock.unlock() }
            return storedError
        }

        func append(_ chunk: Data) {
            lock.lock()
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                guard let object = try? JSONDecoder().decode(AppServerMessage.self, from: line), object.id == 2 else {
                    continue
                }
                if let result = object.result {
                    storedResponse = result
                } else if object.error != nil {
                    storedError = .appServerAuthUnavailable
                }
            }
            let finished = storedResponse != nil || storedError != nil
            lock.unlock()
            if finished { semaphore.signal() }
        }

        func signal() { semaphore.signal() }

        @discardableResult
        func wait(timeout: TimeInterval) -> DispatchTimeoutResult {
            semaphore.wait(timeout: .now() + timeout)
        }
    }

    enum DirectError: Error {
        case authUnavailable
        case requestFailed
        case payloadTooLarge
        case malformedUsage
        case appServerAuthUnavailable
        case appServerUnavailable
        case appServerTimeout
    }

    struct DirectAuth: Sendable {
        let accessToken: String
        let accountId: String?
    }

    struct UsageEnvelope: Decodable {
        let planType: String?
        let rateLimit: RateLimit?
        let rateLimitResetCredits: CreditEnvelope?

        enum CodingKeys: String, CodingKey {
            case planType = "plan_type"
            case rateLimit = "rate_limit"
            case rateLimitResetCredits = "rate_limit_reset_credits"
        }
    }

    struct RateLimit: Decodable {
        let primaryWindow: DirectWindow?
        let secondaryWindow: DirectWindow?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }
    }

    struct DirectWindow: Decodable {
        let usedPercent: Double?
        let resetAt: Double?
        let limitWindowSeconds: Double?

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }

    struct CreditEnvelope: Decodable {
        let availableCount: Int?
        let credits: [Credit]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            availableCount = try (container.decodeIfPresent(Int.self, forKey: .availableCount)
                ?? container.decodeIfPresent(Int.self, forKey: .availableCountCamel))
            credits = try container.decodeIfPresent([Credit].self, forKey: .credits) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case availableCount = "available_count"
            case availableCountCamel = "availableCount"
            case credits
        }
    }

    struct Credit: Decodable {
        let expiresAt: String?
        let redeemedAt: String?
        let status: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            expiresAt = try (container.decodeIfPresent(String.self, forKey: .expiresAt)
                ?? container.decodeIfPresent(String.self, forKey: .expiresAtCamel))
            redeemedAt = try (container.decodeIfPresent(String.self, forKey: .redeemedAt)
                ?? container.decodeIfPresent(String.self, forKey: .redeemedAtCamel))
            status = try container.decodeIfPresent(String.self, forKey: .status)
        }

        enum CodingKeys: String, CodingKey {
            case expiresAt = "expires_at"
            case expiresAtCamel = "expiresAt"
            case redeemedAt = "redeemed_at"
            case redeemedAtCamel = "redeemedAt"
            case status
        }
    }

    struct AppServerMessage: Decodable {
        let id: Int?
        let result: AppServerRateLimits?
        let error: AppServerErrorPayload?
    }

    struct AppServerErrorPayload: Decodable {
        let code: Int?
        let message: String?
    }

    struct AppServerRateLimits: Decodable {
        let planType: String?
        let rateLimits: AppRateLimits
        let rateLimitResetCredits: CreditEnvelope?

        enum CodingKeys: String, CodingKey {
            case planType
            case rateLimits
            case rateLimitResetCredits
        }
    }

    struct AppRateLimits: Decodable {
        let primary: AppServerWindow?
        let secondary: AppServerWindow?
    }

    struct AppServerWindow: Decodable {
        let usedPercent: Double?
        let windowDurationMins: Double?
        let resetsAt: Double?
    }
}
