import XCTest
@testable import RepairAssistant

final class FlowGateTests: XCTestCase {
    private func full(_ mutate: (inout AnalyzeResponse) -> Void = { _ in }) throws -> AnalyzeResponse {
        var r = try Fixtures.load("textile_tear")
        mutate(&r)
        return r
    }

    func testAllowedFullCaseOpensEverything() throws {
        let r = try full()
        for route: FlowGate.Route in [.diagnosis, .decision, .shopping, .guide, .completion] {
            XCTAssertTrue(FlowGate.canNavigate(to: route, response: r), "\(route)")
        }
        XCTAssertFalse(FlowGate.canNavigate(to: .block, response: r))
        XCTAssertEqual(FlowGate.destination(for: r), .diagnosis)
    }

    func testWarnOnlyBlocksGuideAndShopping() throws {
        let r = try full { $0.riskLevel = .warnOnly }
        XCTAssertTrue(FlowGate.isBlocked(r))
        XCTAssertEqual(FlowGate.destination(for: r), .block)
        for route: FlowGate.Route in [.decision, .shopping, .guide, .completion, .diagnosis] {
            XCTAssertFalse(FlowGate.canNavigate(to: route, response: r), "\(route)")
        }
        XCTAssertTrue(FlowGate.canNavigate(to: .block, response: r))
    }

    func testProfessionalAndUnsupportedBlock() throws {
        XCTAssertTrue(FlowGate.isBlocked(try full { $0.riskLevel = .professional }))
        let u = try full { $0.category = .unsupported }   // even with risk allowed
        XCTAssertTrue(FlowGate.isBlocked(u))
        XCTAssertFalse(FlowGate.canNavigate(to: .guide, response: u))
        XCTAssertFalse(FlowGate.canNavigate(to: .shopping, response: u))
    }

    func testSafetyBlockedFlagBlocks() throws {
        let r = try full { $0.safety.blocked = true }
        XCTAssertFalse(FlowGate.guideAllowed(r))
    }

    func testNeedsMoreInfoBlocksGuide() throws {
        let r = try Fixtures.load("textile_tear_needs_label")
        XCTAssertFalse(FlowGate.guideAllowed(r))
        XCTAssertFalse(FlowGate.canNavigate(to: .guide, response: r))
        XCTAssertFalse(FlowGate.canNavigate(to: .shopping, response: r))
        XCTAssertFalse(FlowGate.canNavigate(to: .decision, response: r))
        XCTAssertTrue(FlowGate.canNavigate(to: .diagnosis, response: r))
    }

    func testSanitizeStripsGuideAndShopping() throws {
        for mutate: (inout AnalyzeResponse) -> Void in [{ $0.riskLevel = .warnOnly }, { $0.riskLevel = .professional }, { $0.category = .unsupported }, { $0.diagnosis.needsMoreInfo = true }] {
            let s = FlowGate.sanitized(try full(mutate))
            XCTAssertTrue(s.guide.steps.isEmpty)
            XCTAssertTrue(s.shoppingList.isEmpty)
        }
        let ok = FlowGate.sanitized(try full())
        XCTAssertFalse(ok.guide.steps.isEmpty)
    }

    func testNoResponseNoNavigation() {
        XCTAssertFalse(FlowGate.canNavigate(to: .guide, response: nil))
    }

    func testBlockedFixtures() throws {
        for n in ["battery_jacket", "helmet"] {
            let r = FlowGate.sanitized(try Fixtures.load(n))
            XCTAssertEqual(FlowGate.destination(for: r), .block, n)
            XCTAssertTrue(r.guide.steps.isEmpty)
        }
    }
}

final class ShoppingGateTests: XCTestCase {
    let items = [
        ShoppingItem(id: "a", name: "A", kind: .material, required: true),
        ShoppingItem(id: "b", name: "B", kind: .tool, required: true),
        ShoppingItem(id: "c", name: "C", kind: .tool, required: false),
    ]

    func testStartOnlyWhenAllRequiredHave() {
        XCTAssertFalse(ShoppingGate.canStart(items: items, statuses: [:]))
        XCTAssertFalse(ShoppingGate.canStart(items: items, statuses: ["a": .have, "b": .buy]))
        XCTAssertTrue(ShoppingGate.canStart(items: items, statuses: ["a": .have, "b": .have]))
        XCTAssertTrue(ShoppingGate.canStart(items: items, statuses: ["a": .have, "b": .have, "c": .buy]))
    }

    func testEmptyListCannotStart() { XCTAssertFalse(ShoppingGate.canStart(items: [], statuses: [:])) }

    func testRequiredOpenAndToBuy() {
        XCTAssertEqual(ShoppingGate.requiredOpen(items: items, statuses: ["a": .have]).map(\.id), ["b"])
        XCTAssertEqual(ShoppingGate.toBuy(items: items, statuses: ["c": .buy, "a": .have]).map(\.id), ["c"])
    }

    func testShareText() {
        let t = ShoppingGate.shareText(title: "Jeans", items: items, statuses: ["a": .have, "b": .buy])
        XCTAssertTrue(t.contains("[x] A"))
        XCTAssertTrue(t.contains("[ ] B"))
        XCTAssertTrue(t.contains("optional"))
    }

    func testStepConfirmationGate() throws {
        let r = try Fixtures.load("textile_tear")
        XCTAssertTrue(r.guide.steps.contains { $0.needsConfirmation })
        XCTAssertFalse(r.guide.steps[1].needsConfirmation)
    }
}

final class ImpactEstimatorTests: XCTestCase {
    func testKeywordMapping() {
        XCTAssertEqual(ImpactEstimator.estimate(summary: "Jeans mit Riss am Knie", segmentLabels: []).kilograms, 0.6)
        XCTAssertEqual(ImpactEstimator.estimate(summary: "Riss", segmentLabels: ["Jeansstoff"]).garment, "Jeans")
        XCTAssertEqual(ImpactEstimator.estimate(summary: "Pullover mit Loch", segmentLabels: []).kilograms, 0.5)
        XCTAssertEqual(ImpactEstimator.estimate(summary: "T-Shirt Naht", segmentLabels: []).kilograms, 0.2)
        XCTAssertEqual(ImpactEstimator.estimate(summary: "Jacke Reißverschluss", segmentLabels: []).kilograms, 1.0)
        XCTAssertEqual(ImpactEstimator.estimate(summary: "Kleid", segmentLabels: []).kilograms, 0.35)
        XCTAssertEqual(ImpactEstimator.estimate(summary: "Bluse", segmentLabels: []).kilograms, 0.25)
        XCTAssertEqual(ImpactEstimator.estimate(summary: "Sohle", segmentLabels: [], category: .shoe).kilograms, 0.8)
    }
    func testDefault() {
        XCTAssertEqual(ImpactEstimator.estimate(summary: "irgendwas", segmentLabels: []).kilograms, 0.4)
    }
    func testFormat() { XCTAssertEqual(ImpactEstimator.format(kg: 0.6), "0,6") }
    func testFixtureSummaryMapsToJeans() throws {
        let r = try Fixtures.load("textile_tear")
        XCTAssertEqual(ImpactEstimator.estimate(summary: r.diagnosis.summary, segmentLabels: r.segments.map(\.label)).garment, "Jeans")
    }
}
