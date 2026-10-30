import SwiftUI

/// Home: the user's repair projects (in progress / done) and the single way to start a new scan.
struct HomeView: View {
    @Environment(FlowModel.self) private var flow
    @State private var tab: Tab = .inProgress
    @State private var demoPhoto: UIImage?
    @Namespace private var tabNS

    enum Tab: String, CaseIterable { case inProgress = "In progress", done = "Done" }

    var body: some View {
        @Bindable var flow = flow
        let progress = flow.inProgress, done = flow.doneProjects
        let savings = Savings.totals(for: done)
        ZStack(alignment: .bottom) {
            Theme.paper.ignoresSafeArea()
            if progress.isEmpty && done.isEmpty { emptyState } else {
              VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if !savings.isEmpty { SavingsCard(totals: savings) { flow.path.append(.impact) }.padding(.top, 4) }
                        tabs
                        if tab == .inProgress {
                            if progress.isEmpty { quiet("Nothing in progress. Start a scan to begin.") }
                            ForEach(Array(progress.enumerated()), id: \.element.id) { i, c in
                                ProjectCard(project: c) { flow.openProject(c) }
                                    .transition(.opacity.combined(with: .offset(y: 12)))
                            }
                            belowCards(done)
                        } else {
                            if done.isEmpty { quiet("Finished repairs show up here.") }
                            else { Text(doneSummary(done)).font(.subheadline).foregroundStyle(Theme.inkSecondary) }
                            VStack(spacing: 0) {
                                ForEach(Array(done.enumerated()), id: \.element.id) { i, c in
                                    DoneRow(project: c) { flow.openProject(c) }
                                    if i < done.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 76) }
                                }
                            }
                            if done.count > 0 && done.count < 4 {
                                Text("Finished repairs stay here with their before and after.")
                                    .font(.footnote).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity).padding(.top, 20)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.margin).padding(.top, 4)
                    .animation(Theme.spring, value: tab)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.bottom, 16, for: .scrollContent)
                // the pill sits below the list in layout, so rows can never run under it
                scanButton.padding(.top, 12).padding(.bottom, 24)
              }
            }
        }
        .navigationTitle("Repairs")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { flow.showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .accessibilityLabel(tr("More"))
            }
        }
        .fullScreenCover(isPresented: $flow.showScan) {
            ScanView(demoPhoto: demoPhoto, onClose: { flow.showScan = false }, onCapture: { photo, scenario in
                if let scenario { flow.scan(photo, scenarioHint: scenario, note: flow.note.isEmpty ? scenario.userNote : flow.note) }
                else if InlineCameraSession.hasCamera { flow.scan(photo) }
                else { flow.scan(photo, scenarioHint: .realSweater, note: flow.note.isEmpty ? DemoScenario.realSweater.userNote : flow.note) }
            }, onPick: { flow.scan($0) })
        }
        .onAppear { tab = flow.inProgress.isEmpty && !flow.doneProjects.isEmpty ? .done : tab }
        .task { demoPhoto = await DemoPhotos.imageAsync(for: .realSweater) }
        #if DEBUG
        .task { await debugJump() }
        #endif
    }

    // MARK: Parts

    private var tabs: some View {
        HStack(spacing: 24) {
            ForEach(Tab.allCases, id: \.self) { t in
                Button {
                    withAnimation(Theme.spring) { tab = t }; Haptics.selection()
                } label: {
                    VStack(spacing: 8) {
                        Text(tr(t.rawValue)).font(.body.weight(.semibold)).foregroundStyle(tab == t ? Theme.ink : Theme.inkSecondary)
                        ZStack {
                            Capsule().fill(Color.clear).frame(height: 2)
                            if tab == t { Capsule().fill(Theme.ink).frame(height: 2).matchedGeometryEffect(id: "tab", in: tabNS) }
                        }
                    }
                    .frame(minHeight: 44, alignment: .bottom).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
            Spacer()
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    /// Under the cards: a calm preview of finished repairs, or one hint row when there are none yet.
    @ViewBuilder private func belowCards(_ done: [SavedCase]) -> some View {
        if done.isEmpty {
            Button { flow.showScan = true } label: {
                HStack(spacing: 12) {
                    Image(systemName: "camera").font(.system(size: 20)).foregroundStyle(Theme.inkSecondary).frame(width: 28)
                    Text("Scan something that needs fixing").font(.body).foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
                }
                .padding(.horizontal, 16).frame(minHeight: 56)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .buttonStyle(PressScaleStyle()).padding(.top, 8)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Done").sectionHeader()
                    Spacer()
                    if done.count > 2 {
                        Button("See all") { withAnimation(Theme.spring) { tab = .done } }.font(.subheadline).foregroundStyle(Theme.thread)
                    }
                }
                .padding(.bottom, 4)
                ForEach(Array(done.prefix(2).enumerated()), id: \.element.id) { i, c in
                    DoneRow(project: c) { flow.openProject(c) }
                    if i < min(done.count, 2) - 1 { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 72) }
                }
            }
            .padding(.top, 16)
        }
    }

    private func doneSummary(_ done: [SavedCase]) -> String {
        done.count == 1 ? "1 repair done" : "\(done.count) repairs done"
    }

    private func quiet(_ text: String) -> some View {
        Text(text).font(.body).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.top, 48)
    }

    private var scanButton: some View {
        Button { flow.showScan = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "camera.fill").font(.system(size: 16, weight: .semibold))
                Text("Scan").font(.headline)
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24).frame(height: 56)
            .glass(Capsule(), interactive: true)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(0.10), radius: 12, y: 4)
        .accessibilityLabel(tr("Scan"))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("Nothing to mend yet.").font(.title.bold()).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            Text("Photograph a tear, a loose sole or a broken cable.").font(.body).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            Spacer().frame(height: 12)
            Button { flow.showScan = true } label: { Text("Scan something") }
                .buttonStyle(PrimaryButtonStyle(kind: .primary))
                .frame(maxWidth: 280)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: Cards

