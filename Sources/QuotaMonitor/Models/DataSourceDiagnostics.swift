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
    let installationProbe: DataSourceInstallationProbe
    let usesObservedDataAsInstallationEvidence: Bool

}

struct DataSourceCapabilityGroup: Identifiable, Sendable {
    let id: String
    let nameKey: String?
    let fallbackName: String
    let quotaSourceIDs: [DataSourceID]
    let routeDependentQuotaSourceIDs: [DataSourceID]
    let tokenSourceIDs: [DataSourceID]
}

enum DataSourceInstallationProbe: Equatable, Sendable {
    case paths([String])
    case codexRoute
    case deepSeekRoute
    case localTool(LocalToolTokenSource)

    func existingPaths(home: URL, environment: [String: String]) -> [URL] {
        switch self {
        case let .paths(paths):
            return paths.map { path in
                path.hasPrefix("/") ? URL(fileURLWithPath: path) : home.appendingPathComponent(path)
            }
        case let .localTool(source):
            return source.resolvedRoots(home: home, environment: environment)
        case .codexRoute, .deepSeekRoute:
            return []
        }
    }
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

struct TokenSourceRuntimeState: Equatable, Sendable {
    var state: DataSourceHealthState = .notDetected
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var candidateFileCount: Int?
    var validRecordCount = 0
    var usesLastGoodData = false

    mutating func begin(at date: Date) {
        lastAttemptAt = date
        state = .scanning
        usesLastGoodData = false
    }

    mutating func finish(
        with result: DataSourceHealthState,
        at date: Date,
        candidateFileCount: Int?,
        validRecordCount: Int,
        usesLastGoodData: Bool
    ) {
        if let candidateFileCount { self.candidateFileCount = candidateFileCount }
        if result == .ready {
            state = .ready
            lastSuccessAt = date
            self.validRecordCount = validRecordCount
            self.usesLastGoodData = false
        } else if lastSuccessAt != nil {
            state = .stale
            self.usesLastGoodData = true
        } else {
            state = result
            self.validRecordCount = validRecordCount
            self.usesLastGoodData = usesLastGoodData
            if candidateFileCount == nil { self.candidateFileCount = validRecordCount }
        }
    }

    mutating func restoreFromCache(at date: Date, validRecordCount: Int, isStale: Bool) {
        state = isStale ? .stale : .ready
        lastAttemptAt = date
        lastSuccessAt = date
        self.validRecordCount = validRecordCount
        usesLastGoodData = isStale
    }

    func snapshot(
        for descriptor: DataSourceDescriptor,
        at date: Date,
        isInstalled: Bool
    ) -> DataSourceHealthSnapshot {
        let expired = state == .ready
            && lastSuccessAt.map { date.timeIntervalSince($0) > descriptor.staleAfter } == true
        let effectiveState = expired ? DataSourceHealthState.stale : state
        return DataSourceHealthSnapshot(
            id: descriptor.id,
            nameKey: descriptor.nameKey,
            fallbackName: descriptor.fallbackName,
            kind: descriptor.kind,
            state: effectiveState,
            redactedPath: descriptor.redactedPath,
            lastAttemptAt: lastAttemptAt,
            lastSuccessAt: lastSuccessAt,
            candidateFileCount: candidateFileCount ?? validRecordCount,
            validRecordCount: validRecordCount,
            usesLastGoodData: usesLastGoodData || effectiveState == .stale,
            isInstalled: isInstalled,
            recoveryActions: descriptor.recoveryActions
        )
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
            descriptor(codexQuota, nameKey: "settings.sources.codex", fallbackName: "Codex quota", kind: .quota, path: "~/Library/Application Support/Codex", staleAfter: 3 * 60, installationProbe: .codexRoute),
            descriptor(codexToken, nameKey: "settings.sources.codexTokens", fallbackName: "Codex tokens", kind: .localToken, path: "~/.codex", staleAfter: 15 * 60, installationProbe: .paths([".codex"])),
            descriptor(deepSeekBalance, nameKey: "settings.sources.deepseek", fallbackName: "DeepSeek balance", kind: .balance, path: "~/Library/Application Support/DeepSeek", staleAfter: 3 * 60, installationProbe: .deepSeekRoute),
            descriptor(claudeCode, nameKey: "settings.sources.claude", fallbackName: "Claude Code tokens", kind: .localToken, path: "~/.claude", staleAfter: 15 * 60, installationProbe: .paths([".claude"])),
            descriptor(claudeDesktop, nameKey: "settings.sources.claudeDesktop", fallbackName: "Claude Desktop tokens", kind: .localToken, path: "~/.cc-switch", staleAfter: 15 * 60, installationProbe: .paths([".cc-switch"])),
            descriptor(workBuddy, nameKey: "settings.sources.workbuddy", fallbackName: "WorkBuddy tokens", kind: .localToken, path: "~/.workbuddy/traces", staleAfter: 15 * 60, installationProbe: .paths([".workbuddy/traces"])),
            descriptor(qoder, nameKey: "settings.sources.qoder", fallbackName: "Qoder tokens", kind: .localToken, path: "~/.qoder", staleAfter: 15 * 60, installationProbe: .paths([
                "Applications/Qoder.app", "/Applications/Qoder.app", ".local/bin/qoder",
                "/opt/homebrew/bin/qoder", "/usr/local/bin/qoder"
            ]), usesObservedDataAsInstallationEvidence: false)
        ] + LocalToolTokenSource.additional.map { source in
            descriptor(
                source.dataSourceID,
                nameKey: nil,
                fallbackName: source.platform.displayName,
                kind: .localToken,
                path: source.redactedRootDescription,
                staleAfter: 15 * 60,
                installationProbe: .localTool(source)
            )
        }
    }

