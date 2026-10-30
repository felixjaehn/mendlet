import SwiftUI
import Observation

@MainActor
@Observable
final class FlowModel {
    enum Route: Hashable { case analysis, diagnosis, decision, shopping, guide, block, completion, project(String), impact }

    let settings: AppSettings
    let store: CaseStore

    var path: [Route] = []

    // Capture
    var photo: UIImage?
    var note = ""
    var showReview = false

    // Analysis
    var stageStates: [AnalysisStage: StageState] = [:]
    var earlySegments: [Segment] = []
    /// When the first marks arrived: the reveal animation on Analysis runs from here and is never cut short.
    var marksArrivedAt: Date?
    /// Live agent trace (SSE `agent_step`), newest last.
    var agentSteps: [AgentStep] = []
    /// true once the proxy announced the Spark grounding fallback (extra live step).
    var groundingSeen = false
    var isAnalyzing = false
    var analysisError: String?
    var response: AnalyzeResponse?
    var labelImage: UIImage?
    var extraImages: [ExtraImage] = []
    var answers: [AnswerPayload] = []
    var followUpUsed = false
    var showFollowUp = false
    var newInfoBanner: String?
    // Optional label flow (diagnosis screen)
    var labelBusy = false
    /// Shopping items that changed because of the label photo (highlighted for a moment).
    var changedItemIds: Set<String> = []
    private var labelBaseline: AnalyzeResponse?
    // Tap to refine (diagnosis): one SAM point prompt when the mask missed the damage.
    var refineMode = false
    var refineBusy = false
    var refineError: String?
    // Muse Image before/after
    enum AfterState: Equatable { case idle, loading, ready, unavailable }
    var afterState: AfterState = .idle
    var afterImage: UIImage?
    private var afterCaseId: String?
    private var afterTask: Task<Void, Never>?
    // Muse Image step pictures (guide): in-memory cache per case + step number; a failed step stays hidden.
    var stepImages: [Int: UIImage] = [:]
    private var stepImagePending: Set<Int> = []
    private var stepImageFailed: Set<Int> = []
    private var stepImageCaseId: String?
    private var analysisTask: Task<Void, Never>?

    // Shopping & guide
    var statuses: [String: ItemStatus] = [:]
    var currentStep = 0
    var completedSteps: Set<Int> = []
    var guideStartedAt: Date?
    var resultPhoto: UIImage?
    var showSettings = false
    /// Home presents Scan as a cover; Analysis pushes underneath.
    var showScan = false
    var projectStarted = false
    var projectParked = false

    init(settings: AppSettings = AppSettings(), store: CaseStore = CaseStore()) {
        self.settings = settings
        self.store = store
    }

    var service: AnalysisService { settings.makeService() }

    // MARK: Capture

    func choose(_ image: UIImage, scenarioHint: DemoScenario? = nil, note: String? = nil) {
        photo = ImageResizer.resized(image)
        if let note { self.note = note }
        if let scenarioHint { settings.scenario = scenarioHint }
        showReview = true
    }

    /// Scan -> Analysis: the captured photo goes straight into the analysis (no review step).
    func scan(_ image: UIImage, scenarioHint: DemoScenario? = nil, note: String? = nil) {
        choose(image, scenarioHint: scenarioHint, note: note)
        showReview = false
        showScan = false
        startAnalysis()
    }

    // MARK: Analysis

    func startAnalysis(resetExtras: Bool = true) {
        guard let photo else { return }
        if resetExtras {
            projectStarted = false; projectParked = false
            extraImages = []; answers = []; followUpUsed = false; labelImage = nil; newInfoBanner = nil
            statuses = [:]; currentStep = 0; completedSteps = []; guideStartedAt = nil
        }
        showReview = false
        showFollowUp = false
        analysisError = nil
        response = resetExtras ? nil : response
        stageStates = [:]; groundingSeen = false; agentSteps = []
        earlySegments = resetExtras ? [] : (response?.segments ?? earlySegments)
        marksArrivedAt = earlySegments.isEmpty ? nil : Date()
        isAnalyzing = true
        path = [.analysis]

        let request = AnalyzeRequest(
            imageBase64: ImageResizer.base64(photo), userNote: note,
            extraImages: extraImages, answers: answers, locale: Lang.apiCode,
            mockScenario: settings.demoMode ? settings.scenario.rawValue : (settings.scenarioRaw.isEmpty ? nil : settings.scenario.rawValue),
            agent: settings.demoMode ? nil : settings.precisionMode)
        let svc = service
        analysisTask?.cancel()
        analysisTask = Task { [weak self] in
            do {
                for try await event in svc.analyze(request) {
                    guard let self else { return }
                    self.handle(event)
                }
                guard let self else { return }
                if self.isAnalyzing { self.fail(APIError.emptyResult) }
            } catch is CancellationError {
            } catch {
                self?.fail(APIError.from(error))
            }
        }
    }

