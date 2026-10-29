import SwiftUI
import PhotosUI

struct HomeView: View {
    @Environment(FlowModel.self) private var flow
    @State private var showLiveScan = false
    @State private var liveCapture: (UIImage, DemoScenario?)?
    @State private var showGallery = false
    @State private var showGrid = false
    @State private var showHistory = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var recents = RecentPhotos()
    @State private var demoPhoto: UIImage?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var flow = flow
        ZStack {
            InlineCameraCard(active: !showLiveScan && !flow.showReview && !flow.showSettings && !showGrid && !showHistory,
                             demoPhoto: demoPhoto, lastThumb: recents.images.first?.image ?? demoPhoto,
                             onCapture: { photo in
                                 if InlineCameraSession.hasCamera { flow.choose(photo) }
                                 else { flow.choose(photo, scenarioHint: .textileTear, note: DemoScenario.textileTear.userNote) }
                             },
                             onLiveScan: { showLiveScan = true },
                             onGallery: { if InlineCameraSession.hasCamera { showGallery = true } else { showGrid = true } })
            VStack {
                HStack {
                    if !flow.store.cases.isEmpty {
                        glassButton("clock.arrow.circlepath", label: "History") { showHistory = true }
                    }
                    Spacer()
                    glassButton("gearshape", label: tr("Einstellungen")) { flow.showSettings = true }
                }
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .navigationBarHidden(true)
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
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
        .task { demoPhoto = await DemoPhotos.imageAsync(for: .textileTear); await recents.load() }
        .onChange(of: scenePhase) { _, p in if p == .active { Task { await recents.load() } } }
        .photosPicker(isPresented: $showGallery, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { flow.choose(img) }
                pickerItem = nil
            }
        }
        .sheet(isPresented: $flow.showReview) { ReviewSheet() }
        .sheet(isPresented: $showGrid) { PhotoGridSheet { showGrid = false } }
        .sheet(isPresented: $showHistory) { HistorySheet { showHistory = false } }
    }

    private func glassButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.3), in: Circle())
                .glass(Circle(), interactive: true)
        }
        .accessibilityLabel(label)
    }
}

/// Plain photo grid (like a camera roll, no labels). Picking a photo starts the analysis with it.
struct PhotoGridSheet: View {
    @Environment(FlowModel.self) private var flow
    var close: () -> Void
    @State private var images: [DemoScenario: UIImage] = [:]
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 2) {
                    ForEach(DemoScenario.allCases) { s in
                        Button {
                            Task {
                                let img = await DemoPhotos.imageAsync(for: s)
                                close()
                                flow.choose(img, scenarioHint: s, note: s.userNote)
                            }
                        } label: {
                            Color(Theme.fill).aspectRatio(1, contentMode: .fit)
                                .overlay { if let i = images[s] { Image(uiImage: i).resizable().scaledToFill() } }
                                .clipped()
                        }
                        .buttonStyle(.plain).accessibilityLabel(tr("Fotos"))
                        .task { images[s] = await DemoPhotos.imageAsync(for: s) }
                    }
                }
            }
            .navigationTitle("Photos").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(tr("Abbrechen"), action: close) } }
        }
        .presentationDetents([.large])
    }
}

struct HistorySheet: View {
    @Environment(FlowModel.self) private var flow
    var close: () -> Void
    private let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: cols, spacing: 2) {
                    ForEach(flow.store.cases) { c in
                        Button { close(); flow.open(c) } label: {
                            Color(Theme.fill).aspectRatio(1, contentMode: .fit)
                                .overlay { if let i = flow.store.image(for: c.id) { Image(uiImage: i).resizable().scaledToFill() } }
                                .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("History").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done", action: close) } }
        }
        .presentationDetents([.large])
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