    static var capabilityGroups: [DataSourceCapabilityGroup] {
        let builtIn = [
            DataSourceCapabilityGroup(
                id: "codex", nameKey: "settings.sources.codexProduct", fallbackName: "Codex",
                quotaSourceIDs: [codexQuota], routeDependentQuotaSourceIDs: [], tokenSourceIDs: [codexToken]
            ),
            DataSourceCapabilityGroup(
                id: "deepseek", nameKey: "settings.sources.deepseekProduct", fallbackName: "DeepSeek",
                quotaSourceIDs: [deepSeekBalance], routeDependentQuotaSourceIDs: [], tokenSourceIDs: []
            ),
            DataSourceCapabilityGroup(
                id: "claude", nameKey: "settings.sources.claudeProduct", fallbackName: "Claude",
                quotaSourceIDs: [], routeDependentQuotaSourceIDs: [deepSeekBalance],
                tokenSourceIDs: [claudeCode, claudeDesktop]
            ),
            DataSourceCapabilityGroup(
                id: "workbuddy", nameKey: "settings.sources.workbuddyProduct", fallbackName: "WorkBuddy",
                quotaSourceIDs: [], routeDependentQuotaSourceIDs: [], tokenSourceIDs: [workBuddy]
            ),
            DataSourceCapabilityGroup(
                id: "qoder", nameKey: "settings.sources.qoderProduct", fallbackName: "Qoder",
                quotaSourceIDs: [], routeDependentQuotaSourceIDs: [], tokenSourceIDs: [qoder]
            )
        ]
        let additionalByPlatform = Dictionary(grouping: LocalToolTokenSource.additional, by: \.platform)
        let additional = additionalByPlatform.keys.sorted { $0.rawValue < $1.rawValue }.compactMap { platform -> DataSourceCapabilityGroup? in
            guard let sources = additionalByPlatform[platform] else { return nil }
            return DataSourceCapabilityGroup(
                id: platform.rawValue, nameKey: nil, fallbackName: platform.displayName,
                quotaSourceIDs: [], routeDependentQuotaSourceIDs: [],
                tokenSourceIDs: sources.map(\.dataSourceID)
            )
        }
        return builtIn + additional
    }

    static func descriptor(
        _ id: DataSourceID,
        nameKey: String?,
        fallbackName: String,
        kind: DataSourceKind,
        path: String,
        staleAfter: TimeInterval,
        installationProbe: DataSourceInstallationProbe = .paths([]),
        usesObservedDataAsInstallationEvidence: Bool = true
    ) -> DataSourceDescriptor {
        DataSourceDescriptor(
            id: id,
            nameKey: nameKey,
            fallbackName: fallbackName,
            kind: kind,
            redactedPath: path,
            staleAfter: staleAfter,
            recoveryActions: [.retry, .openHelp],
            installationProbe: installationProbe,
            usesObservedDataAsInstallationEvidence: usesObservedDataAsInstallationEvidence
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
