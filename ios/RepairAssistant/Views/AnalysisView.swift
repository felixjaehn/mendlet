import SwiftUI

struct AnalysisView: View {
    @Environment(FlowModel.self) private var flow

    private let stages: [(AnalysisStage, String, String)] = [
        (.classify, "Objekt und Sicherheit prüfen", "Muse Spark"),
        (.segment, "Schaden markieren", "SAM 3.1"),
        (.diagnose, "Diagnose stellen", "Muse Spark"),
        (.plan, "Reparatur planen", "Muse Wonder"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let photo = flow.photo {
                    PhotoStage(image: photo, dim: flow.analysisError == nil ? 0.18 : 0.4, minAspect: 1.15) { size in
                        ScanRevealView(segments: flow.earlySegments, size: size, isScanning: flow.isAnalyzing && flow.analysisError == nil)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(flow.analysisError == nil ? tr("Ich schaue mir das genau an") : tr("Das hat nicht geklappt"))
                        .font(.title3.bold()).foregroundStyle(Theme.ink)
                    if flow.analysisError != nil {
                        Text("Dein Foto bleibt erhalten.").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                    }
                }
                if let err = flow.analysisError {
                    ErrorCard(message: err, retry: { flow.startAnalysis(resetExtras: false) },
                              secondaryTitle: "Abbrechen", secondary: { flow.cancelAnalysis() })
                } else {
                    StageStrip(titles: stages.map { $0.0 == .segment && flow.groundingSeen ? "Muse Spark lokalisiert, SAM segmentiert" : $0.1 },
                               states: stages.map { state(for: $0.0) })
                    AgentTraceView(steps: flow.agentSteps, active: activeWork, replay: flow.settings.demoMode)
                }
            }
            .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { flow.cancelAnalysis() } label: { Image(systemName: "xmark") }
                    .accessibilityLabel("Abbrechen")
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sensoryFeedback(.success, trigger: flow.isAnalyzing) { old, new in old && !new && flow.analysisError == nil }
    }

    /// Work in progress: the first stage that is not done yet.
    private var activeWork: (label: String, model: String)? {
        guard flow.isAnalyzing else { return nil }
        guard let s = stages.first(where: { state(for: $0.0) == .active }) ?? stages.first(where: { state(for: $0.0) != .done }) else { return nil }
        if s.0 == .segment && flow.groundingSeen { return ("Muse Spark lokalisiert, SAM 3.1 segmentiert", "SAM 3.1") }
        return (s.1, s.2)
    }

    private func state(for stage: AnalysisStage) -> StageState {
        if let s = flow.stageStates[stage] { return s }
        if stage == .classify && flow.isAnalyzing && flow.stageStates.isEmpty { return .active }
        return .pending
    }
}
