import UIKit

/// Real proxy answers (Meta Model API, 28.10.2026) bundled in `Resources/LiveRecordings/`. The demo mode replays them.
struct LiveRecording: @unchecked Sendable {
    let name: String
    let response: AnalyzeResponse
    let photo: UIImage?
    /// Muse Image after-preview (nil for the sneaker: none was recorded).
    let after: UIImage?
    /// Second analysis with the label photo (jeans only).
    let labelResponse: AnalyzeResponse?
    let labelPhoto: UIImage?
    /// Real agent tool calls (jeans_agent.json) and the real run with SAM failure + recovery.
    var agentSteps: [AgentStep] = []
    var recoverySteps: [AgentStep] = []
}

/// `jeans_agent.json` / `jeans_agent_recovery_trace.json`: {recorded, agent_steps, result?}
struct AgentEnvelope: Decodable {
    var agentSteps: [AgentStep]
    var result: AnalyzeResponse?
}

enum LiveRecordings {
    static var chipText: String { tr("Demo · echte Modellantworten vom 28.10.") }

    static func name(for s: DemoScenario) -> String? {
        switch s {
        case .textileTear: "jeans"
        case .textileHole: "pulli"
        case .shoeSole: "sneaker"
        case .batteryJacket: "heizjacke"
        case .helmet: nil
        case .platine: "platine"
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var images: [String: UIImage] = [:]

    static func url(_ file: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: file, withExtension: ext, subdirectory: "LiveRecordings") ?? Bundle.main.url(forResource: file, withExtension: ext)
    }

    /// Optional English recordings sit next to the German ones as `<case>.en.json` (e.g. `jeans.en.json`).
    /// In English mode an existing `.en` file wins; otherwise the German recording is used. `exists` is injectable for tests.
    static func localizedJSONName(_ file: String, language: String = Lang.shared.code, exists: (String) -> Bool = { url($0, "json") != nil }) -> String {
        guard language == "en", !file.hasSuffix(".en") else { return file }
        return exists(file + ".en") ? file + ".en" : file
    }

    static func response(file: String) -> AnalyzeResponse? {
        guard let u = url(localizedJSONName(file), "json"), let d = try? Data(contentsOf: u) else { return nil }
        return try? ContractCoding.decoder().decode(AnalyzeResponse.self, from: d)
    }

    static func image(file: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let i = images[file] { return i }
        guard let u = url(file, "jpg"), let i = UIImage(contentsOfFile: u.path) else { return nil }
        images[file] = i
        return i
    }

    static func envelope(file: String) -> AgentEnvelope? {
        guard let u = url(localizedJSONName(file), "json"), let d = try? Data(contentsOf: u) else { return nil }
        return try? ContractCoding.decoder().decode(AgentEnvelope.self, from: d)
    }

    static func recording(for s: DemoScenario) -> LiveRecording? {
        guard let n = name(for: s), var r = response(file: n) else { return nil }
        let isJeans = n == "jeans"
        let agent = isJeans ? envelope(file: "jeans_agent") : nil
        // The agent run carries its own (German) result; it must not replace an English `<case>.en.json`.
        let englishBase = localizedJSONName(n) != n, englishAgent = localizedJSONName("jeans_agent") != "jeans_agent"
        if let res = agent?.result, englishAgent || !englishBase { r = res }
        return LiveRecording(name: n, response: r, photo: image(file: n), after: image(file: n + "_after"),
                             labelResponse: isJeans ? response(file: "jeans_label") : nil,
                             labelPhoto: isJeans ? image(file: "jeans_label_photo") : nil,
                             agentSteps: agent?.agentSteps ?? [],
                             recoverySteps: isJeans ? (envelope(file: "jeans_agent_recovery_trace")?.agentSteps ?? []) : [])
    }

    static func photo(for s: DemoScenario) -> UIImage? { name(for: s).flatMap { image(file: $0) } }
    static func afterImage(for s: DemoScenario) -> UIImage? { name(for: s).flatMap { image(file: $0 + "_after") } }
}

/// Demo photos: the recorded real photo, else the procedural image.
enum DemoPhotos {
    static func imageAsync(for s: DemoScenario) async -> UIImage {
        if let p = LiveRecordings.photo(for: s) { return p }
        return await DemoImageFactory.imageAsync(for: s)
    }
}

/// Timeline of a recorded analysis, played back with realistic timing (seconds at normal speed).
/// Agent steps are only the REAL recorded ones (plus the classify step); scenarios without a recorded trace show none.
enum DemoReplay {
    /// Fast mode compresses the run to about 6 s.
    static let fastScale = 0.21

    /// (seconds from start, event). Blocked cases end after the safety check.
    static func timeline(name: String, response r: AnalyzeResponse, steps: [AgentStep] = []) -> [(at: Double, event: AnalyzeEvent)] {
        var t: [(at: Double, event: AnalyzeEvent)] = []
        t.append((0, .progress(stage: .classify, label: tr("Objekt und Sicherheit prüfen"), segments: nil)))
        t.append((2.8, .agentStep(AgentStep(n: 1, tool: "classify", label: tr("Muse Spark prüft Objekt und Sicherheit"), model: "muse-spark-1.3", ms: 2800))))
        if FlowGate.isBlocked(r) {
            t.append((3.0, .result(r)))
            return t
        }
        t.append((3.0, .progress(stage: .segment, label: tr("Schaden markieren"), segments: nil)))
        var clock = 3.0
        var n = 1
        for s in steps where s.tool != "finish" {
            clock += Double(max(s.ms, 300)) / 1000
            n += 1
            var c = s; c.n = n
            t.append((clock, .agentStep(c)))
        }
        let segEnd = steps.isEmpty ? 12.4 : clock + 0.3
        if let fin = steps.first(where: { $0.tool == "finish" }) {
            var c = fin; c.n = n + 1
            t.append((segEnd, .agentStep(c)))
        }
        t.append((segEnd + 0.4, .segments(r.segments)))
        t.append((segEnd + 0.4, .progress(stage: .diagnose, label: tr("Diagnose stellen"), segments: nil)))
        t.append((segEnd + 7.5, .progress(stage: .plan, label: tr("Reparatur planen"), segments: nil)))
        t.append((segEnd + 15, .result(r)))
        return t
    }
}
