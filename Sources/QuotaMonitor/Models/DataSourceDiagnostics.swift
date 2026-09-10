import Foundation

/// A stable identity for one source. The client and format are part of the
/// identity so Kimi CLI/Desktop (and similar pairs) never collapse into one row.
struct DataSourceID: Hashable, Codable, Identifiable, Sendable {
    let platform: String
    let client: String
    let format: String
    let definition: String

    init(platform: String, client: String, format: String, definition: String) {
        self.platform = platform
        self.client = client
        self.format = format
        self.definition = definition
    }

    var id: String {
        [platform, client, format, definition].joined(separator: ":")
    }
}

enum DataSourceKind: String, Codable, Sendable {
    case quota
    case balance
    case localToken
    case cloudToken
}

enum DataSourceHealthState: String, Codable, Sendable {
    case scanning
    case ready
    case notDetected
    case noData
    case needsPermission
    case unsupportedFormat
    case stale
    case failed
}

enum SourceRecoveryAction: String, Codable, Sendable {
    case retry
    case openSystemSettings
    case revealPath
    case openHelp
}

struct DataSourceDescriptor: Identifiable, Sendable {
    let id: DataSourceID
    let nameKey: String?
    let fallbackName: String
    let kind: DataSourceKind
    let redactedPath: String
    let staleAfter: TimeInterval
    let recoveryActions: [SourceRecoveryAction]

    var identifier: DataSourceID { id }
}

struct DataSourceHealthSnapshot: Equatable, Identifiable, Sendable {
    let id: DataSourceID
    let nameKey: String?
    let fallbackName: String
    let kind: DataSourceKind
    let state: DataSourceHealthState
    let redactedPath: String
    let lastAttemptAt: Date?
    let lastSuccessAt: Date?
    let candidateFileCount: Int
    let validRecordCount: Int
    let usesLastGoodData: Bool
    let isInstalled: Bool
    let recoveryActions: [SourceRecoveryAction]

    var isActionable: Bool {
        switch state {
        case .ready, .scanning, .notDetected:
            return false
        case .noData, .needsPermission, .unsupportedFormat, .stale, .failed:
            return true
        }
    }
}

struct DataSourceScanDiagnostic: Equatable, Sendable {
    let id: DataSourceID
    let state: DataSourceHealthState
    let candidateFileCount: Int
    let validRecordCount: Int
    let usesLastGoodData: Bool
}

struct AdditionalLocalTokenScanResult: Sendable {
    let snapshots: [TokenSourceSnapshot]
    let diagnostics: [DataSourceScanDiagnostic]
}

enum DataSourceCatalog {
    static let codexQuota = DataSourceID(
        platform: "codex",
        client: "api",
        format: "usage-json",
        definition: "quota"
    )
    static let codexToken = DataSourceID(
        platform: "codex",
        client: TokenClient.cli.rawValue,
        format: "jsonl",
        definition: "session-token"
    )
    static let deepSeekBalance = DataSourceID(
        platform: "deepseek",
        client: "api",
        format: "balance-json",
        definition: "balance"
    )
    static let claudeCode = DataSourceID(
        platform: TokenPlatform.claude.rawValue,
        client: TokenClient.cli.rawValue,
        format: "jsonl",
        definition: "session-token"
    )
    static let claudeDesktop = DataSourceID(
        platform: TokenPlatform.claude.rawValue,
        client: TokenClient.desktop.rawValue,
        format: "jsonl",
        definition: "cc-switch"
    )
    static let workBuddy = DataSourceID(
        platform: TokenPlatform.workbuddy.rawValue,
        client: TokenClient.desktop.rawValue,
        format: "jsonl",
        definition: "trace"
    )
    static let qoder = DataSourceID(
        platform: TokenPlatform.qoder.rawValue,
        client: TokenClient.cli.rawValue,
        format: "jsonl",
        definition: "session-token"
    )

    static var additional: [DataSourceID] {
        LocalToolTokenSource.additional.map(\.dataSourceID)
    }

    static var all: [DataSourceDescriptor] {
        [
            descriptor(codexQuota, nameKey: "settings.sources.codex", fallbackName: "Codex quota", kind: .quota, path: "~/Library/Application Support/Codex", staleAfter: 3 * 60),
            descriptor(codexToken, nameKey: "settings.sources.codexTokens", fallbackName: "Codex tokens", kind: .localToken, path: "~/.codex", staleAfter: 15 * 60),
            descriptor(deepSeekBalance, nameKey: "settings.sources.deepseek", fallbackName: "DeepSeek balance", kind: .balance, path: "~/Library/Application Support/DeepSeek", staleAfter: 3 * 60),
            descriptor(claudeCode, nameKey: "settings.sources.claude", fallbackName: "Claude Code tokens", kind: .localToken, path: "~/.claude", staleAfter: 15 * 60),
            descriptor(claudeDesktop, nameKey: "settings.sources.claudeDesktop", fallbackName: "Claude Desktop tokens", kind: .localToken, path: "~/.cc-switch", staleAfter: 15 * 60),
            descriptor(workBuddy, nameKey: "settings.sources.workbuddy", fallbackName: "WorkBuddy tokens", kind: .localToken, path: "~/.workbuddy/traces", staleAfter: 15 * 60),
            descriptor(qoder, nameKey: "settings.sources.qoder", fallbackName: "Qoder tokens", kind: .localToken, path: "~/.qoder", staleAfter: 15 * 60)
        ] + LocalToolTokenSource.additional.map { source in
            descriptor(
                source.dataSourceID,
                nameKey: nil,
                fallbackName: source.platform.displayName,
                kind: .localToken,
                path: source.redactedRootDescription,
                staleAfter: 15 * 60
            )
        }
    }

    static func descriptor(
        _ id: DataSourceID,
        nameKey: String?,
        fallbackName: String,
        kind: DataSourceKind,
        path: String,
        staleAfter: TimeInterval
    ) -> DataSourceDescriptor {
        DataSourceDescriptor(
            id: id,
            nameKey: nameKey,
            fallbackName: fallbackName,
            kind: kind,
            redactedPath: path,
            staleAfter: staleAfter,
            recoveryActions: [.retry, .openHelp]
        )
    }
}

extension LocalToolTokenSource {
    var dataSourceID: DataSourceID {
        DataSourceID(
            platform: platform.rawValue,
            client: client.rawValue,
            format: format.rawValue,
            definition: roots.joined(separator: "|")
        )
    }

    var redactedRootDescription: String {
        roots.map { root in
            root.hasPrefix("/") ? root : "~/\(root)"
        }.joined(separator: " · ")
    }
}
