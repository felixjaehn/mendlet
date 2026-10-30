import XCTest
@testable import RepairAssistant

final class StitchPathPlannerTests: XCTestCase {
    private func rect(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) -> [CGPoint] {
        [CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y0), CGPoint(x: x1, y: y1), CGPoint(x: x0, y: y1)]
    }

    func testStraightThinRectangle() {
        let plan = StitchPathPlanner.plan(polygon: rect(0.1, 0.49, 0.9, 0.51), box: nil, stitchType: .ladderStitch)
        XCTAssertEqual(plan.kind, .stitches)
        XCTAssertFalse(plan.isFallback)
        // near-straight centerline at y = 0.5
        for p in plan.centerline { XCTAssertEqual(p.y, 0.5, accuracy: 0.012) }
        // spans most of the length
        let xs = plan.centerline.map(\.x)
        XCTAssertLessThan(xs.min()!, 0.2); XCTAssertGreaterThan(xs.max()!, 0.8)
        // monotonic arc length: cumulative length strictly increases, stitches progress along x
        var cum: CGFloat = 0
        for i in 1..<plan.centerline.count {
            let d = hypot(plan.centerline[i].x - plan.centerline[i - 1].x, plan.centerline[i].y - plan.centerline[i - 1].y)
            XCTAssertGreaterThan(d, 0); cum += d
        }
        XCTAssertGreaterThan(cum, 0.6)
        let sx = plan.stitches.map(\.position.x)
        let ordered = sx == sx.sorted() || sx == sx.sorted(by: >)
        XCTAssertTrue(ordered)
        // alternating sides
        for (i, s) in plan.stitches.enumerated() {
            XCTAssertEqual(s.side, i % 2 == 0 ? 1 : -1)
            XCTAssertEqual(s.index, i + 1)
        }
        let above = plan.stitches.map { $0.position.y > 0.5 }
        for i in 1..<above.count { XCTAssertNotEqual(above[i], above[i - 1]) }
    }

    func testStitchCountDependsOnLengthAndIsClamped() {
        let short = StitchPathPlanner.plan(polygon: rect(0.45, 0.49, 0.55, 0.51), box: nil, stitchType: .ladderStitch)
        let mid = StitchPathPlanner.plan(polygon: rect(0.25, 0.49, 0.75, 0.51), box: nil, stitchType: .ladderStitch)
        let long = StitchPathPlanner.plan(polygon: rect(0.02, 0.49, 0.98, 0.51), box: nil, stitchType: .ladderStitch)
        XCTAssertEqual(short.stitches.count, 6)
        XCTAssertGreaterThan(mid.stitches.count, 6)
        XCTAssertLessThanOrEqual(mid.stitches.count, long.stitches.count)
        XCTAssertLessThanOrEqual(long.stitches.count, 18)
        XCTAssertGreaterThan(long.stitches.count, mid.stitches.count)
    }

    func testCurvedBandFollowsCurve() {
        func curve(_ t: CGFloat) -> CGPoint { CGPoint(x: 0.15 + 0.7 * t, y: 0.5 - 0.2 * sin(.pi * t)) }
        var up: [CGPoint] = [], lo: [CGPoint] = []
        for i in 0...40 {
            let t = CGFloat(i) / 40, c = curve(t)
            up.append(CGPoint(x: c.x, y: c.y - 0.015)); lo.append(CGPoint(x: c.x, y: c.y + 0.015))
        }
        let plan = StitchPathPlanner.plan(polygon: up + lo.reversed(), box: nil, stitchType: .runningStitch)
        XCTAssertEqual(plan.kind, .stitches)
        func distToCurve(_ p: CGPoint) -> CGFloat { (0...400).map { hypot(curve(CGFloat($0) / 400).x - p.x, curve(CGFloat($0) / 400).y - p.y) }.min()! }
        for p in plan.centerline { XCTAssertLessThan(distToCurve(p), 0.02) }
        let ys = plan.centerline.map(\.y)
        XCTAssertGreaterThan(ys.max()! - ys.min()!, 0.1, "centerline must bend, not be a straight chord")
    }

    func testAspectRatioKeepsGeometryUndistorted() {
        // In a 2:1 image a square-ish thin band keeps normalized coordinates inside 0..1
        let plan = StitchPathPlanner.plan(polygon: rect(0.1, 0.48, 0.9, 0.52), box: nil, stitchType: .ladderStitch, aspect: 0.5)
        for s in plan.stitches { XCTAssertTrue((0...1).contains(s.position.x) && (0...1).contains(s.position.y)) }
    }

    func testDarningGridAnchorsOutsideBlob() {
        var blob: [CGPoint] = []
        for i in 0..<28 {
            let th = 2 * CGFloat.pi * CGFloat(i) / 28
            let k = 1 + 0.15 * sin(3 * th)
            blob.append(CGPoint(x: 0.5 + 0.1 * k * cos(th), y: 0.5 + 0.07 * k * sin(th)))
        }
        let plan = StitchPathPlanner.plan(polygon: blob, box: nil, stitchType: .darning)
        XCTAssertEqual(plan.kind, .darning)
        XCTAssertGreaterThan(plan.firstDirectionCount, 0)
        XCTAssertLessThan(plan.firstDirectionCount, plan.gridLines.count)
        for line in plan.gridLines {
            XCTAssertEqual(line.count, 2)
            for p in line { XCTAssertFalse(StitchPathPlanner.pointInPolygon(p, blob), "\(p) must anchor on intact fabric") }
            let m = CGPoint(x: (line[0].x + line[1].x) / 2, y: (line[0].y + line[1].y) / 2)
            XCTAssertTrue(StitchPathPlanner.pointInPolygon(m, blob))
        }
        let f = plan.gridLines[0], s = plan.gridLines[plan.firstDirectionCount]
        let d1 = CGPoint(x: f[1].x - f[0].x, y: f[1].y - f[0].y), d2 = CGPoint(x: s[1].x - s[0].x, y: s[1].y - s[0].y)
        let cosA = abs(d1.x * d2.x + d1.y * d2.y) / (hypot(d1.x, d1.y) * hypot(d2.x, d2.y))
        XCTAssertLessThan(cosA, 0.15)
    }

    // MARK: Real jeans mask (LiveRecordings/jeans.json, 1152x1536)

    private func jeansPolygon() throws -> [CGPoint] {
        let r = try XCTUnwrap(LiveRecordings.response(file: "jeans"))
        return try XCTUnwrap(r.segments.first { $0.isDamage }).polygon
    }

    private func distToPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> CGFloat {
        var best = CGFloat.infinity
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let dx = b.x - a.x, dy = b.y - a.y
            let l2 = max(dx * dx + dy * dy, 1e-12)
            let t = min(1, max(0, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
            best = min(best, hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t)))
        }
        return best
    }

    func testJeansDarningGeometry() throws {
        let aspect: CGFloat = 0.75
        let poly = try jeansPolygon()
        let plan = StitchPathPlanner.plan(polygon: poly, box: nil, stitchType: .darning, aspect: aspect)
        XCTAssertEqual(plan.kind, .darning)
        // aspect-corrected space for angle/length checks
        func sp(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * aspect, y: p.y) }
        let sPoly = poly.map(sp)
        // centroid + principal axis (rasterised)
        var cells: [CGPoint] = []
        let xs = sPoly.map(\.x), ys = sPoly.map(\.y)
        let x0 = xs.min()!, x1 = xs.max()!, y0 = ys.min()!, y1 = ys.max()!
        for iy in 0..<120 { for ix in 0..<120 {
            let p = CGPoint(x: x0 + (x1 - x0) * (CGFloat(ix) + 0.5) / 120, y: y0 + (y1 - y0) * (CGFloat(iy) + 0.5) / 120)
            if StitchPathPlanner.pointInPolygon(p, sPoly) { cells.append(p) }
        } }
        let cx = cells.map(\.x).reduce(0, +) / CGFloat(cells.count), cy = cells.map(\.y).reduce(0, +) / CGFloat(cells.count)
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in cells { sxx += (p.x - cx) * (p.x - cx); syy += (p.y - cy) * (p.y - cy); sxy += (p.x - cx) * (p.y - cy) }
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        let axis = CGPoint(x: cos(theta), y: sin(theta))
        let major = hypot(x1 - x0, y1 - y0)

        let warp = Array(plan.gridLines.prefix(plan.firstDirectionCount))
        XCTAssertTrue((6...9).contains(warp.count), "warp count \(warp.count)")
        for line in warp {
            let a = sp(line[0]), b = sp(line[1])
            let len = hypot(b.x - a.x, b.y - a.y)
            let cosA = abs((b.x - a.x) * axis.x + (b.y - a.y) * axis.y) / len
            XCTAssertGreaterThan(cosA, cos(5 * .pi / 180), "warp line not parallel to principal axis")
            for e in line {
                XCTAssertFalse(StitchPathPlanner.pointInPolygon(sp(e), sPoly), "endpoint \(e) inside mask")
                XCTAssertLessThan(distToPolygon(sp(e), sPoly), 0.25 * major, "endpoint too far from the mask")
            }
        }
        // grid centroid on the mask centroid
        let mids = plan.gridLines.map { CGPoint(x: ($0[0].x + $0[1].x) / 2 * aspect, y: ($0[0].y + $0[1].y) / 2) }
        let gx = mids.map(\.x).reduce(0, +) / CGFloat(mids.count), gy = mids.map(\.y).reduce(0, +) / CGFloat(mids.count)
        XCTAssertLessThan(hypot(gx - cx, gy - cy), 0.05 * major)

        // U-turns never cut through the hole
        let turns = (plan.warpStrokes + plan.weftStrokes).filter(\.isTurn)
        XCTAssertGreaterThan(turns.count, 5)
        for t in turns { for p in t.points { XCTAssertFalse(StitchPathPlanner.pointInPolygon(sp(p), sPoly), "U-turn crosses the mask at \(p)") } }
        // every needle jump between consecutive strokes is continuous
        for strokes in [plan.warpStrokes, plan.weftStrokes] {
            for i in 1..<strokes.count {
                let a = strokes[i - 1].points.last!, b = strokes[i].points.first!
                XCTAssertLessThan(hypot(a.x - b.x, a.y - b.y), 1e-6)
            }
        }
        // weft is perpendicular to warp
        let w = plan.gridLines[plan.firstDirectionCount]
        let wa = sp(w[0]), wb = sp(w[1])
        XCTAssertLessThan(abs((wb.x - wa.x) * axis.x + (wb.y - wa.y) * axis.y) / hypot(wb.x - wa.x, wb.y - wa.y), 0.09)
    }

    func testFixturePolygonsProducePlans() throws {
        let tear = try Fixtures.load("textile_tear").segments[0]
        let plan = StitchPathPlanner.plan(for: tear, stitchType: .ladderStitch, aspect: 0.8)
        XCTAssertEqual(plan.kind, .stitches)
        XCTAssertGreaterThanOrEqual(plan.stitches.count, 6)
        let hole = try Fixtures.load("textile_hole").segments[0]
        XCTAssertEqual(StitchPathPlanner.plan(for: hole, stitchType: .darning, aspect: 0.8).kind, .darning)
    }

    func testFallbackBoxDiagonal() {
        let plan = StitchPathPlanner.plan(polygon: [], box: CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.2), stitchType: .ladderStitch)
        XCTAssertTrue(plan.isFallback)
        XCTAssertEqual(plan.kind, .stitches)
        XCTAssertEqual(plan.centerline.first!.x, 0.2, accuracy: 0.01)
        XCTAssertEqual(plan.centerline.last!.y, 0.5, accuracy: 0.01)
    }

    func testDegenerateInputsDoNotCrash() {
        let nan = CGFloat.nan
        let cases: [[CGPoint]] = [
            [], [CGPoint(x: 0.5, y: 0.5)], [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.9, y: 0.9)],
            [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.5)],
            [CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.9, y: 0.9)],   // collinear
            [CGPoint(x: nan, y: 0.2), CGPoint(x: 0.3, y: nan), CGPoint(x: 0.5, y: 0.5)],
            rect(0.5, 0.5, 0.5001, 0.5001),                                                  // tiny
            rect(-5, -5, 5, 5),                                                              // huge
        ]
        for c in cases {
            for t in [StitchType.ladderStitch, .darning, .runningStitch, .whipStitch] {
                for box in [nil, CGRect(x: 0, y: 0, width: 0, height: 0), CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.3)] {
                    _ = StitchPathPlanner.plan(polygon: c, box: box, stitchType: t, aspect: 0.8)
                    _ = StitchPathPlanner.plan(polygon: c, box: box, stitchType: t, aspect: 0)
                }
            }
        }
    }

    func testAspectFitMapping() {
        let r = AspectFit.rect(content: CGSize(width: 800, height: 1000), in: CGSize(width: 400, height: 400))
        XCTAssertEqual(r.height, 400, accuracy: 0.001)
        XCTAssertEqual(r.width, 320, accuracy: 0.001)
        XCTAssertEqual(r.minX, 40, accuracy: 0.001)
        let p = AspectFit.map(CGPoint(x: 0.5, y: 0.5), in: r)
        XCTAssertEqual(p.x, 200, accuracy: 0.001); XCTAssertEqual(p.y, 200, accuracy: 0.001)
        let w = AspectFit.rect(content: CGSize(width: 1000, height: 500), in: CGSize(width: 400, height: 400))
        XCTAssertEqual(w.height, 200, accuracy: 0.001); XCTAssertEqual(w.minY, 100, accuracy: 0.001)
    }

    func testAllPointsStayInsideExpandedMaskBounds() {
        let diag: [CGPoint] = [CGPoint(x: 0.40, y: 0.10), CGPoint(x: 0.46, y: 0.10), CGPoint(x: 0.62, y: 0.85), CGPoint(x: 0.56, y: 0.85)]
        let polys = [diag, rect(0.3, 0.3, 0.5, 0.45), rect(0.1, 0.49, 0.9, 0.51)]
        for poly in polys {
            let ex = StitchPathPlanner.expanded(CGRect(x: poly.map(\.x).min()!, y: poly.map(\.y).min()!,
                                                       width: poly.map(\.x).max()! - poly.map(\.x).min()!,
                                                       height: poly.map(\.y).max()! - poly.map(\.y).min()!)).insetBy(dx: -1e-9, dy: -1e-9)
            for type in [StitchType.darning, .runningStitch, .ladderStitch] {
                let plan = StitchPathPlanner.plan(polygon: poly, box: nil, stitchType: type, aspect: 0.75)
                var pts = plan.centerline + plan.stitches.map(\.position) + plan.gridLines.flatMap { $0 }
                pts += (plan.warpStrokes + plan.weftStrokes).flatMap(\.points)
                for p in pts { XCTAssertTrue(ex.contains(p), "\(type) point \(p) outside \(ex)") }
            }
        }
    }
}
