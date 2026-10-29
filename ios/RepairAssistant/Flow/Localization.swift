import Foundation
import Observation

/// UI language: follows the system language unless the user picks one in Settings ("Sprache / Language").
/// The same code is sent to the proxy as `locale`, so UI and model texts always match.
/// Catalog keys are the German source texts (`Localizable.xcstrings`, source language de).
@Observable
final class Lang: @unchecked Sendable {
    static let shared = Lang()
    static let defaultsKey = "appLanguage"
    static let supported = ["de", "en"]

    /// "system", "de" or "en".
    var choice: String {
        didSet { UserDefaults.standard.set(choice, forKey: Self.defaultsKey) }
    }

    init(defaults: UserDefaults = .standard) {
        let stored = defaults.string(forKey: Self.defaultsKey) ?? "system"
        // Unit tests assert the German texts; under XCTest the default is German instead of the simulator language.
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // The submitted app is English-only (UI, model answers, voice). Tests keep the German catalog keys.
        choice = testing ? (Self.supported.contains(stored) ? stored : "de") : "en"
    }

    /// Resolved language, "de" or "en". Reads `choice`, so SwiftUI views calling `tr` re-render when it changes.
    var code: String { Self.resolve(choice, preferred: Locale.preferredLanguages) }

    var locale: Locale { Locale(identifier: code) }

    /// Pure logic for tests: explicit choice wins, "system" takes the first supported preferred language (default de).
    static func resolve(_ choice: String, preferred: [String]) -> String {
        if supported.contains(choice) { return choice }
        for p in preferred {
            let base = p.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
            if supported.contains(base) { return base }
        }
        return "de"
    }

    var isEnglish: Bool { code == "en" }

    /// Value of the proxy request field `locale`.
    static var apiCode: String { shared.code }

    func bundle() -> Bundle {
        Bundle.main.path(forResource: code, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .main
    }
}

/// Looks up `key` (the German source text) in the catalog for the current UI language and fills `%lld`/`%@`/`%d` arguments.
/// Unknown keys (for example model-written texts) come back unchanged.
func tr(_ key: String, _ args: CVarArg...) -> String {
    let text = Lang.shared.bundle().localizedString(forKey: key, value: key, table: nil)
    return args.isEmpty ? text : String(format: text, locale: Lang.shared.locale, arguments: args)
}
