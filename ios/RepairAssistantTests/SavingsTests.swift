import XCTest
@testable import RepairAssistant

@MainActor
final class SavingsTests: XCTestCase {
    private func make(_ rec: Recommendation, cost: [Double], new: [Double], finished: Bool = true) throws -> SavedCase {
        var r = try Fixtures.load("textile_tear")
        r.decision = Decision(recommendation: rec, reasoning: "", effort: .medium, timeMinutes: [10], costEur: cost)
        r.decision?.newPriceEur = new
        return SavedCase(id: UUID().uuidString, createdAt: Date(), userNote: "", response: r, shoppingStatus: [:], currentStep: 0, completedSteps: [], finished: finished)
    }

    func testMidpointMath() throws {
        let c = try make(.repairSelf, cost: [3, 8], new: [40, 90])
        let i = try XCTUnwrap(Savings.item(for: c))
        XCTAssertEqual(i.newPrice, 65); XCTAssertEqual(i.repairCost, 5.5); XCTAssertEqual(i.saved, 59.5)
    }
    func testMissingNewPriceSkipped() throws {
        XCTAssertNil(Savings.item(for: try make(.repairSelf, cost: [3, 8], new: [])))
        XCTAssertTrue(Savings.totals(for: [try make(.repairSelf, cost: [3, 8], new: [])]).isEmpty)
    }
    func testFlooredAtZero() throws {
        let i = try XCTUnwrap(Savings.item(for: try make(.repairPro, cost: [100, 200], new: [20, 40])))
        XCTAssertEqual(i.saved, 0)
    }
    func testMissingCostCountsAsZero() throws {
        XCTAssertEqual(try XCTUnwrap(Savings.item(for: try make(.repairSelf, cost: [], new: [50, 70]))).saved, 60)
    }
    func testMixedRecommendationsAndUnfinished() throws {
        let cases = [try make(.repairSelf, cost: [0, 10], new: [30, 50]),
                     try make(.repairPro, cost: [20, 40], new: [100, 140]),
                     try make(.replace, cost: [5, 5], new: [50, 50]),
                     try make(.repairSelf, cost: [1, 1], new: [50, 50], finished: false)]
        let t = Savings.totals(for: cases)
        XCTAssertEqual(t.repairsDone, 2); XCTAssertEqual(t.itemsKeptInUse, 2)
        XCTAssertEqual(t.moneySaved, 35 + 90)
        XCTAssertEqual(Savings.milestones(t).map(\.reached), [true, false, true])
    }
    func testEmptyState() { XCTAssertTrue(Savings.totals(for: []).isEmpty); XCTAssertEqual(Savings.totals(for: []).moneySaved, 0) }
    func testDecodesNewPrice() throws {
        let rec = try XCTUnwrap(LiveRecordings.recording(for: .realSole)?.response.decision)
        XCTAssertEqual(rec.newPriceEur, [120, 250])
    }
}
