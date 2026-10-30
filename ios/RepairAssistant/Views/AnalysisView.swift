import SwiftUI

/// The mark reveal: the user's own photo dims, a light band sweeps over it, the damage outline draws itself.
/// A quiet sheet below says what happens (4 phases, no percentages). Tapping the status line opens the hidden agent trace.
struct AnalysisView: View {
    @Environment(FlowModel.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTrace = false

    private let phases = ["Looking at your photo", "Finding the damage", "Outlining it", "Writing your plan"]

    var body: some View {
        GeometryReader { geo in
            let photoHeight = geo.size.height * 0.62 + geo.safeAreaInsets.top * 0.2
            ZStack(alignment: .top) {
                Theme.surface.ignoresSafeArea()
                VStack(spacing: 0) {
                    ZStack(alignment: .topLeading) {
                        photoView
                        CircleIconButton(systemImage: "xmark", label: "Cancel", onPhoto: true) { flow.cancelAnalysis() }
                            .padding(.leading, Theme.margin).padding(.top, geo.safeAreaInsets.top + 8)
                    }
                    .frame(height: photoHeight + (showTrace ? -photoHeight * 0.35 : 0))
                    .clipped()
                    sheet(bottomInset: geo.safeAreaInsets.bottom)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .ignoresSafeArea(edges: [.top, .bottom])
        }
        .navigationBarBackButtonHidden()
        .navigationBarHidden(true)
        .animation(Theme.spring, value: showTrace)
        .sensoryFeedback(.success, trigger: flow.isAnalyzing) { old, new in old && !new && flow.analysisError == nil }
        .onAppear { if flow.settings.recoveryTrace { showTrace = true } }
    }

    // MARK: Photo

    @ViewBuilder private var photoView: some View {
        if let photo = flow.photo {
            let failed = flow.analysisError != nil
            MarkedPhoto(image: photo, segments: flow.earlySegments,
                        mode: failed ? .thumb : .analysis(arrival: flow.marksArrivedAt),
                        focus: DamageFocus.region(for: flow.earlySegments), zoomable: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Color.black
        }
    }

    // MARK: Sheet

    private func sheet(bottomInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            Capsule().fill(Theme.inkTertiary.opacity(0.5)).frame(width: 36, height: 5).padding(.top, 8).padding(.bottom, 18)
                .accessibilityHidden(true)
            if let err = flow.analysisError {
                errorBlock(err)
            } else {
                VStack(spacing: 14) {
                    Button { showTrace.toggle() } label: {
                        Group {
                            if showTrace {
                                Text(tr(phases[phaseIndex]))
                                    .font(.title3.weight(.semibold)).foregroundStyle(Theme.ink)
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            } else {
                                stageList
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tr(phases[phaseIndex]))
                    if showTrace {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 8) {
                                AgentTraceView(steps: flow.agentSteps, active: activeWork, replay: flow.settings.demoMode)
                            }
                            .padding(.horizontal, Theme.margin).padding(.top, 8)
                        }
                        .scrollIndicators(.hidden)
                        .transition(.opacity)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .background(Theme.surface, in: UnevenRoundedRectangle(topLeadingRadius: Theme.heroRadius, topTrailingRadius: Theme.heroRadius, style: .continuous))
        .padding(.top, -Theme.heroRadius)
        .padding(.bottom, 0)
    }

    /// Quiet checklist of the four stages: done = check, current = bold with spinner, upcoming = tertiary.
    /// Rows change state without cross-fading text, so a screenshot at any moment shows one legible line per stage.
    private var stageList: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(phases.enumerated()), id: \.offset) { i, title in
                HStack(spacing: 14) {
                    ZStack {
                        if i < phaseIndex { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.inkSecondary) }
                        else if i == phaseIndex { ProgressView().controlSize(.small) }
                        else { Circle().stroke(Theme.hairline, lineWidth: 1.5).frame(width: 12, height: 12) }
                    }
                    .frame(width: 22, height: 22)
                    Text(tr(title))
                        .font(i == phaseIndex ? .title3.weight(.semibold) : .title3)
                        .foregroundStyle(i == phaseIndex ? Theme.ink : (i < phaseIndex ? Theme.inkSecondary : Theme.inkTertiary))
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, Theme.margin + 8).padding(.top, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorBlock(_ err: String) -> some View {
        let offline = err.lowercased().contains("connect") || err.lowercased().contains("offline") || err.lowercased().contains("network") || err.lowercased().contains("verbind")
        return VStack(spacing: 8) {
            Text(offline ? "No connection." : "We couldn't find the damage.")
                .font(.serif(.title2)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text(offline ? "Your photo is saved. Try again when you're back online." : "Try a closer photo in daylight, with the damage in the middle.")
                .font(.subheadline).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            PrimaryButton(title: "Try again") { flow.startAnalysis(resetExtras: false) }
            PrimaryButton(title: "Choose another photo", kind: .secondary) { flow.cancelAnalysis() }
        }
        .padding(.horizontal, Theme.margin).padding(.bottom, 32)
    }

    // MARK: Phase

    private var phaseIndex: Int {
        let order = AnalysisStage.allCases
        var idx = 0
        for (i, s) in order.enumerated() where flow.stageStates[s] == .active || flow.stageStates[s] == .done { idx = i }
        if flow.stageStates.isEmpty, !flow.isAnalyzing { idx = 3 }
        if flow.marksArrivedAt != nil { idx = max(idx, 2) }
        if flow.response != nil { idx = 3 }
        return min(idx, 3)
    }

    private var activeWork: (label: String, model: String)? {
        guard flow.isAnalyzing else { return nil }
        let stages: [(AnalysisStage, String, String)] = [
            (.classify, "Objekt und Sicherheit prüfen", "Muse Spark"), (.segment, "Schaden markieren", "SAM 3.1"),
            (.diagnose, "Diagnose stellen", "Muse Spark"), (.plan, "Reparatur planen", "Muse Wonder"),
        ]
        guard let s = stages.first(where: { flow.stageStates[$0.0] == .active }) ?? stages.first(where: { flow.stageStates[$0.0] != .done }) else { return nil }
        return (s.1, s.2)
    }
}

/// Four small dots under the status line: done = ink, current = pulsing ink, upcoming = fill.
struct PhaseDots: View {
    var current: Int
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(i <= current ? Theme.ink : Theme.fill)
                    .frame(width: 6, height: 6)
                    .opacity(i == current && pulse ? 0.4 : 1)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityHidden(true)
    }
}