/// Project title, repair line and progress shared by Home and Project.
enum ProjectInfo {
    static func title(_ c: SavedCase) -> String { ProjectTitle.title(summary: c.response.diagnosis.summary, english: Lang.shared.isEnglish) }
    static func subtitle(_ c: SavedCase) -> String { ProjectTitle.subtitle(for: c.response, parked: c.parked == true) }

    /// Everything not yet ticked, required or not: the same count as the checklist and the verdict.
    static func missing(_ c: SavedCase) -> [ShoppingItem] { c.response.shoppingList.filter { c.shoppingStatus[$0.id] != .have } }

    /// Quiet verdict label for cards and rows.
    static func verdict(_ c: SavedCase) -> String? {
        if c.parked == true { return tr("Zum Profi") }
        return c.response.decision?.recommendation.title
    }

    static func stillNeeded(_ c: SavedCase) -> String? {
        let names = missing(c).map { ($0.name.components(separatedBy: ",").first ?? $0.name).lowercasedFirst }
        guard !names.isEmpty else { return nil }
        if names.count <= 2 { return "Still needed: " + names.joined(separator: " and ").replacingOccurrences(of: " and ", with: ", ") }
        return "Still needed: " + names.prefix(2).joined(separator: ", ") + " and \(names.count - 2) more"
    }

    static func started(_ c: SavedCase) -> Bool { c.currentStep > 0 || !c.completedSteps.isEmpty }

    static func progressLine(_ c: SavedCase) -> String {
        let steps = c.response.guide.steps.count
        if started(c) { return "Step \(min(c.currentStep + 1, max(steps, 1))) of \(steps)" }
        let items = c.response.shoppingList
        if !items.isEmpty && !missing(c).isEmpty { return "Gathering materials" }
        return "Ready to start"
    }
}

struct ProjectCard: View {
    @Environment(FlowModel.self) private var flow
    let project: SavedCase
    var action: () -> Void

