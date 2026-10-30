import XCTest
@testable import RepairAssistant

@MainActor
final class RecordingTests: XCTestCase {
    func testAllRecordingsDecode() throws {
        for f in ["jeans", "jeans_label", "pulli", "sneaker", "heizjacke"] {
            let r = try XCTUnwrap(LiveRecordings.response(file: f), f)
            XCTAssertFalse(r.caseId.isEmpty)
            if f == "heizjacke" { XCTAssertTrue(FlowGate.isBlocked(r)) } else {
                XCTAssertFalse(r.segments.isEmpty, f); XCTAssertFalse(r.guide.steps.isEmpty, f)
            }
        }
        XCTAssertEqual(LiveRecordings.response(file: "pulli")?.segments.filter { $0.prompt == "hole" }.count, 3)
        XCTAssertEqual(LiveRecordings.response(file: "jeans_label")?.diagnosis.labelInfo?.materials.count, 2)
        for n in ["jeans", "jeans_after", "pulli_after", "sneaker", "heizjacke", "jeans_label_photo"] { XCTAssertNotNil(LiveRecordings.image(file: n), n) }
    }

    func testReplayEmitsSegmentsAndAgentStepsBeforeResult() async throws {
        let mock = MockAPIClient(speed: 200)
        var order: [String] = []; var steps = 0
        for try await e in mock.analyze(AnalyzeRequest(imageBase64: "", userNote: "", mockScenario: "textile_tear")) {
            switch e {
            case .segments: order.append("segments")
            case .agentStep: steps += 1
            case .progress(let s, _, _): order.append(s.rawValue)
            case .result: order.append("result")
            case .grounding: break
            }
        }
        XCTAssertEqual(steps, 4)   // classify + 2 real agent steps + finish
        XCTAssertEqual(order, ["classify", "segment", "segments", "diagnose", "plan", "result"])
    }

    func testRecoveryTraceHasFailedStepAndPlaysIt() async throws {
        let rec = try XCTUnwrap(LiveRecordings.recording(for: .textileTear))
        XCTAssertEqual(rec.agentSteps.count, 3)
        XCTAssertEqual(rec.recoverySteps.count, 7)
        XCTAssertEqual(rec.recoverySteps.first?.status, .failed)
        var failed = 0, steps = 0
        for try await e in MockAPIClient(speed: 300, recovery: true).analyze(AnalyzeRequest(imageBase64: "", userNote: "", mockScenario: "textile_tear")) {
            if case .agentStep(let a) = e { steps += 1; if a.status == .failed { failed += 1 } }
        }
        XCTAssertEqual(steps, 8)
        XCTAssertEqual(failed, 1)
        XCTAssertEqual(ModelStyle.display("sam-3.1"), "SAM 3.1")
        XCTAssertEqual(ModelStyle.display("muse-spark-1.3"), "Muse Spark")
    }

    func testSliderLayersShareOneFrame() {
        let size = CGSize(width: 361, height: 361)
        let f = SliderMath.layerFrame(container: size)
        XCTAssertEqual(f, CGRect(origin: .zero, size: size))
    }

    func testRepairHintClampedTo200() throws {
        var r = try XCTUnwrap(LiveRecordings.response(file: "sneaker"))
        r.guide.steps = (1...5).map { GuideStep(n: $0, title: String(repeating: "x", count: 120), text: "") }
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { _ in }
        XCTAssertLessThanOrEqual(FlowModel.afterPreviewRequest(for: r, photo: photo).repairHint?.count ?? 0, 200)
    }

    func testGroupedLabelChip() throws {
        let r = try XCTUnwrap(LiveRecordings.response(file: "pulli"))
        let layer = LabelPinsLayer(segments: r.segments, all: r.segments, size: CGSize(width: 300, height: 400))
        let items = layer.items()
        let holes = items.filter { $0.text.contains("Löcher") }
        XCTAssertEqual(holes.count, 1)
        XCTAssertEqual(holes.first?.dots.count, 0)   // one leader to the group, no fan-out
        XCTAssertEqual(items.filter { $0.text == "Loch" }.count, 0)
    }

    func testBlockedReplayEndsEarly() async throws {
        var last: AnalyzeResponse?
        for try await e in MockAPIClient(speed: 200).analyze(AnalyzeRequest(imageBase64: "", userNote: "", mockScenario: "battery_jacket")) { if case .result(let r) = e { last = r } }
        XCTAssertTrue(FlowGate.isBlocked(try XCTUnwrap(last)))
    }

