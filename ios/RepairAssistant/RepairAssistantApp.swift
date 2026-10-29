import SwiftUI

@main
struct RepairAssistantApp: App {
    @State private var flow = FlowModel()

    init() {
        // English-only app: SwiftUI string literals resolve against the bundle's preferred language, not `tr`,
        // so a German iPhone would otherwise get German catalog values. Tests keep the German keys.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            UserDefaults.standard.set(["en"], forKey: "AppleLanguages")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(flow)
                .environment(\.locale, Lang.shared.locale)
                .preferredColorScheme(Self.forcedScheme)
        }
    }

    private static var forcedScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "forceScheme") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}
