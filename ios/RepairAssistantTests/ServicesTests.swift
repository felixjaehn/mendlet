import XCTest
@testable import RepairAssistant

@MainActor
final class ServicesTests: XCTestCase {
    func testResizerCapsLongEdge() {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000)).image { c in UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 3000, height: 2000)) }
        let r = ImageResizer.resized(big)
        XCTAssertLessThanOrEqual(max(r.size.width * r.scale, r.size.height * r.scale), 1536)
        XCTAssertEqual(r.size.width * r.scale, 1536, accuracy: 1)
        XCTAssertNotNil(ImageResizer.jpegData(big))
        let small = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100)).image { _ in }
        XCTAssertEqual(ImageResizer.resized(small).size.width * ImageResizer.resized(small).scale, 200, accuracy: 1)
    }

    func testCaseStoreRoundTripAndTrim() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cs-\(UUID().uuidString)")
        let store = CaseStore(directory: dir)
        let r = try Fixtures.load("textile_tear")
        for i in 0..<25 {
            var rr = r; rr.caseId = "c\(i)"
            store.upsert(SavedCase(id: rr.caseId, createdAt: Date(), userNote: "n", response: rr, shoppingStatus: ["item_needle": .have], currentStep: 2, completedSteps: [0, 1], finished: false))
        }
        XCTAssertEqual(store.cases.count, 20)
        store.recordRescue(caseId: "c24", garment: "Jeans", kilograms: 0.6)
        store.recordRescue(caseId: "c24", garment: "Jeans", kilograms: 0.6)   // idempotent
        XCTAssertEqual(store.rescuedCount, 1)
        let reloaded = CaseStore(directory: dir)
        XCTAssertEqual(reloaded.cases.count, 20)
        XCTAssertEqual(reloaded.cases.first?.id, "c24")
        XCTAssertEqual(reloaded.cases.first?.shoppingStatus["item_needle"], .have)
        XCTAssertEqual(reloaded.cases.first?.currentStep, 2)
        XCTAssertEqual(reloaded.rescuedKilograms, 0.6, accuracy: 0.001)
    }

    func testMockTearFlowAsksForLabelThenResolves() async throws {
        let mock = MockAPIClient(speed: 100)
        var req = AnalyzeRequest(imageBase64: "", userNote: "", mockScenario: "textile_tear")
        var last: AnalyzeResponse?
        var stages: [AnalysisStage] = []
        for try await e in mock.analyze(req) {
            switch e { case .progress(let s, _, _): stages.append(s); case .result(let r): last = r; case .grounding: break }
        }
        XCTAssertEqual(last?.diagnosis.needsMoreInfo, true)
        XCTAssertEqual(stages, [.classify, .segment, .diagnose])
        req.extraImages = [ExtraImage(purpose: .label, imageBase64: "x")]
        for try await e in mock.analyze(req) { if case .result(let r) = e { last = r } }
        XCTAssertEqual(last?.diagnosis.needsMoreInfo, false)
        XCTAssertEqual(last?.guide.steps.count, 6)
    }

    func testDemoImagesGenerate() {
        for s in DemoScenario.allCases { XCTAssertEqual(DemoImageFactory.image(for: s).size.width, 1500) }
        XCTAssertGreaterThan(DemoImageFactory.labelImage().size.width, 0)
    }
}

final class ContractExtensionTests: XCTestCase {
    func testGroundingSSEAndInstances() throws {
        let e = try SSEDecoder.decode(SSEMessage(event: "grounding", data: #"{"label":"Schadstelle genauer lokalisieren"}"#))
        if case .grounding(let l)? = e { XCTAssertEqual(l, "Schadstelle genauer lokalisieren") } else { XCTFail() }
        let r = try ContractCoding.decoder().decode(AnalyzeResponse.self, from: Data(#"{"category":"textile","risk_level":"allowed","instances":{"tear":2}}"#.utf8))
        XCTAssertEqual(r.instances?["tear"], 2)
    }

    func testTrackDecodingKeepsObjectIdString() throws {
        let json = #"{"frames":[{"index":3,"segments":[{"id":"seg_7","label":"Riss","kind":"damage","prompt":"tear","box":[0.1,0.1,0.2,0.2],"score":0.8,"object_id":"7"}]},{"index":4,"segments":[]}],"fps":10}"#
        let t = try ContractCoding.decoder().decode(TrackResponse.self, from: Data(json.utf8))
        XCTAssertEqual(t.frames.count, 2)
        XCTAssertEqual(t.frames[0].segments[0].objectId, "7")
        XCTAssertEqual(t.frames[0].segments[0].segment.id, "seg_7")
        XCTAssertEqual(t.fps, 10)
    }

    func testMockRefineTrackAfterPreview() async throws {
        let m = MockAPIClient(speed: 100)
        let s = try await m.refine(RefineRequest(imageBase64: "", points: [RefinePoint(x: 0.5, y: 0.5, label: "positive")], box: nil, label: "Riss"))
        XCTAssertEqual(s.source, .tap)
        let t = try await m.track(TrackRequest(videoBase64: "", concept: "tear"))
        XCTAssertEqual(t.frames.count, 10)
        let a = try await m.afterPreview(AfterPreviewRequest(imageBase64: "AAAA", diagnosisSummary: "x", stitchType: .ladderStitch))
        XCTAssertEqual(a.imageBase64, "AAAA")
        let enc = try ContractCoding.encoder().encode(AfterPreviewRequest(imageBase64: "A", diagnosisSummary: "x", stitchType: .darning))
        XCTAssertTrue(String(decoding: enc, as: UTF8.self).contains("diagnosis_summary"))
    }
}
