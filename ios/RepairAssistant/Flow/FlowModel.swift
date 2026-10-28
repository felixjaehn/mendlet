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
        stageStates = [:]; groundingSeen = false
        earlySegments = resetExtras ? [] : (response?.segments ?? earlySegments)
        isAnalyzing = true
        path = [.analysis]

        let request = AnalyzeRequest(
            imageBase64: ImageResizer.base64(photo), userNote: note,
            extraImages: extraImages, answers: answers, locale: "de",
            mockScenario: settings.demoMode ? settings.scenario.rawValue : (settings.scenarioRaw.isEmpty ? nil : settings.scenario.rawValue))
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
        newInfoBanner = hadLabel ? r.diagnosis.labelInfo.map { "Etikett erkannt: " + $0.materials.joined(separator: ", ") } : nil
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
        submitFollowUp(answers: qs.map { AnswerPayload(questionId: $0.id, text: "Keine Angabe") }, images: [])
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
