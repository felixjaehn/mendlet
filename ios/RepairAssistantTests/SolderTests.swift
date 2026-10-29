import XCTest
@testable import RepairAssistant

@MainActor
final class SolderTests: XCTestCase {
    func testPlatineDecodesWithPolarityAndSolderOverlays() throws {
        let r = try XCTUnwrap(LiveRecordings.response(file: "platine"))
        XCTAssertEqual(r.category, .lowVoltageElectronics)
        XCTAssertEqual(r.segments.count, 7)
        XCTAssertEqual(r.segments.filter { $0.polarity == "+" }.map(\.id), ["seg_6"])
        XCTAssertEqual(r.segments.filter { $0.polarity == "-" }.map(\.id), ["seg_7"])
        XCTAssertTrue(r.segments.filter { $0.polarity != nil }.allSatisfy { $0.source == .grounding })
        XCTAssertNotNil(LiveRecordings.image(file: "platine"))
        let solder = r.guide.steps.filter { $0.overlay?.type == .solder }
        XCTAssertEqual(solder.map(\.n), [4, 5])
    }

    func testSolderOverlaysReferenceExistingSegments() throws {
        let r = try XCTUnwrap(LiveRecordings.response(file: "platine"))
        for step in r.guide.steps {
            guard let o = step.overlay, o.type == .solder else { continue }
            XCTAssertNil(o.segmentId)
            let from = try XCTUnwrap(o.fromSegmentId.flatMap { r.segment($0) })
            let to = try XCTUnwrap(o.toSegmentId.flatMap { r.segment($0) })
            XCTAssertEqual(from.prompt, "copper wire strands")
            XCTAssertNotNil(to.polarity)
            XCTAssertEqual(o.holdSeconds, 3)
            XCTAssertNotNil(SolderStyle.wire(for: from, in: r.segments), "bare end \(from.id) overlaps a wire")
        }
        // red wire goes to +
        let s4 = try XCTUnwrap(r.guide.steps.first { $0.n == 4 }?.overlay)
        let end = try XCTUnwrap(r.segment(s4.fromSegmentId ?? ""))
        let wire = try XCTUnwrap(SolderStyle.wire(for: end, in: r.segments))
        XCTAssertEqual(SolderStyle.tone(wire), .red)
        XCTAssertEqual(r.segment(s4.toSegmentId ?? "")?.polarity, "+")
    }

    func testPolarityAndOverlayDecoding() throws {
        let dec = ContractCoding.decoder()
        func seg(_ extra: String) throws -> Segment {
            try dec.decode(Segment.self, from: Data(#"{"id":"a","label":"x","kind":"part"\#(extra)}"#.utf8))
        }
        XCTAssertEqual(try seg(#","polarity":"−""#).polarity, "-")
        XCTAssertEqual(try seg(#","polarity":"-""#).polarity, "-")
        XCTAssertEqual(try seg(#","polarity":"+""#).polarity, "+")
        XCTAssertNil(try seg("").polarity)
        XCTAssertNil(try seg(#","polarity":"banana""#).polarity)
        XCTAssertNil(try seg(#","polarity":null"#).polarity)

        let ov = #"{"type":"solder","segment_id":null,"from_segment_id":"a","to_segment_id":"b","hold_seconds":2.5}"#
        let o = try dec.decode(Overlay.self, from: Data(ov.utf8))
        XCTAssertEqual(o.type, .solder); XCTAssertNil(o.segmentId)
        XCTAssertEqual(o.fromSegmentId, "a"); XCTAssertEqual(o.toSegmentId, "b"); XCTAssertEqual(o.holdSeconds, 2.5)
        // old overlay JSON still decodes
        let old = try dec.decode(Overlay.self, from: Data(#"{"type":"stitch_path","stitch_type":"darning","segment_id":"s"}"#.utf8))
        XCTAssertEqual(old.type, .stitchPath); XCTAssertNil(old.fromSegmentId); XCTAssertNil(old.holdSeconds)
    }

    func testPlatineScenarioHasNoAfterPreviewAndPolarityChip() {
        XCTAssertNil(LiveRecordings.afterImage(for: .platine))
        XCTAssertEqual(LiveRecordings.name(for: .platine), "platine")
        XCTAssertEqual(LabelPinsLayer.stripPolarity("Lötpad +"), "Lötpad")
        XCTAssertEqual(LabelPinsLayer.stripPolarity("Lötpad −"), "Lötpad")
        XCTAssertEqual(LabelPinsLayer.stripPolarity("Kabel"), "Kabel")
    }

    func testReplayPlaysPlatine() async throws {
        var got: AnalyzeResponse?
        for try await e in MockAPIClient(speed: 300).analyze(AnalyzeRequest(imageBase64: "", userNote: "", mockScenario: "platine")) {
            if case .result(let r) = e { got = r }
        }
        XCTAssertEqual(got?.segments.count, 7)
    }
}
