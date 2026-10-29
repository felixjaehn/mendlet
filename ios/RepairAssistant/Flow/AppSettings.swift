import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var demoMode: Bool { didSet { defaults.set(demoMode, forKey: "demoMode") } }
    var scenarioRaw: String { didSet { defaults.set(scenarioRaw, forKey: "demoScenarioSetting") } }
    var fastReplay: Bool { didSet { defaults.set(fastReplay, forKey: "fastReplay") } }
    var recoveryTrace: Bool { didSet { defaults.set(recoveryTrace, forKey: "recoveryTrace") } }
    var baseURLString: String { didSet { defaults.set(baseURLString, forKey: "proxyBaseURL") } }

    static var configuredBaseURL: String {
        (Bundle.main.object(forInfoDictionaryKey: "PROXY_BASE_URL") as? String).flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : $0 } ?? "http://localhost:8787"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        demoMode = (defaults.object(forKey: "demoMode") as? Bool) ?? true
        scenarioRaw = defaults.string(forKey: "demoScenarioSetting") ?? DemoScenario.textileTear.rawValue
        fastReplay = defaults.bool(forKey: "fastReplay")
        recoveryTrace = defaults.bool(forKey: "recoveryTrace")
        baseURLString = defaults.string(forKey: "proxyBaseURL") ?? Self.configuredBaseURL
    }

    var scenario: DemoScenario {
        get { DemoScenario(rawValue: scenarioRaw) ?? .textileTear }
        set { scenarioRaw = newValue.rawValue }
    }

    var baseURL: URL? { URL(string: baseURLString.trimmingCharacters(in: .whitespaces)) }

    func makeService() -> AnalysisService {
        if demoMode { return MockAPIClient(fast: fastReplay, recovery: recoveryTrace) }
        if let url = baseURL { return LiveAPIClient(baseURL: url) }
        return MockAPIClient()
    }
}
