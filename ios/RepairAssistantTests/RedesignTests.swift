import XCTest
@testable import RepairAssistant

final class RedesignTests: XCTestCase {
    func testCopyPolishRemovesHedgesAndCapitalizes() {
        XCTAssertEqual(CopyPolish.sentence("small hole in presumably grey knit"), "Small hole in grey knit.")
        XCTAssertEqual(CopyPolish.sentence("Assumed leather outsole from the photo."), "")
        XCTAssertEqual(CopyPolish.sentence("The knit looks intact."), "The knit is intact.")
        XCTAssertEqual(CopyPolish.sentence("Kleines Loch", english: false), "Kleines Loch")
        XCTAssertEqual(CopyPolish.text("Likely a hole. Probably old."), "A hole. Old.")
    }

    func testHeadlineAndBodySplit() {
        let t = CopyPolish.headlineAndBody("Small hole in grey knit. The surrounding knit is intact.")
        XCTAssertEqual(t.headline, "Small hole in grey knit.")
        XCTAssertEqual(t.body, "The surrounding knit is intact.")
    }

    func testDoneWhenSplit() {
        let a = DoneWhenLine.split("Lay it flat. Done when the edges lie flat.")
        XCTAssertEqual(a.body, "Lay it flat.")
        XCTAssertEqual(a.doneWhen, "Done when the edges lie flat.")
        let b = DoneWhenLine.split("Trim fuzz. End state: No threads stick out.")
        XCTAssertEqual(b.doneWhen, "Done when no threads stick out.")
        XCTAssertNil(DoneWhenLine.split("Just do it.").doneWhen)
    }

    func testMistakeSeparator() {
        XCTAssertEqual(CopyPolish.mistake("Cutting too deep - trim only fluff"), "Cutting too deep. Trim only fluff.")
    }

    func testProjectTitle() {
        XCTAssertEqual(ProjectTitle.title(summary: "Small hole in grey knit sweater. Knit is intact."), "Grey knit sweater")
        XCTAssertEqual(ProjectTitle.title(summary: "Detached front sole on white sneaker."), "White sneaker")
        XCTAssertEqual(ProjectTitle.title(summary: "Hole in worn leather shoe sole."), "Leather shoe sole")
    }

    func testMaskSimplifyReducesAndStaysClosed() {
        let ring = (0..<200).map { i -> CGPoint in
            let a = Double(i) / 200 * 2 * .pi
            return CGPoint(x: 0.5 + 0.2 * cos(a), y: 0.5 + 0.2 * sin(a))
        }
        let simple = MaskPath.simplify(ring)
        XCTAssertLessThan(simple.count, ring.count)
        XCTAssertGreaterThanOrEqual(simple.count, 3)
        let c = MaskPath.contours(for: ring)
        XCTAssertEqual(c.count, 1)
        XCTAssertTrue(c[0].closed)
        XCTAssertEqual(c[0].points.first?.y ?? 1, 0.3, accuracy: 0.02)  // starts at the top-most point
    }

    func testCopyPolishDropsSafetyBoilerplate() {
        XCTAssertEqual(CopyPolish.text("Wear gloves and ventilate the room. Apply a thin 1 mm layer of shoe adhesive."),
                       "Apply a thin 1 mm layer of shoe adhesive.")
        XCTAssertEqual(CopyPolish.text("Ventilate the room. Keep your fingers clear. Trim the loose ends."), "Trim the loose ends.")
    }
}
