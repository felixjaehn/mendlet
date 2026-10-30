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
        Self.styleNavigationBar()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(flow)
                .environment(\.locale, Lang.shared.locale)
                .preferredColorScheme(Self.forcedScheme)
        }
    }

    /// Large titles in SF Pro, the only typeface of the app.
    private static func styleNavigationBar() {
        func sf(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont { .systemFont(ofSize: size, weight: weight) }
        let a = UINavigationBarAppearance()
        a.configureWithTransparentBackground()
        a.largeTitleTextAttributes = [.font: sf(34, .bold)]
        a.titleTextAttributes = [.font: sf(17, .semibold)]
        UINavigationBar.appearance().standardAppearance = a
        UINavigationBar.appearance().scrollEdgeAppearance = a
    }

    private static var forcedScheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "forceScheme") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }
}
