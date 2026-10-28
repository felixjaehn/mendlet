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
}

enum LiveRecordings {
    static let chipText = "Demo · echte Modellantworten vom 28.10."

    static func name(for s: DemoScenario) -> String? {
        switch s {
        case .textileTear: "jeans"
        case .textileHole: "pulli"
        case .shoeSole: "sneaker"
        case .batteryJacket: "heizjacke"
        case .helmet: nil
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var images: [String: UIImage] = [:]

    static func url(_ file: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: file, withExtension: ext, subdirectory: "LiveRecordings") ?? Bundle.main.url(forResource: file, withExtension: ext)
    }

    static func response(file: String) -> AnalyzeResponse? {
        guard let u = url(file, "json"), let d = try? Data(contentsOf: u) else { return nil }
        return try? ContractCoding.decoder().decode(AnalyzeResponse.self, from: d)
    }

    static func image(file: String) -> UIImage? {
        lock.lock(); defer { lock.unlock() }
        if let i = images[file] { return i }
        guard let u = url(file, "jpg"), let i = UIImage(contentsOfFile: u.path) else { return nil }
        images[file] = i
        return i
    }

    static func recording(for s: DemoScenario) -> LiveRecording? {
        guard let n = name(for: s), let r = response(file: n) else { return nil }
        let isJeans = n == "jeans"
        return LiveRecording(name: n, response: r, photo: image(file: n), after: image(file: n + "_after"),
                             labelResponse: isJeans ? response(file: "jeans_label") : nil,
                             labelPhoto: isJeans ? image(file: "jeans_label_photo") : nil)
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
enum DemoReplay {
    /// Fast mode compresses the ~28 s of the real run to about 6 s.
    static let fastScale = 0.21

    struct Step { var tool: String; var model: String; var label: String; var ms: Int }

    static func segmentSteps(for name: String) -> [Step] {
        switch name {
        case "jeans":
            [Step(tool: "segment", model: "SAM 3.1", label: "SAM 3.1 sucht „rip“", ms: 2400),
             Step(tool: "ground", model: "Muse Spark", label: "Muse Spark lokalisiert Schaden", ms: 2500),
             Step(tool: "segment", model: "SAM 3.1", label: "SAM 3.1 segmentiert Box", ms: 2200),
             Step(tool: "verify", model: "Muse Spark", label: "Muse Spark prüft Maske ✓", ms: 2400)]
        case "pulli":
            [Step(tool: "segment", model: "SAM 3.1", label: "SAM 3.1 sucht „hole“", ms: 3000),
             Step(tool: "segment", model: "SAM 3.1", label: "SAM 3.1 sucht „rip“", ms: 2600),
             Step(tool: "verify", model: "Muse Spark", label: "Muse Spark prüft 3 Masken ✓", ms: 3200)]
        case "sneaker":
            [Step(tool: "segment", model: "SAM 3.1", label: "SAM 3.1 sucht „detached sole“", ms: 3000),
             Step(tool: "segment", model: "SAM 3.1", label: "SAM 3.1 sucht „seam“", ms: 2600),
             Step(tool: "verify", model: "Muse Spark", label: "Muse Spark prüft Maske ✓", ms: 3000)]
        default: []
        }
    }

    /// (seconds from start, event). Blocked cases end after the safety check.
    static func timeline(name: String, response r: AnalyzeResponse) -> [(at: Double, event: AnalyzeEvent)] {
        var t: [(at: Double, event: AnalyzeEvent)] = []
        t.append((0, .progress(stage: .classify, label: "Objekt und Sicherheit prüfen", segments: nil)))
        t.append((2.8, .agentStep(AgentStep(n: 1, tool: "classify", label: "Muse Spark prüft Objekt und Sicherheit", model: "Muse Spark", ms: 2800))))
        if FlowGate.isBlocked(r) {
            t.append((3.0, .result(r)))
            return t
        }
        t.append((3.0, .progress(stage: .segment, label: "Schaden markieren", segments: nil)))
        let steps = segmentSteps(for: name)
        let span = 12.4 - 3.0
        for (i, s) in steps.enumerated() {
            let at = 3.0 + span * Double(i + 1) / Double(max(steps.count, 1))
            t.append((at, .agentStep(AgentStep(n: i + 2, tool: s.tool, label: s.label, model: s.model, ms: s.ms))))
        }
        t.append((13.0, .segments(r.segments)))
        t.append((13.0, .progress(stage: .diagnose, label: "Diagnose stellen", segments: nil)))
        t.append((20.5, .progress(stage: .plan, label: "Reparatur planen", segments: nil)))
        t.append((28.0, .agentStep(AgentStep(n: steps.count + 2, tool: "plan", label: "Muse Wonder erstellt Plan", model: "Muse Wonder", ms: 15000))))
        t.append((28.2, .result(r)))
        return t
    }
}
