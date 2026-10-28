import Foundation

enum DemoScenario: String, CaseIterable, Identifiable, Sendable {
    case textileTear = "textile_tear"
    case textileHole = "textile_hole"
    case shoeSole = "shoe_sole"
    case batteryJacket = "battery_jacket"
    case helmet = "helmet"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .textileTear: "Jeans (Riss)"
        case .textileHole: "Pulli (3 Löcher)"
        case .shoeSole: "Sneaker (Sohle)"
        case .batteryJacket: "Heizjacke (Akku)"
        case .helmet: "Fahrradhelm"
        }
    }
    var subtitle: String {
        switch self {
        case .textileTear: "Flicken, optional Etikett"
        case .textileHole: "Drei Stopfstellen"
        case .shoeSole: "Kleben"
        case .batteryJacket: "Gesperrt"
        case .helmet: "Profi empfohlen"
        }
    }
    var systemImage: String {
        switch self {
        case .textileTear: "scissors"
        case .textileHole: "circle.dotted"
        case .shoeSole: "shoe"
        case .batteryJacket: "bolt.fill"
        case .helmet: "shield.lefthalf.filled"
        }
    }
    var userNote: String {
        switch self {
        case .textileTear: "Riss am Knie meiner Jeans"
        case .textileHole: "Loch am Ellbogen"
        case .shoeSole: "Sohle löst sich vorne"
        case .batteryJacket: "Reißverschluss kaputt"
        case .helmet: "Riss in der Schale"
        }
    }
}

enum Fixtures {
    static func load(_ name: String) throws -> AnalyzeResponse {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else { throw APIError.emptyResult }
        return try ContractCoding.decoder().decode(AnalyzeResponse.self, from: Data(contentsOf: url))
    }

    static func fileName(_ s: DemoScenario, labelProvided: Bool) -> String {
        switch s {
        case .textileTear: labelProvided ? "textile_tear" : "textile_tear_needs_label"
        default: s.rawValue
        }
    }

    static func response(_ s: DemoScenario, labelProvided: Bool = true) throws -> AnalyzeResponse {
        try load(fileName(s, labelProvided: labelProvided))
    }
}

struct MockAPIClient: AnalysisService {
    var speed: Double = 1
    /// "Schnell (für Videoaufnahmen)": the recorded run is compressed to about 6 s.
    var fast = false
    /// Replay the real recordings (LiveRecordings); false = old hand-written fixtures.
    var useRecordings = true

    func analyze(_ request: AnalyzeRequest) -> AsyncThrowingStream<AnalyzeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let scenario = DemoScenario(rawValue: request.mockScenario ?? "") ?? .textileTear
                    if useRecordings, let rec = LiveRecordings.recording(for: scenario) {
                        var resp = (!request.extraImages.isEmpty ? rec.labelResponse : nil) ?? rec.response
                        resp.caseId = UUID().uuidString
                        let scale = (fast ? DemoReplay.fastScale : 1) / speed
                        var clock = 0.0
                        for item in DemoReplay.timeline(name: rec.name, response: resp) {
                            let wait = (item.at - clock) * scale
                            if wait > 0 { try await Task.sleep(for: .milliseconds(Int(wait * 1000))) }
                            clock = item.at
                            continuation.yield(item.event)
                        }
                        continuation.finish(); return
                    }
                    let provided = !request.extraImages.isEmpty || !request.answers.isEmpty
                    var resp = try Fixtures.response(scenario, labelProvided: provided)
                    resp.caseId = UUID().uuidString
                    if !request.userNote.isEmpty { /* note is only sent along; fixtures stay fixed */ }

