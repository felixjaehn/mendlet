import SwiftUI

struct RootView: View {
    @Environment(FlowModel.self) private var flow

    var body: some View {
        @Bindable var flow = flow
        NavigationStack(path: $flow.path) {
            HomeView()
                .navigationDestination(for: FlowModel.Route.self) { route in
                    switch route {
                    case .analysis: AnalysisView()
                    case .diagnosis: DiagnosisView()
                    case .decision: DecisionView()
                    case .shopping: ShoppingListView()
                    case .guide: GuideView()
                    case .block: BlockView()
                    case .completion: CompletionView()
                    }
                }
        }
        .tint(Theme.thread)
        .sheet(isPresented: $flow.showSettings) { SettingsSheet() }
        .task { await DemoBootstrap.run(flow) }
    }
}
