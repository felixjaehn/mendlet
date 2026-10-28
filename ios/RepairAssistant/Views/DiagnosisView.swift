import SwiftUI

struct DiagnosisView: View {
    @Environment(FlowModel.self) private var flow
    @State private var hidden: Set<String> = []
    @State private var pulsing: Set<String> = []
    @State private var selectedCause: Int?
    @State private var appeared = false

    var body: some View {
        @Bindable var flow = flow
        let r = flow.response
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let photo = flow.photo, let r {
                    PhotoStage(image: photo) { size in
                        SegmentOverlayView(segments: r.segments, size: size, hidden: hidden, pulsingIDs: pulsing, appeared: appeared, showDimension: true)
                    }
                    chipBar(r)
                }
                if let r {
                    if let banner = flow.newInfoBanner, r.diagnosis.labelInfo != nil { infoBanner(banner) }
                    summaryCard(r)
                    if r.diagnosis.needsMoreInfo { needsInfoCard(r) }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .safeAreaInset(edge: .bottom) { ctaBar(r) }
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { flow.reset() } label: { Image(systemName: "xmark") }.accessibilityLabel("Schließen")
            }
        }
        .sheet(isPresented: $flow.showFollowUp) { FollowUpSheet() }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.5).delay(0.15)) { appeared = true }
            if let r, r.diagnosis.needsMoreInfo, !flow.followUpUsed, !r.diagnosis.followUpQuestions.isEmpty {
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    flow.showFollowUp = true
                }
            }
        }
    }

    private func chipBar(_ r: AnalyzeResponse) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(Theme.spring) { hidden = hidden.isEmpty ? Set(r.segments.map(\.id)) : [] }
                    Haptics.selection()
                } label: { Chip(title: "Alle", systemImage: "square.stack.3d.up", tint: Theme.ink, isOn: hidden.isEmpty, filled: hidden.isEmpty) }
                ForEach(r.segments) { s in
                    Button {
                        withAnimation(Theme.spring) { if hidden.contains(s.id) { hidden.remove(s.id) } else { hidden.insert(s.id) } }
                        Haptics.selection()
                    } label: {
                        Chip(title: s.label, systemImage: hidden.contains(s.id) ? "eye.slash" : "eye", tint: segmentColor(s, in: r.segments), isOn: !hidden.contains(s.id))
                    }
                    .accessibilityLabel("\(s.label) \(hidden.contains(s.id) ? "einblenden" : "ausblenden")")
                }
            }
            .padding(.horizontal, Theme.margin)
        }
        .padding(.horizontal, -Theme.margin)
    }

    private func infoBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill").foregroundStyle(Theme.safe)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                if flow.response?.diagnosis.labelInfo?.materials.contains(where: { $0.lowercased().contains("elasthan") }) == true {
                    Text("Elasthan erkannt, also ein dehnbarer Stich").font(.footnote).foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.safeSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func summaryCard(_ r: AnalyzeResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(r.diagnosis.summary).font(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            ConfidenceMeter(confidence: r.diagnosis.confidence)
            if !r.diagnosis.likelyCauses.isEmpty {
                Divider().overlay(Theme.hairline)
                SectionLabel(text: "Wahrscheinliche Ursachen")
                VStack(spacing: 8) {
                    ForEach(Array(r.diagnosis.likelyCauses.enumerated()), id: \.offset) { i, cause in
                        Button { pulse(cause: i, r) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)").font(.rounded(.footnote)).monospacedDigit()
                                    .foregroundStyle(selectedCause == i ? .white : Theme.thread)
                                    .frame(width: 24, height: 24)
                                    .background(selectedCause == i ? Theme.thread : Theme.threadSoft, in: Circle())
                                Text(cause).font(.subheadline).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if !r.diagnosis.evidenceSegmentIds.isEmpty {
                                    Image(systemName: "scope").font(.footnote).foregroundStyle(Theme.inkSecondary)
                                }
                            }
                            .padding(10)
                            .background(selectedCause == i ? Theme.threadSoft : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, -10)
            }
        }
        .card()
    }

    private func needsInfoCard(_ r: AnalyzeResponse) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.bubble.fill").foregroundStyle(Theme.caution).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(flow.followUpUsed ? "Es fehlen weiter Angaben" : "Mir fehlt noch eine Angabe").font(.headline)
                Text(flow.followUpUsed ? "Mach ein neues, schärferes Foto, dann versuche ich es noch einmal." : "Mit einer kurzen Antwort kann ich Nadel, Faden und Stich genau wählen.")
                    .font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cautionSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func ctaBar(_ r: AnalyzeResponse?) -> some View {
        if let r {
            VStack(spacing: 0) {
                if r.diagnosis.needsMoreInfo {
                    if flow.followUpUsed {
                        PrimaryButton(title: "Neues Foto aufnehmen", systemImage: "camera.fill") { flow.reset() }
                    } else {
                        PrimaryButton(title: "Frage beantworten", systemImage: "text.bubble.fill") { flow.showFollowUp = true }
                    }
                } else {
                    PrimaryButton(title: "Weiter zur Entscheidung", systemImage: "arrow.right") { flow.go(.decision) }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.vertical, 12)
            .background(.regularMaterial)
        }
    }

    private func pulse(cause i: Int, _ r: AnalyzeResponse) {
        Haptics.selection()
        let ev = r.diagnosis.evidenceSegmentIds
        guard !ev.isEmpty else { return }
        selectedCause = i
        let id = ev[i % ev.count]
        hidden.remove(id)
        pulsing = [id]
        Task {
            try? await Task.sleep(for: .milliseconds(2600))
            if pulsing == [id] { pulsing = []; selectedCause = nil }
        }
    }
}
