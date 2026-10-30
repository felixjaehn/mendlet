import XCTest
@testable import RepairAssistant

final class HandsFreeCommandTests: XCTestCase {
    func testNextVariants() {
        for t in ["next", "Next!", "NEXT.", "done", "Done.", "next step", "Okay, next step please", "I'm done", "I’m done", "go next", "continue"] {
            XCTAssertEqual(HandsFreeCommand.parse(t), .next, t)
        }
    }
    func testBackVariants() {
        for t in ["back", "Back.", "previous", "Previous step", "go back", "Go back, please!", "last step"] {
            XCTAssertEqual(HandsFreeCommand.parse(t), .back, t)
        }
    }
    func testRepeatVariants() {
        for t in ["repeat", "Repeat that", "read", "Read it again.", "read this", "say it again", "Okay, repeat"] {
            XCTAssertEqual(HandsFreeCommand.parse(t), .repeatStep, t)
        }
    }
    func testStopVariants() {
        for t in ["stop", "Stop.", "exit", "Exit hands-free", "stop listening", "Quit", "hands free off"] {
            XCTAssertEqual(HandsFreeCommand.parse(t), .stop, t)
        }
    }
    func testQuestionsAreNotCommands() {
        for t in ["", "   ", "How tight should I pull the thread?", "Should I stop pulling the thread now",
                  "what does the next step look like", "is it done when the hole is closed", "can you repeat what thread to use"] {
            XCTAssertNil(HandsFreeCommand.parse(t), t)
        }
    }
}

final class VoiceActivityDetectorTests: XCTestCase {
    private let dt = 0.05

    /// Feeds `seconds` of constant level and returns every event.
    private func feed(_ vad: inout VoiceActivityDetector, level: Float, seconds: Double) -> [VoiceActivityDetector.Event] {
        var out: [VoiceActivityDetector.Event] = []
        for _ in 0..<Int((seconds / dt).rounded()) { if let e = vad.process(rms: level, dt: dt) { out.append(e) } }
        return out
    }

    func testSilenceNeverTriggersAndLearnsTheNoiseFloor() {
        var vad = VoiceActivityDetector()
        XCTAssertTrue(feed(&vad, level: 0.006, seconds: 3).isEmpty)
        XCTAssertFalse(vad.isSpeaking)
        XCTAssertEqual(vad.noiseFloor, 0.006, accuracy: 0.002)
    }

    func testSpeechStartsAfterShortDebounceAndEndsAfterSeventyMsSilence() {
        var vad = VoiceActivityDetector()
        _ = feed(&vad, level: 0.004, seconds: 1)
        let start = feed(&vad, level: 0.12, seconds: 1.0)
        XCTAssertEqual(start, [.speechStarted])
        XCTAssertTrue(vad.isSpeaking)
        // 0.6 s of silence is not enough
        XCTAssertTrue(feed(&vad, level: 0.003, seconds: 0.6).isEmpty)
        XCTAssertTrue(vad.isSpeaking)
        // ... 0.7 s is
        let end = feed(&vad, level: 0.003, seconds: 0.2)
        guard case .speechEnded(let d)? = end.first else { return XCTFail("expected speechEnded, got \(end)") }
        XCTAssertEqual(d, 1.0, accuracy: 0.15)
        XCTAssertFalse(vad.isSpeaking)
    }

    func testShortPauseInsideSpeechDoesNotEndIt() {
        var vad = VoiceActivityDetector()
        _ = feed(&vad, level: 0.12, seconds: 0.5)
        XCTAssertTrue(feed(&vad, level: 0.003, seconds: 0.5).isEmpty)
        XCTAssertTrue(feed(&vad, level: 0.12, seconds: 0.5).isEmpty)
        XCTAssertTrue(vad.isSpeaking)
    }

    func testClickIsDiscardedAndTooBriefBlipNeverStarts() {
        var vad = VoiceActivityDetector()
        XCTAssertTrue(feed(&vad, level: 0.2, seconds: 0.05).isEmpty)   // below the 90 ms debounce
        _ = feed(&vad, level: 0.003, seconds: 0.5)
        XCTAssertFalse(vad.isSpeaking)
        // starts, then stops straight away: shorter than minUtterance
        var v2 = VoiceActivityDetector()
        v2.startAfter = 0.05
        XCTAssertEqual(feed(&v2, level: 0.2, seconds: 0.05), [.speechStarted])
        XCTAssertEqual(feed(&v2, level: 0.003, seconds: 0.8), [.discarded])
    }

    func testNoiseFloorRaisesTheThreshold() {
        var vad = VoiceActivityDetector()
        _ = feed(&vad, level: 0.012, seconds: 4)          // noisy room, below the initial threshold
        XCTAssertEqual(vad.noiseFloor, 0.012, accuracy: 0.002)
        XCTAssertTrue(feed(&vad, level: 0.03, seconds: 1).isEmpty)   // 0.03 would trigger a quiet room, not this one
        XCTAssertEqual(feed(&vad, level: 0.3, seconds: 0.5), [.speechStarted])
    }

    func testVeryLongSpeechIsCutAtMaxUtterance() {
        var vad = VoiceActivityDetector()
        vad.maxUtterance = 2
        let events = feed(&vad, level: 0.2, seconds: 3)
        guard events.count >= 2, case .speechEnded(let d) = events[1] else { return XCTFail("\(events)") }
        XCTAssertEqual(events.first, .speechStarted)
        XCTAssertEqual(d, 2, accuracy: 0.1)
    }
}

final class ThinkingOrbGoldenTests: XCTestCase {
    private struct Golden: Decodable {
        struct Case: Decodable { let key: String; let state: String; let t: Double; let dotCount: Int; let dots: [Double] }
        let tolerance: Double
        let cases: [Case]
    }

    func testListeningAndWorkingMatchTheLibraryGoldenVectors() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "orbs-golden-listening-working-64", withExtension: "json"))
        let golden = try JSONDecoder().decode(Golden.self, from: Data(contentsOf: url))
        XCTAssertEqual(golden.cases.count, 8)
        for c in golden.cases {
            let state: OrbState = c.state == "listening" ? .listening : .working
            let dots = OrbEngine.frame(state, t: c.t)
            XCTAssertEqual(dots.count, c.dotCount, c.key)
            for (i, d) in dots.enumerated() where i * 6 + 5 < c.dots.count {
                let g = Array(c.dots[(i * 6)..<(i * 6 + 6)])
                let mine = [d.x, d.y, d.z, d.r, d.white, d.a]
                for (j, name) in ["x", "y", "z", "r", "white", "a"].enumerated() {
                    XCTAssertEqual(mine[j], g[j], accuracy: 1e-3, "\(c.key) dot \(i) \(name)")
                }
            }
        }
    }

    func testFramesAreFiniteAndDrawnFarToNear() {
        for state in [OrbState.listening, .working] {
            let dots = OrbEngine.frame(state, t: 12.34)
            XCTAssertFalse(dots.isEmpty)
            XCTAssertEqual(dots.map(\.z), dots.map(\.z).sorted())
            XCTAssertTrue(dots.allSatisfy { $0.x.isFinite && $0.y.isFinite && $0.r >= 0.3 })
        }
    }
}