    private func handle(_ event: AnalyzeEvent) {
        switch event {
        case .progress(let stage, _, let segments):
            let order = AnalysisStage.allCases
            let idx = order.firstIndex(of: stage) ?? 0
            for (i, s) in order.enumerated() { stageStates[s] = i < idx ? .done : (i == idx ? .active : .pending) }
            if let segments, !segments.isEmpty { setEarly(segments) }
        case .grounding:
            groundingSeen = true
        case .segments(let segments):
            if !segments.isEmpty { setEarly(segments) }
        case .agentStep(let step):
            if let i = agentSteps.firstIndex(where: { $0.n == step.n }) { agentSteps[i] = step } else { agentSteps.append(step) }
            agentSteps.sort { $0.n < $1.n }
        case .result(let r):
            finish(with: FlowGate.sanitized(r))
        }
    }

    private func setEarly(_ segments: [Segment]) {
        earlySegments = segments
        if marksArrivedAt == nil { marksArrivedAt = Date() }
    }

    private func finish(with r: AnalyzeResponse) {
        if r.segments.isEmpty && r.diagnosis.summary.isEmpty && !FlowGate.isBlocked(r) {
            fail(APIError.emptyResult); return
        }
        for s in AnalysisStage.allCases { stageStates[s] = .done }
        response = r
        if earlySegments.isEmpty, !r.segments.isEmpty { setEarly(r.segments) }
        isAnalyzing = false
        let hadLabel = (labelImage != nil) && r.diagnosis.labelInfo != nil
        newInfoBanner = hadLabel ? r.diagnosis.labelInfo.map { tr("Etikett erkannt: %@", $0.materials.joined(separator: ", ")) } : nil
        if hadLabel, let base = labelBaseline { markChanged(from: base, to: r) }
        labelBaseline = nil
        persist()
        // let the last checkmark land before navigating
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            // the mark reveal (3.6 s) always runs to its end before the screen changes
            if let t = self?.marksArrivedAt {
                let left = t.timeIntervalSinceNow + 4.1
                if left > 0 { try? await Task.sleep(for: .seconds(left)) }
            }
            guard let self, self.response?.caseId == r.caseId else { return }
            switch FlowGate.destination(for: r) {
            case .block: self.path = [.block]; Haptics.warning()
            case .diagnosis: self.path = [.diagnosis]
            }
        }
    }

    private func fail(_ e: APIError) {
        isAnalyzing = false
        analysisError = e.errorDescription
    }

    func cancelAnalysis() {
        analysisTask?.cancel()
        isAnalyzing = false
        path = []
    }

    // MARK: Follow-up (max one round)

    func submitFollowUp(answers newAnswers: [AnswerPayload], images: [(Purpose, UIImage)]) {
        followUpUsed = true
        answers = newAnswers
        extraImages = images.map { ExtraImage(purpose: $0.0, imageBase64: ImageResizer.base64($0.1)) }
        labelImage = images.first(where: { $0.0 == .label })?.1 ?? images.first?.1
        startAnalysis(resetExtras: false)
    }

    // MARK: Optional label photo (jeans)

    /// Card "Etikett fotografieren" is offered for textile cases without label data.
    var labelOfferAvailable: Bool {
        guard let r = response, r.category == .textile, !r.diagnosis.needsMoreInfo, !FlowGate.isBlocked(r),
              labelImage == nil, r.diagnosis.labelInfo?.materials.isEmpty ?? true else { return false }
        if settings.demoMode { return LiveRecordings.recording(for: settings.scenario)?.labelResponse != nil }
        return true
    }

    func markChanged(from old: AnalyzeResponse, to new: AnalyzeResponse) {
        let before = Dictionary(old.shoppingList.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        changedItemIds = Set(new.shoppingList.filter { before[$0.id] != $0.name }.map(\.id))
    }

    /// Demo: replays jeans_label.json after a short "reading" phase and shows what changed.
    func applyDemoLabel() {
        guard !labelBusy, let old = response, let rec = LiveRecordings.recording(for: settings.scenario), var new = rec.labelResponse else { return }
        labelImage = rec.labelPhoto
        labelBusy = true
        new.caseId = old.caseId
        let fast = settings.fastReplay
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(fast ? 900 : 2800))
            guard let self, self.response?.caseId == old.caseId else { return }
            let sane = FlowGate.sanitized(new)
            self.markChanged(from: old, to: sane)
            self.newInfoBanner = sane.diagnosis.labelInfo.map { tr("Etikett erkannt: %@", $0.materials.joined(separator: ", ")) }
            self.labelBusy = false
            withAnimation(Theme.spring) { self.response = sane }
            self.currentStep = 0; self.completedSteps = []
            Haptics.success()
            self.persist()
        }
    }

    /// Live: runs the analysis again with the label photo as extra image.
    func submitLabelPhoto(_ image: UIImage) {
        labelBaseline = response
        let img = ImageResizer.resized(image)
        extraImages = [ExtraImage(purpose: .label, imageBase64: ImageResizer.base64(img))]
        labelImage = img
        followUpUsed = true
        startAnalysis(resetExtras: false)
    }

    // MARK: Tap to refine

    /// `point` is normalized to the photo. The tapped mask replaces damage marks it overlaps (keeping their id, so guide
    /// overlays still point at it) or is added as a new damage mark.
    func refine(at point: CGPoint) {
        guard let r = response, let photo, !refineBusy else { return }
        refineBusy = true; refineError = nil
        let label = r.segments.first(where: \.isDamage)?.label ?? tr("Damage")
        let req = RefineRequest(imageBase64: ImageResizer.base64(photo),
                                points: [RefinePoint(x: Double(point.x), y: Double(point.y), label: "positive")], box: nil, label: label)
        let svc = service
        Task { [weak self] in
            do {
                let seg = try await svc.refine(req)
                guard let self, var resp = self.response, resp.caseId == r.caseId else { return }
                resp.segments = Self.merging(refined: seg, into: resp.segments)
                withAnimation(Theme.spring) { self.response = resp; self.refineMode = false }
                Haptics.success()
            } catch {
                self?.refineError = APIError.from(error).errorDescription
            }
            self?.refineBusy = false
        }
    }

    static func merging(refined: Segment, into segments: [Segment]) -> [Segment] {
        let new = refined.normalizedBounds ?? .zero
        let hit = segments.filter { $0.isDamage && ($0.normalizedBounds.map { $0.intersects(new) } ?? false) }
        var seg = refined
        seg.kind = .damage
        seg.id = hit.first?.id ?? {
            var i = segments.count + 1
            while segments.contains(where: { $0.id == "seg_\(i)" }) { i += 1 }
            return "seg_\(i)"
        }()
        let dropped = Set(hit.map(\.id))
        return segments.filter { !dropped.contains($0.id) } + [seg]
    }

    // MARK: Muse Image preview

    func loadAfterPreview() {
        guard let r = response, let photo, !FlowGate.isBlocked(r) else { return }
        if afterCaseId == r.caseId, afterState != .idle { return }
        afterCaseId = r.caseId
        afterState = .loading; afterImage = nil
        afterTask?.cancel()
        let demo = settings.demoMode, scenario = settings.scenario, fast = settings.fastReplay
        let svc = service
        afterTask = Task { [weak self] in
            if demo {
                guard LiveRecordings.afterImage(for: scenario) != nil else { self?.afterState = .unavailable; return }
                try? await Task.sleep(for: .milliseconds(fast ? 500 : 1800))
                guard !Task.isCancelled, let self, self.afterCaseId == r.caseId else { return }
                if let img = LiveRecordings.afterImage(for: scenario) { self.afterImage = img; self.afterState = .ready } else { self.afterState = .unavailable }
                return
            }
            let req = Self.afterPreviewRequest(for: r, photo: photo)
            do {
                let resp = try await svc.afterPreview(req)
                guard !Task.isCancelled, let self, self.afterCaseId == r.caseId else { return }
                if let d = resp.imageData, let img = UIImage(data: d) { self.afterImage = img; self.afterState = .ready } else { self.afterState = .unavailable }
            } catch {
                guard !Task.isCancelled, let self, self.afterCaseId == r.caseId else { return }
                self.afterState = .unavailable
            }
        }
    }

    /// Demo: the recording's `<name>_step<n>.jpg` if bundled. Live: nil until `loadStepImage` has fetched it.
    func stepImage(for step: GuideStep) -> UIImage? {
        if settings.demoMode {
            guard let name = LiveRecordings.name(for: settings.scenario) else { return nil }
            return LiveRecordings.image(file: "\(name)_step\(step.n)")
        }
        return stepImages[step.n]
    }

    /// Live mode only, lazily when a step is shown: POST /step-image. Failure just leaves the toggle hidden.
    func loadStepImage(for step: GuideStep) {
        guard !settings.demoMode, let r = response, let photo, !FlowGate.isBlocked(r) else { return }
        if stepImageCaseId != r.caseId { stepImageCaseId = r.caseId; stepImages = [:]; stepImagePending = []; stepImageFailed = [] }
        guard stepImages[step.n] == nil, !stepImagePending.contains(step.n), !stepImageFailed.contains(step.n) else { return }
        stepImagePending.insert(step.n)
        var req = Self.afterPreviewRequest(for: r, photo: photo)
        req.stepTitle = String(step.title.prefix(120)); req.stepText = String(step.text.prefix(600))
        let svc = service, caseId = r.caseId, n = step.n
        Task { [weak self] in
            var image: UIImage?
            if let resp = try? await svc.stepImage(req), let d = resp.imageData { image = UIImage(data: d) }
            guard let self, self.stepImageCaseId == caseId else { return }
            self.stepImagePending.remove(n)
            if let image { self.stepImages[n] = image } else { self.stepImageFailed.insert(n) }
        }
    }

    /// Textile: stitch type of the first stitch_path step. Shoe: category "shoe" and no stitch type.
    static func afterPreviewRequest(for r: AnalyzeResponse, photo: UIImage) -> AfterPreviewRequest {
        let b64 = ImageResizer.base64(photo)
        if r.category == .shoe {
            let hint = r.guide.steps.prefix(3).map(\.title).joined(separator: "; ")
            return AfterPreviewRequest(imageBase64: b64, diagnosisSummary: r.diagnosis.summary, stitchType: nil, category: "shoe",
                                       repairHint: hint.isEmpty ? nil : String(hint.prefix(200)))
        }
        let stitch = r.guide.steps.first { $0.overlay?.type == .stitchPath }?.overlay?.stitchType ?? .runningStitch
        return AfterPreviewRequest(imageBase64: b64, diagnosisSummary: r.diagnosis.summary, stitchType: stitch)
    }

    // MARK: Navigation (always through the safety gate)

    func go(_ route: Route) {
        let gateRoute: FlowGate.Route = switch route {
        case .analysis, .diagnosis: .diagnosis
        case .decision: .decision
        case .shopping: .shopping
        case .guide: .guide
        case .block: .block
        case .completion: .completion
        case .project, .impact: .guide
        }
        guard route == .analysis || FlowGate.canNavigate(to: gateRoute, response: response) else { Haptics.warning(); return }
        path.append(route)
    }

    var shoppingItems: [ShoppingItem] { response?.shoppingList ?? [] }
    /// One source for every checklist number: "N things" = all items, ready = marked as have, missing = the rest (required or not).
    var shoppingProgress: (total: Int, ready: Int, missing: Int) {
        let total = shoppingItems.count
        let ready = shoppingItems.filter { statuses[$0.id] == .have }.count
        return (total, ready, total - ready)
    }

    func setStatus(_ item: ShoppingItem, _ status: ItemStatus) {
        statuses[item.id] = (statuses[item.id] == status) ? nil : status
        Haptics.selection()
        persist()
    }

    /// Problem found → start repairing. The shopping list is a checklist, never a gate;
    /// each step shows what it needs anyway. The safety gate still decides whether a guide exists at all.
    func startRepair() {
        guard FlowGate.canNavigate(to: .guide, response: response) else { return }
        if guideStartedAt == nil { guideStartedAt = Date() }
        go(.guide)
    }

    func markStepDone(_ index: Int) {
        completedSteps.insert(index)
        persist()
    }

    func finishRepair() {
        guard FlowGate.canNavigate(to: .completion, response: response) else { return }
        projectStarted = true
        if let r = response {
            let est = impact()
            store.recordRescue(caseId: r.caseId, garment: est.garment, kilograms: est.kilograms)
        }
        persist(finished: true)
        path.append(.completion)
    }

    func impact() -> ImpactEstimator.Estimate {
        guard let r = response else { return ImpactEstimator.estimate(summary: "", segmentLabels: []) }
        return ImpactEstimator.estimate(summary: r.diagnosis.summary, segmentLabels: r.segments.map(\.label), category: r.category)
    }

    func reset() {
        analysisTask?.cancel()
        path = []
        photo = nil; note = ""; response = nil; showReview = false; showFollowUp = false
        refineMode = false; refineBusy = false; refineError = nil
        extraImages = []; answers = []; followUpUsed = false; labelImage = nil; resultPhoto = nil
        statuses = [:]; currentStep = 0; completedSteps = []; guideStartedAt = nil
        earlySegments = []; marksArrivedAt = nil; analysisError = nil; isAnalyzing = false; stageStates = [:]; groundingSeen = false
        newInfoBanner = nil; projectStarted = false; projectParked = false
        agentSteps = []; labelBusy = false; changedItemIds = []; labelBaseline = nil
        afterTask?.cancel(); afterState = .idle; afterImage = nil; afterCaseId = nil
        stepImages = [:]; stepImagePending = []; stepImageFailed = []; stepImageCaseId = nil
    }

    // MARK: Persistence

    func persist(finished: Bool = false) {
        guard let r = response else { return }
        let old = store.savedCase(r.caseId)
        let nowFinished = finished || (old?.finished ?? false)
        let c = SavedCase(id: r.caseId, createdAt: old?.createdAt ?? Date(), userNote: note, response: r,
                          shoppingStatus: statuses, currentStep: currentStep, completedSteps: completedSteps.sorted(),
                          finished: nowFinished, started: projectStarted || (old?.started ?? false), parked: projectParked || (old?.parked ?? false),
                          finishedAt: nowFinished ? (old?.finishedAt ?? Date()) : nil,
                          scenario: old?.scenario ?? (settings.demoMode ? settings.scenario.rawValue : nil))
        store.upsert(c, image: photo)
    }

    /// "Start repair" (or "Save for later"): the case becomes a project on Home.
    func startProject(parked: Bool = false) {
        projectStarted = true
        projectParked = parked
        persist()
    }

    var projects: [SavedCase] { store.cases.filter { $0.started == true || $0.finished } }
    var inProgress: [SavedCase] { projects.filter { !$0.finished } }
    var doneProjects: [SavedCase] { projects.filter(\.finished).sorted { ($0.finishedAt ?? $0.createdAt) > ($1.finishedAt ?? $1.createdAt) } }

    /// Home -> Project detail.
    func openProject(_ c: SavedCase) {
        guard store.image(for: c.id) != nil else { return }
        loadCase(c)
        path = [.project(c.id)]
    }

    private func loadCase(_ c: SavedCase) {
        guard let img = store.image(for: c.id) else { return }
        reset()
        photo = img; note = c.userNote
        response = FlowGate.sanitized(c.response)
        statuses = c.shoppingStatus; currentStep = c.currentStep; completedSteps = Set(c.completedSteps)
        projectStarted = c.started == true; projectParked = c.parked == true
        followUpUsed = true
        if settings.demoMode, let raw = c.scenario, let s = DemoScenario(rawValue: raw) { settings.scenario = s }
    }

    func open(_ c: SavedCase) {
        loadCase(c)
        if let r = response {
            switch FlowGate.destination(for: r) {
            case .block: path = [.block]
            case .diagnosis: path = [.diagnosis]
            }
        }
    }
}
