import SwiftUI
import PhotosUI

struct HomeView: View {
    @Environment(FlowModel.self) private var flow
    @State private var showLiveScan = false
    @State private var liveCapture: (UIImage, DemoScenario?)?
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        @Bindable var flow = flow
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                topBar
                headline
                HeroShowcase()
                actions
                if flow.store.rescuedCount >= 1 { balanceRow }
                if flow.settings.demoMode { demoSection }
                if !flow.store.cases.isEmpty { historySection }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { flow.choose($0) }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showLiveScan, onDismiss: {
            if let (photo, scenario) = liveCapture {
                liveCapture = nil
                flow.choose(photo, scenarioHint: scenario)
            }
        }) {
            LiveScanView(settings: flow.settings) { photo, scenario in
                liveCapture = (photo, scenario)
                showLiveScan = false
            }
        }
        #if DEBUG
        .task { await debugJump() }
        #endif
        .photosPicker(isPresented: $showGallery, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { flow.choose(img) }
                pickerItem = nil
            }
        }
        .sheet(isPresented: $flow.showReview) { ReviewSheet() }
    }

    private var topBar: some View {
        HStack {
            if flow.settings.demoMode { DemoChip() }
            Spacer()
            Button { flow.showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44).glass(Circle(), interactive: true)
            }
            .accessibilityLabel(tr("Einstellungen"))
        }
        .padding(.top, 4)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reparieren").font(.largeTitle.bold()).foregroundStyle(Theme.ink)
                .onLongPressGesture(minimumDuration: 0.8) { Haptics.success(); flow.showSettings = true }
            Text("Zeig mir den Schaden. Ich markiere ihn auf deinem Foto und führe dich Schritt für Schritt durch die Reparatur.")
                .font(.body).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 10) {
            PrimaryButton(title: "Schaden scannen", systemImage: "viewfinder") { showLiveScan = true }
            HStack(spacing: 10) {
                PrimaryButton(title: "Kamera", systemImage: "camera", kind: .secondary) {
                    if CameraPicker.isAvailable { showCamera = true } else { showGallery = true }
                }
                PrimaryButton(title: "Fotos", systemImage: "photo.on.rectangle", kind: .secondary) { showGallery = true }
            }
            Text("Kleidung, Schuhe und Niedervolt-Elektronik").font(.footnote).foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity)
        }
    }

    private var balanceRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill").foregroundStyle(Theme.safe)
            VStack(alignment: .leading, spacing: 1) {
                Text("Deine Bilanz").font(.caption).foregroundStyle(Theme.inkSecondary)
                Text(tr(flow.store.rescuedCount == 1 ? "%lld Teil gerettet · ≈ %@ kg" : "%lld Teile gerettet · ≈ %@ kg", flow.store.rescuedCount, ImpactEstimator.format(kg: flow.store.rescuedKilograms)))
                    .font(.rounded(.subheadline, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.safeSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Demo-Szenarien")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(DemoScenario.allCases) { s in ScenarioCard(scenario: s) }
                }
                .padding(.horizontal, Theme.margin)
            }
            .padding(.horizontal, -Theme.margin)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Zuletzt analysiert")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(flow.store.cases.prefix(8)) { c in HistoryCard(item: c) }
                }
                .padding(.horizontal, Theme.margin)
            }
            .padding(.horizontal, -Theme.margin)
        }
    }
}

private struct ScenarioCard: View {
    @Environment(FlowModel.self) private var flow
    let scenario: DemoScenario
    @State private var image: UIImage?

    var body: some View {
        Button {
            Task {
                let img = await DemoPhotos.imageAsync(for: scenario)
                flow.choose(img, scenarioHint: scenario, note: scenario.userNote)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Theme.hairline.overlay(Image(systemName: scenario.systemImage).foregroundStyle(Theme.inkSecondary))
                    }
                }
                .frame(width: 132, height: 120).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(scenario.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(scenario.subtitle).font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
            }
            .frame(width: 132)
        }
        .buttonStyle(.plain)
        .task {
            image = await DemoPhotos.imageAsync(for: scenario)
        }
    }
}

private struct HistoryCard: View {
    @Environment(FlowModel.self) private var flow
    let item: SavedCase
    var body: some View {
        Button { flow.open(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let img = flow.store.image(for: item.id) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else { Theme.hairline }
                }
                .frame(width: 132, height: 96).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(item.response.diagnosis.summary.isEmpty ? tr("Analyse") : item.response.diagnosis.summary)
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 132)
        }
        .buttonStyle(.plain)
    }
}

/// Hero: the real product, the recorded jeans photo with its SAM mask and pins (no illustration).
private struct HeroShowcase: View {
    private let rec = LiveRecordings.recording(for: .textileTear)
    @State private var appeared = false

    var body: some View {
        if let rec, let photo = rec.photo {
            PhotoStage(image: photo, cornerRadius: 28, minAspect: 1.15) { size in
                SegmentOverlayView(segments: rec.response.segments.filter(\.isDamage), size: size, appeared: appeared, showLabels: true)
            }
            .overlay(alignment: .bottomLeading) {
                Label("SAM 3.1 · Muse Spark", systemImage: "sparkles")
                    .font(.caption.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6).glass(Capsule())
                    .padding(12)
            }
            .onAppear { withAnimation(.easeOut(duration: 0.9).delay(0.3)) { appeared = true } }
            .accessibilityLabel(tr("Beispiel: Riss in einer Jeans, markiert von SAM 3.1"))
        }
    }
}

#if DEBUG
extension HomeView {
    /// Screenshot helper: `-uiScreen liveScan|analysis|diagnosis|guide` (+ `-uiScenario textile_hole`) jumps straight to a screen.
    @MainActor func debugJump() async {
        let d = UserDefaults.standard
        guard let screen = d.string(forKey: "uiScreen") else { return }
        flow.settings.demoMode = true
        if screen == "liveScan" { try? await Task.sleep(for: .milliseconds(400)); showLiveScan = true; return }
        if screen == "settings" { try? await Task.sleep(for: .milliseconds(400)); flow.showSettings = true; return }
        let scenario = DemoScenario(rawValue: d.string(forKey: "uiScenario") ?? "") ?? .textileTear
        let img = await DemoPhotos.imageAsync(for: scenario)
        flow.choose(img, scenarioHint: scenario, note: scenario.userNote)
        flow.answers = [AnswerPayload(questionId: "debug", text: "Jeans, Baumwolle")]
        flow.startAnalysis(resetExtras: false)
        guard ["guide", "decision", "shopping", "completion"].contains(screen) else { return }
        let flow = self.flow
        Task { @MainActor in  // unstructured: survives HomeView's .task cancellation on navigation
        while flow.isAnalyzing || flow.response == nil { try? await Task.sleep(for: .milliseconds(200)) }
        try? await Task.sleep(for: .milliseconds(900))
        if screen == "decision" { flow.go(.decision); return }
        if screen == "shopping" { flow.go(.shopping); return }
        if screen == "completion" { flow.finishRepair(); return }
        for i in flow.shoppingItems { flow.statuses[i.id] = .have }
        flow.currentStep = d.integer(forKey: "uiStep")
        flow.startRepair()
        }
    }
}
#endif