                    func pause(_ s: Double) async throws { try await Task.sleep(for: .milliseconds(Int(s * 1000 / speed))) }
                    continuation.yield(.progress(stage: .classify, label: "Objekt und Sicherheit prüfen", segments: nil))
                    try await pause(1.0)
                    if FlowGate.isBlocked(resp) {
                        continuation.yield(.progress(stage: .segment, label: "Schaden markieren", segments: resp.segments))
                        try await pause(0.7)
                        continuation.yield(.result(resp)); continuation.finish(); return
                    }
                    if scenario == .textileHole {
                        continuation.yield(.grounding(label: "Schadstelle genauer lokalisieren"))
                        try await pause(1.0)
                    }
                    continuation.yield(.progress(stage: .segment, label: "Schaden markieren", segments: resp.segments))
                    try await pause(1.5)
                    continuation.yield(.progress(stage: .diagnose, label: "Diagnose stellen", segments: nil))
                    try await pause(1.5)
                    if resp.diagnosis.needsMoreInfo {
                        continuation.yield(.result(resp)); continuation.finish(); return
                    }
                    continuation.yield(.progress(stage: .plan, label: "Reparatur planen", segments: nil))
                    try await pause(1.2)
                    continuation.yield(.result(resp))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stepHelp(_ request: StepHelpRequest) async throws -> StepHelpResponse {
        try await Task.sleep(for: .milliseconds(Int(900 / speed)))
        let t = request.issueText.lowercased()
        if ["rauch", "heiß", "heiss", "brennt", "qualm", "warm"].contains(where: { t.contains($0) }) {
            return StepHelpResponse(answer: "Das klingt nach einem Sicherheitsproblem. Höre sofort auf und arbeite nicht weiter.", retryHint: nil, escalate: true)
        }
        return StepHelpResponse(
            answer: "Das passiert oft bei diesem Schritt. Prüfe, ob der Faden zu straff sitzt, und löse die letzten zwei Stiche etwas.",
            retryHint: "Versuche es mit weniger Zug am Faden und achte auf gleichmäßige Abstände.",
            escalate: false)
    }

    func transcribe(fileURL: URL) async throws -> String {
        try await Task.sleep(for: .milliseconds(700))
        return "Der Riss ist etwa sechs Zentimeter lang und geht quer über das Knie."
    }

    func refine(_ request: RefineRequest) async throws -> Segment {
        try await Task.sleep(for: .milliseconds(Int(400 / speed)))
        let b = request.box ?? {
            let p = request.points.first { $0.label == "positive" }
            return [max(0, (p?.x ?? 0.5) - 0.1), max(0, (p?.y ?? 0.5) - 0.05), 0.2, 0.1]
        }()
        let (x, y, w, h) = (b[0], b[1], b[2], b[3])
        let ring: [[Double]] = [[x, y + h * 0.5], [x + w * 0.3, y], [x + w * 0.8, y + h * 0.1], [x + w, y + h * 0.6], [x + w * 0.5, y + h], [x + w * 0.1, y + h * 0.9]]
        return Segment(id: "seg_1", label: request.label, kind: .damage, prompt: request.label, box: b, mask: SegmentMask(points: ring), score: 0.9, source: .tap)
    }

    func track(_ request: TrackRequest) async throws -> TrackResponse {
        try await Task.sleep(for: .milliseconds(Int(500 / speed)))
        let frames = (0..<10).map { i -> TrackFrame in
            let dx = 0.3 + Double(i) * 0.02
            let ring: [[Double]] = [[dx, 0.4], [dx + 0.15, 0.4], [dx + 0.15, 0.5], [dx, 0.5]]
            let seg = Segment(id: "seg_7", label: request.concept, kind: .damage, prompt: request.concept, box: [dx, 0.4, 0.15, 0.1], mask: SegmentMask(points: ring), score: 0.9, source: .text)
            return TrackFrame(index: i, segments: [TrackedSegment(segment: seg, objectId: "7")])
        }
        return TrackResponse(frames: frames, fps: 10)
    }

    func afterPreview(_ request: AfterPreviewRequest) async throws -> AfterPreviewResponse {
        try await Task.sleep(for: .milliseconds(Int(900 / speed)))
        let raw = request.imageBase64
        let b64 = raw.range(of: "base64,").map { String(raw[$0.upperBound...]) } ?? raw
        return AfterPreviewResponse(imageBase64: b64, model: "muse-image-1.0")
    }
}