    var body: some View {
        let steps = project.response.guide.steps.count
        let parked = project.parked == true
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                MarkedThumb(caseId: project.id, response: project.response, store: flow.store)
                    .aspectRatio(16.0 / 10.0, contentMode: .fit)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: Theme.cardRadius, topTrailingRadius: Theme.cardRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    if let v = ProjectInfo.verdict(project) { Text(v).font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary).padding(.bottom, 2) }
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ProjectInfo.title(project)).font(.headline).foregroundStyle(Theme.ink)
                            Text(ProjectInfo.subtitle(project)).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer(minLength: 0)
                        if !parked && steps > 0 { StepRing(done: project.completedSteps.count, total: steps) }
                    }
                    if !parked && steps > 0 {
                        Text(ProjectInfo.progressLine(project)).font(.footnote).foregroundStyle(Theme.inkSecondary).padding(.top, 8)
                        if let need = ProjectInfo.stillNeeded(project) {
                            Text(need).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 2)
                        } else if !ProjectInfo.started(project) && !project.response.shoppingList.isEmpty {
                            Text("Everything is ready").font(.subheadline).foregroundStyle(Theme.ink).padding(.top, 2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .contextMenu {
            Button(role: .destructive) { flow.store.delete(project.id) } label: { Label("Delete project", systemImage: "trash") }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(ProjectInfo.title(project)), \(ProjectInfo.progressLine(project).lowercased())\(ProjectInfo.stillNeeded(project).map { ", " + $0.lowercased() } ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}

/// Small progress ring with "2/6" inside, right-aligned on a project card.
struct StepRing: View {
    let done: Int, total: Int
    var body: some View {
        ZStack {
            Circle().stroke(Theme.fill, lineWidth: 3)
            Circle().trim(from: 0, to: total > 0 ? CGFloat(done) / CGFloat(total) : 0)
                .stroke(Theme.thread, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
            Text("\(done)/\(total)").font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
        }
        .frame(width: 44, height: 44)
        .accessibilityHidden(true)
    }
}

struct DoneRow: View {
    @Environment(FlowModel.self) private var flow
    let project: SavedCase
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                MarkedThumb(caseId: project.id, response: project.response, store: flow.store, marks: false)
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.thumbRadius, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    if let v = ProjectInfo.verdict(project) { Text(v).font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary) }
                    Text(ProjectInfo.title(project)).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text("Repaired " + (project.finishedAt ?? project.createdAt).formatted(.dateTime.day().month(.abbreviated).locale(Lang.shared.locale)))
                        .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
            }
            .padding(.vertical, 12).frame(minHeight: 72)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { flow.store.delete(project.id) } label: { Label("Delete project", systemImage: "trash") }
        }
    }
}

/// The saved photo with the damage outline drawn static (1.25 pt, no scrim, no label).
struct MarkedThumb: View {
    let caseId: String
    let response: AnalyzeResponse
    let store: CaseStore
    var marks = true
    @State private var image: UIImage?

    var body: some View {
        Color(uiColor: .secondarySystemFill)
            .overlay {
                if let image {
                    if marks { MarkedPhoto(image: image, segments: response.segments, mode: .thumb, showLabels: false, zoomable: false) }
                    else { Image(uiImage: image).resizable().scaledToFill() }
                }
            }
            .clipped()
            .task(id: caseId) { image = store.image(for: caseId) }
            .accessibilityHidden(true)
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
                                flow.scan(img, scenarioHint: s, note: s.userNote)
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
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Cancel", action: close) } }
        }
        .presentationDetents([.large])
    }
}

