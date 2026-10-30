import SwiftUI

struct RootView: View {
    @Environment(FlowModel.self) private var flow
    @Namespace private var heroNS

    var body: some View {
        @Bindable var flow = flow
        NavigationStack(path: $flow.path) {
            HomeView()
                .navigationDestination(for: FlowModel.Route.self) { route in
                    switch route {
                    case .analysis: AnalysisView().heroDestination()
                    case .diagnosis: DiagnosisView().heroDestination()
                    case .decision: DecisionView().heroDestination()
                    case .shopping: ShoppingListView()
                    case .guide: GuideView()
                    case .block: BlockView()
                    case .completion: CompletionView()
                    case .project(let id): ProjectView(caseId: id)
                    case .impact: ImpactView()
                    }
                }
        }
        .environment(\.heroNamespace, heroNS)
        .tint(Theme.thread)
        .sheet(isPresented: $flow.showSettings) { SettingsSheet() }
        .task { await DemoBootstrap.run(flow) }
    }
}
