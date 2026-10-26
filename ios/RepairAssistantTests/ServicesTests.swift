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
            switch e { case .progress(let s, _, _): stages.append(s); case .result(let r): last = r }
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