#if DEBUG
extension HomeView {
    /// Screenshot helper: `-uiScreen home|project|projectDone|scan|liveScan|settings|analysis|diagnosis|decision|shopping|guide|completion`
    /// (+ `-uiScenario textile_hole`) jumps straight to a screen.
    @MainActor func debugJump() async {
        let d = UserDefaults.standard
        guard let screen = d.string(forKey: "uiScreen") else { return }
        flow.settings.demoMode = true
        if screen == "scan" { try? await Task.sleep(for: .milliseconds(400)); flow.showScan = true; return }
        if screen == "liveScan" { try? await Task.sleep(for: .milliseconds(400)); flow.showScan = true; return }
        if screen == "settings" { try? await Task.sleep(for: .milliseconds(400)); flow.showSettings = true; return }
        if screen == "impact" { _ = await DebugSeed.projects(flow); try? await Task.sleep(for: .milliseconds(500)); flow.path = [.impact]; return }
        if ["home", "project", "projectDone"].contains(screen) {
            let (a, b) = await DebugSeed.projects(flow)
            tab = screen == "home" && d.string(forKey: "uiTab") == "done" ? .done : .inProgress
            if screen == "project" { try? await Task.sleep(for: .milliseconds(500)); flow.openProject(a) }
            if screen == "projectDone" { try? await Task.sleep(for: .milliseconds(500)); flow.openProject(b) }
            return
        }
        let scenario = DemoScenario(rawValue: d.string(forKey: "uiScenario") ?? "") ?? .textileTear
        let img = await DemoPhotos.imageAsync(for: scenario)
        flow.choose(img, scenarioHint: scenario, note: scenario.userNote)
        flow.answers = [AnswerPayload(questionId: "debug", text: "Jeans, Baumwolle")]
        flow.startAnalysis(resetExtras: false)
        let wanted = screen == "checklist" ? "shopping" : screen
        guard ["guide", "decision", "shopping", "completion"].contains(wanted) else { return }
        let flow = self.flow
        Task { @MainActor in  // unstructured: survives HomeView's .task cancellation on navigation
            while flow.isAnalyzing || flow.response == nil { try? await Task.sleep(for: .milliseconds(200)) }
            try? await Task.sleep(for: .milliseconds(3200))
            flow.startProject()
            if wanted == "decision" { flow.go(.decision); return }
            if wanted == "shopping" {
                for (n, i) in flow.shoppingItems.enumerated() where n % 2 == 0 { flow.statuses[i.id] = .have }
                flow.go(.shopping); return
            }
            if wanted == "completion" { flow.finishRepair(); return }
            for i in flow.shoppingItems { flow.statuses[i.id] = .have }
            flow.currentStep = d.integer(forKey: "uiStep")
            flow.completedSteps = Set(0..<flow.currentStep)
            flow.startRepair()
        }
    }
}

/// Seeds two projects for the Home / Project screenshots: one in progress, one done.
@MainActor enum DebugSeed {
    static func projects(_ flow: FlowModel) async -> (SavedCase, SavedCase) {
        flow.store.clearHistory()
        func make(_ s: DemoScenario, id: String) async -> SavedCase? {
            guard var r = LiveRecordings.recording(for: s)?.response else { return nil }
            r.caseId = id
            let r2 = FlowGate.sanitized(r)
            let img = ImageResizer.resized(await DemoPhotos.imageAsync(for: s))
            return SavedCase(id: id, createdAt: Date(), userNote: s.userNote, response: r2, shoppingStatus: [:], currentStep: 0, completedSteps: [], finished: false, started: true, parked: nil, finishedAt: nil, scenario: s.rawValue).withImage(img, store: flow.store)
        }
        var a = await make(.realSweater, id: "seed-sweater")!
        let required = a.response.shoppingList.filter(\.required)
        for i in required.prefix(1) { a.shoppingStatus[i.id] = .have }
        a.currentStep = 2; a.completedSteps = [0, 1]
        flow.store.upsert(a)
        var b = await make(.shoeSole, id: "seed-sneaker")!
        b.finished = true; b.finishedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
        b.currentStep = max(b.response.guide.steps.count - 1, 0); b.completedSteps = Array(0..<b.response.guide.steps.count)
        flow.store.upsert(b)
        // more finished repairs (with new prices) so the savings card and the impact screen are populated
        for (s, id, days) in [(DemoScenario.realSweater, "seed-sweater-done", 5), (.textileTear, "seed-jeans", 9)] {
            guard var c = await make(s, id: id) else { continue }
            c.finished = true; c.finishedAt = Calendar.current.date(byAdding: .day, value: -days, to: Date())
            c.currentStep = max(c.response.guide.steps.count - 1, 0); c.completedSteps = Array(0..<c.response.guide.steps.count)
            flow.store.upsert(c)
        }
        return (a, b)
    }
}

private extension SavedCase {
    @MainActor func withImage(_ image: UIImage, store: CaseStore) -> SavedCase {
        store.upsert(self, image: image)
        return self
    }
}
#endif
