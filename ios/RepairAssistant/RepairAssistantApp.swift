import SwiftUI

@main
struct RepairAssistantApp: App {
    @State private var flow = FlowModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(flow)
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
