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
        case .textileTear: "Jeans mit Riss"
        case .textileHole: "Pullover mit Loch"
        case .shoeSole: "Sohle löst sich"
        case .batteryJacket: "Heizjacke mit Akku"
        case .helmet: "Fahrradhelm"
        }
    }
    var subtitle: String {
        switch self {
        case .textileTear: "Rückfrage, Leiterstich"
        case .textileHole: "Stopfgitter"
        case .shoeSole: "Kleben"
        case .batteryJacket: "Sicherheitssperre"
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

    func analyze(_ request: AnalyzeRequest) -> AsyncThrowingStream<AnalyzeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let scenario = DemoScenario(rawValue: request.mockScenario ?? "") ?? .textileTear
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
}
