import SwiftUI

struct AnalysisView: View {
    @Environment(FlowModel.self) private var flow

    private let stages: [(AnalysisStage, String, String)] = [
        (.classify, "Objekt und Sicherheit prüfen", "Muse Spark"),
        (.segment, "Schaden markieren", "SAM 3.1"),
        (.diagnose, "Diagnose stellen", "Muse Spark"),
        (.plan, "Reparatur planen", "Muse Spark"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let photo = flow.photo {
                    PhotoStage(image: photo, dim: flow.analysisError == nil ? 0.18 : 0.4) { size in
                        ScanRevealView(segments: flow.earlySegments, size: size, isScanning: flow.isAnalyzing && flow.analysisError == nil)
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(flow.analysisError == nil ? "Ich schaue mir das genau an" : "Das hat nicht geklappt")
                        .font(.title2.bold()).foregroundStyle(Theme.ink)
                    Text(flow.analysisError == nil ? "Das dauert meist unter 30 Sekunden." : "Dein Foto bleibt erhalten.")
                        .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                }
                if let err = flow.analysisError {
                    ErrorCard(message: err, retry: { flow.startAnalysis(resetExtras: false) },
                              secondaryTitle: "Abbrechen", secondary: { flow.cancelAnalysis() })
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(stages.enumerated()), id: \.offset) { i, s in
                            if s.0 == .segment && flow.groundingSeen {
                                StageRow(title: "Muse Spark lokalisiert → SAM segmentiert", subtitle: "Zweiter Versuch mit Spark-Box", state: state(for: .segment))
                                Divider().overlay(Theme.hairline).padding(.leading, 46)
                            }
                            StageRow(title: s.1, subtitle: s.2, state: state(for: s.0))
                            if i < stages.count - 1 { Divider().overlay(Theme.hairline).padding(.leading, 46) }
                        }
                    }
                    .card(padding: 14)
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

    private func state(for stage: AnalysisStage) -> StageState {
        if let s = flow.stageStates[stage] { return s }
        if stage == .classify && flow.isAnalyzing && flow.stageStates.isEmpty { return .active }
        return .pending
    }
}
