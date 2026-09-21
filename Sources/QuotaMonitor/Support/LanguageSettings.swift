import Foundation
import Observation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    static var systemDefault: AppLanguage {
        Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true ? .simplifiedChinese : .english
    }
}

@MainActor @Observable
final class LanguageSettings {
    static let storageKey = "QuotaMonitor.appLanguage"
    private static let legacyStorageKeys = ["CodexQuota.appLanguage", "QuotaDot.appLanguage"]

    @ObservationIgnored private let defaults: UserDefaults

    var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Self.storageKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = ([Self.storageKey] + Self.legacyStorageKeys)
            .compactMap { defaults.string(forKey: $0) }
            .first
            .flatMap(AppLanguage.init(rawValue:)) ?? .systemDefault
    }

    func toggle() {
        language = language == .simplifiedChinese ? .english : .simplifiedChinese
    }

    func text(_ key: String, _ arguments: CVarArg...) -> String {
        text(key, arguments: arguments)
    }

    func text(_ key: String, arguments: [CVarArg]) -> String {
        let localized = localizedBundle.localizedString(forKey: key, value: key, table: nil)
        guard !arguments.isEmpty else { return localized }
        return String(format: localized, locale: language.locale, arguments: arguments)
    }

    private var localizedBundle: Bundle {
        let resources = QuotaResourceBundle.current
        let localizationName = resources.localizations.first {
            $0.caseInsensitiveCompare(language.rawValue) == .orderedSame
        } ?? language.rawValue
        guard let path = resources.path(forResource: localizationName, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return QuotaResourceBundle.current }
        return bundle
    }
}

enum QuotaResourceBundle {
    static var current: Bundle {
        let packagedBundle = Bundle.main.resourceURL
            .map { $0.appendingPathComponent("QuotaMonitor_QuotaMonitor.bundle", isDirectory: true) }
            .flatMap(Bundle.init(url:))
        return packagedBundle ?? Bundle.module
    }
}
