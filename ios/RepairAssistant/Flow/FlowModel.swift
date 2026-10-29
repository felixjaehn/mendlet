import SwiftUI
import Observation

@MainActor
@Observable
final class FlowModel {
    enum Route: Hashable { case analysis, diagnosis, decision, shopping, guide, block, completion }

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
    // Muse Image before/after
    enum AfterState: Equatable { case idle, loading, ready, unavailable }
    var afterState: AfterState = .idle
    var afterImage: UIImage?
    private var afterCaseId: String?
    private var afterTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?

    // Shopping & guide
    var statuses: [String: ItemStatus] = [:]
    var currentStep = 0
    var completedSteps: Set<Int> = []
    var guideStartedAt: Date?
    var resultPhoto: UIImage?
    var showSettings = false

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

    // MARK: Analysis

    func startAnalysis(resetExtras: Bool = true) {
        guard let photo else { return }
        if resetExtras {
            extraImages = []; answers = []; followUpUsed = false; labelImage = nil; newInfoBanner = nil
            statuses = [:]; currentStep = 0; completedSteps = []; guideStartedAt = nil
        }
        showReview = false
        showFollowUp = false
        analysisError = nil
        response = resetExtras ? nil : response
        stageStates = [:]; groundingSeen = false; agentSteps = []
        earlySegments = resetExtras ? [] : (response?.segments ?? earlySegments)
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
            if let segments, !segments.isEmpty { earlySegments = segments }
        case .grounding:
            groundingSeen = true
        case .segments(let segments):
            if !segments.isEmpty { earlySegments = segments }
        case .agentStep(let step):
            if let i = agentSteps.firstIndex(where: { $0.n == step.n }) { agentSteps[i] = step } else { agentSteps.append(step) }
            agentSteps.sort { $0.n < $1.n }
        case .result(let r):
            finish(with: FlowGate.sanitized(r))
        }
    }

    private func finish(with r: AnalyzeResponse) {
        if r.segments.isEmpty && r.diagnosis.summary.isEmpty && !FlowGate.isBlocked(r) {
            fail(APIError.emptyResult); return
        }
        for s in AnalysisStage.allCases { stageStates[s] = .done }
        response = r
        isAnalyzing = false
        let hadLabel = (labelImage != nil) && r.diagnosis.labelInfo != nil
        newInfoBanner = hadLabel ? r.diagnosis.labelInfo.map { tr("Etikett erkannt: %@", $0.materials.joined(separator: ", ")) } : nil
        if hadLabel, let base = labelBaseline { markChanged(from: base, to: r) }
        labelBaseline = nil
        persist()
        // let the last checkmark land before navigating
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
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

    func skipFollowUp() {
        let qs = response?.diagnosis.followUpQuestions ?? []
        submitFollowUp(answers: qs.map { AnswerPayload(questionId: $0.id, text: tr("Keine Angabe")) }, images: [])
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
        }
        guard route == .analysis || FlowGate.canNavigate(to: gateRoute, response: response) else { Haptics.warning(); return }
        path.append(route)
    }

    var shoppingItems: [ShoppingItem] { response?.shoppingList ?? [] }
    var canStartRepair: Bool { ShoppingGate.canStart(items: shoppingItems, statuses: statuses) }

    func setStatus(_ item: ShoppingItem, _ status: ItemStatus) {
        statuses[item.id] = (statuses[item.id] == status) ? nil : status
        Haptics.selection()
        persist()
    }

    func startRepair() {
        guard canStartRepair else { return }
        if guideStartedAt == nil { guideStartedAt = Date() }
        go(.guide)
    }

    func markStepDone(_ index: Int) {
        completedSteps.insert(index)
        persist()
    }

    func finishRepair() {
        guard FlowGate.canNavigate(to: .completion, response: response) else { return }
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
        extraImages = []; answers = []; followUpUsed = false; labelImage = nil; resultPhoto = nil
        statuses = [:]; currentStep = 0; completedSteps = []; guideStartedAt = nil
        earlySegments = []; analysisError = nil; isAnalyzing = false; stageStates = [:]; groundingSeen = false
        newInfoBanner = nil
        agentSteps = []; labelBusy = false; changedItemIds = []; labelBaseline = nil
        afterTask?.cancel(); afterState = .idle; afterImage = nil; afterCaseId = nil
    }

    // MARK: Persistence

    func persist(finished: Bool = false) {
        guard let r = response else { return }
        let c = SavedCase(id: r.caseId, createdAt: store.savedCase(r.caseId)?.createdAt ?? Date(), userNote: note, response: r,
                          shoppingStatus: statuses, currentStep: currentStep, completedSteps: completedSteps.sorted(),
                          finished: finished || (store.savedCase(r.caseId)?.finished ?? false))
        store.upsert(c, image: photo)
    }

    func open(_ c: SavedCase) {
        guard let img = store.image(for: c.id) else { return }
        reset()
        photo = img; note = c.userNote
        response = FlowGate.sanitized(c.response)
        statuses = c.shoppingStatus; currentStep = c.currentStep; completedSteps = Set(c.completedSteps)
        followUpUsed = true
        if let r = response {
            switch FlowGate.destination(for: r) {
            case .block: path = [.block]
            case .diagnosis: path = [.diagnosis]
            }
        }
    }
}
