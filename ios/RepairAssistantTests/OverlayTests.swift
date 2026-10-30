import XCTest
@testable import RepairAssistant

final class OverlayTests: XCTestCase {
    func testRingsAndSourceDecode() throws {
        let json = """
        {"id":"a","label":"Loch","kind":"damage","score":0.9,"source":"grounding",
         "mask":{"points":[],"rings":[{"points":[[0,0],[1,0],[1,1],[0,1]],"hole":false},{"points":[[0.4,0.4],[0.6,0.4],[0.6,0.6]],"hole":true}]}}
        """
        let s = try JSONDecoder().decode(Segment.self, from: Data(json.utf8))
        XCTAssertEqual(s.source, .grounding)
        XCTAssertEqual(s.source?.badge, "Spark → SAM")
        XCTAssertEqual(s.ringPolygons.count, 2)
        XCTAssertTrue(s.ringPolygons[1].hole)
        XCTAssertEqual(s.polygon.count, 4)
    }

    func testLegacyPointsAndUnknownSource() throws {
        let json = #"{"id":"a","label":"x","kind":"part","source":"weird","mask":{"points":[[0,0],[1,0],[1,1]]}}"#
        let s = try JSONDecoder().decode(Segment.self, from: Data(json.utf8))
        XCTAssertNil(s.source)
        XCTAssertEqual(s.ringPolygons.count, 1)
    }

    func testLabelsDoNotOverlap() {
        let size = CGSize(width: 300, height: 300)
        let items = (0..<4).map { i in
            LabelPlacer.Item(id: "\(i)", text: "Label \(i)", score: "90 %", badge: "SAM 3.1",
                             anchor: CGPoint(x: 150, y: 150), bounds: CGRect(x: 140, y: 140, width: 20, height: 20),
                             width: 120, large: false)
        }
        let placed = LabelPlacer.place(items, in: size)
        XCTAssertEqual(placed.count, 4)
        for i in placed.indices { for j in placed.indices where j > i { XCTAssertFalse(placed[i].rect.intersects(placed[j].rect)) } }
    }

    func testDimensionOnlyWithScale() {
        let ring = [[0.3, 0.5], [0.7, 0.5], [0.7, 0.55], [0.3, 0.55]]
        let damage = Segment(id: "d", label: "Riss", kind: .damage, mask: SegmentMask(points: ring), score: 0.9)
        let size = CGSize(width: 400, height: 400)
        XCTAssertNil(DamageDimension.layout(segments: [damage], size: size))
        let part = Segment(id: "p", label: "Jeansstoff", kind: .part, box: [0.1, 0.2, 0.8, 0.6])
        let l = DamageDimension.layout(segments: [damage, part], size: size)
        XCTAssertEqual(l?.cm ?? 0, 10, accuracy: 0.6)
    }
}

final class CureActivityTests: XCTestCase {
    func testStateProgressAndRemaining() {
        let t0 = Date(timeIntervalSince1970: 1000)
        let s = CureActivityController.state(seconds: 600, from: t0)
        XCTAssertEqual(s.total, 600)
        XCTAssertEqual(s.remaining(at: t0.addingTimeInterval(150)), 450)
        XCTAssertEqual(s.progress(at: t0.addingTimeInterval(300)), 0.5, accuracy: 0.001)
        XCTAssertEqual(s.progress(at: t0.addingTimeInterval(9999)), 1)
        XCTAssertEqual(s.range.lowerBound, t0)
    }

    func testAttributesRoundTrip() throws {
        let a = CureActivityAttributes(itemName: "Sneaker", stepTitle: "Press", kind: .solder)
        let d = try JSONEncoder().encode(a)
        XCTAssertEqual(try JSONDecoder().decode(CureActivityAttributes.self, from: d).kind, .solder)
    }
}