    func testSSESegmentsAndAgentStep() throws {
        let seg = try SSEDecoder.decode(SSEMessage(event: "segments", data: #"{"segments":[{"id":"seg_1","label":"Riss","kind":"damage","prompt":"rip","box":[0.1,0.1,0.2,0.2],"score":0.9}]}"#))
        if case .segments(let s)? = seg { XCTAssertEqual(s.first?.id, "seg_1") } else { XCTFail() }
        let st = try SSEDecoder.decode(SSEMessage(event: "agent_step", data: #"{"n":2,"tool":"segment","label":"SAM 3.1 sucht „rip“","model":"SAM 3.1","status":"failed","ms":2400}"#))
        if case .agentStep(let a)? = st { XCTAssertEqual(a.n, 2); XCTAssertEqual(a.status, .failed); XCTAssertEqual(a.ms, 2400); XCTAssertEqual(a.model, "SAM 3.1") } else { XCTFail() }
        XCTAssertNil(try SSEDecoder.decode(SSEMessage(event: "agent_step", data: "{}")))
    }

    func testSliderClamping() {
        XCTAssertEqual(SliderMath.clamp(-1), SliderMath.range.lowerBound)
        XCTAssertEqual(SliderMath.clamp(5), SliderMath.range.upperBound)
        XCTAssertEqual(SliderMath.clamp(.nan), 0.5)
        XCTAssertEqual(SliderMath.fraction(x: 100, width: 200), 0.5, accuracy: 0.001)
        XCTAssertEqual(SliderMath.fraction(x: -50, width: 200), SliderMath.range.lowerBound)
        XCTAssertEqual(SliderMath.fraction(x: 900, width: 200), SliderMath.range.upperBound)
        XCTAssertEqual(SliderMath.fraction(x: 10, width: 0), 0.5)
    }

    func testAfterPreviewRequestOmitsNilFields() throws {
        let photo = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        let shoe = FlowModel.afterPreviewRequest(for: try XCTUnwrap(LiveRecordings.response(file: "sneaker")), photo: photo)
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractCoding.encoder().encode(shoe)) as? [String: Any])
        XCTAssertEqual(j["category"] as? String, "shoe")
        XCTAssertNil(j["stitch_type"])
        let tex = FlowModel.afterPreviewRequest(for: try XCTUnwrap(LiveRecordings.response(file: "jeans")), photo: photo)
        let k = try XCTUnwrap(JSONSerialization.jsonObject(with: ContractCoding.encoder().encode(tex)) as? [String: Any])
        XCTAssertEqual(k["stitch_type"] as? String, "running_stitch")
        XCTAssertNil(k["category"]); XCTAssertNil(k["repair_hint"])
    }

    func testShoeStepMinutes() {
        XCTAssertEqual(ShoeStepKind.minutes(in: "Danach 10 Minuten offen trocknen"), 10)
        XCTAssertEqual(ShoeStepKind.minutes(in: "20–30 Min. aushärten"), 30)
        XCTAssertEqual(ShoeStepKind.minutes(in: "mindestens 2 Stunden"), 120)
        XCTAssertNil(ShoeStepKind.minutes(in: "Fest andrücken"))
    }

    func testRealPhotoRecordingsZoomToTheHole() throws {
        let sweater = try XCTUnwrap(LiveRecordings.recording(for: .realSweater))
        XCTAssertEqual(sweater.response.decision?.recommendation, .repairSelf)
        XCTAssertNotNil(sweater.photo); XCTAssertNotNil(sweater.after)
        let sole = try XCTUnwrap(LiveRecordings.recording(for: .realSole))
        XCTAssertEqual(sole.response.decision?.recommendation, .repairPro)
        for r in [sweater.response, sole.response] {
            let hole = try XCTUnwrap(r.segments.first(where: \.isDamage)?.normalizedBounds)
            let focus = try XCTUnwrap(DamageFocus.region(for: r.segments), "small damage zooms in")
            XCTAssertTrue(focus.contains(CGPoint(x: hole.midX, y: hole.midY)))
        }
        // Large damage (jeans tear across the knee) keeps the whole photo.
        XCTAssertNil(DamageFocus.region(for: [Segment(id: "a", label: "Tear", kind: .damage, box: [0.2, 0.2, 0.5, 0.4])]))
    }

    func testRefinedMaskReplacesOverlappingDamageAndKeepsItsId() {
        let part = Segment(id: "seg_1", label: "Sole", kind: .part, box: [0, 0, 1, 1])
        let wrong = Segment(id: "seg_2", label: "Hole", kind: .damage, box: [0.4, 0.4, 0.2, 0.2])
        let other = Segment(id: "seg_3", label: "Hole", kind: .damage, box: [0.8, 0.8, 0.1, 0.1])
        let tapped = Segment(id: "seg_1", label: "Hole", kind: .damage, box: [0.45, 0.45, 0.05, 0.05], source: .tap)
        let merged = FlowModel.merging(refined: tapped, into: [part, wrong, other])
        XCTAssertEqual(merged.map(\.id), ["seg_1", "seg_3", "seg_2"])
        XCTAssertEqual(merged.last?.source, .tap)
        let added = FlowModel.merging(refined: Segment(id: "x", label: "Hole", kind: .damage, box: [0.05, 0.05, 0.05, 0.05]), into: [part, other])
        XCTAssertEqual(added.map(\.id), ["seg_1", "seg_3", "seg_4"])  // nothing overlapped: added with a free id
    }
}
