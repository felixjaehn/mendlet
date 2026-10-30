import CoreGraphics
import Foundation

struct StitchPoint: Equatable, Sendable {
    var position: CGPoint   // normalized image coordinates
    var side: Int           // +1 / -1 relative to the centerline
    var index: Int
}

struct StitchPlan: Equatable, Sendable {
    enum Kind: Sendable { case stitches, darning, none }
    var kind: Kind = .none
    var centerline: [CGPoint] = []
    var stitches: [StitchPoint] = []
    /// Darning: each entry is a clipped line segment [start, end], in drawing order.
    var gridLines: [[CGPoint]] = []
    /// Number of lines in the first (principal axis) direction.
    var firstDirectionCount: Int = 0
    /// Darning needle routes (lines plus U-turn arcs), warp first, then weft.
    var warpStrokes: [StitchPathPlanner.DarnStroke] = []
    var weftStrokes: [StitchPathPlanner.DarnStroke] = []
    var isFallback = false
    static let empty = StitchPlan()

    /// Keeps every point inside `r` (normalized image coordinates).
    mutating func clamp(to r: CGRect) {
        func c(_ p: CGPoint) -> CGPoint { CGPoint(x: min(max(p.x, r.minX), r.maxX), y: min(max(p.y, r.minY), r.maxY)) }
        centerline = centerline.map(c)
        for i in stitches.indices { stitches[i].position = c(stitches[i].position) }
        gridLines = gridLines.map { $0.map(c) }
        for i in warpStrokes.indices { warpStrokes[i].points = warpStrokes[i].points.map(c) }
        for i in weftStrokes.indices { weftStrokes[i].points = weftStrokes[i].points.map(c) }
    }
}

/// Pure geometry. No model calls (PRD FR-23, §16).
enum StitchPathPlanner {
    struct Config: Sendable {
        var gridLongSide = 128
        var minStitches = 6
        var maxStitches = 18
        var stitchUnit: CGFloat = 0.06   // target stitch length in height-normalized units
        var minOffset: CGFloat = 0.010
        var maxOffset: CGFloat = 0.045
        var smoothPasses = 3
    }

    /// Margin around the mask bounds (fraction of mask size) that no planned point may leave.
    static let boundsMargin: CGFloat = 0.08

    static func plan(polygon: [CGPoint], box: CGRect?, stitchType: StitchType, aspect: CGFloat = 1, config: Config = Config()) -> StitchPlan {
        var p = rawPlan(polygon: polygon, box: box, stitchType: stitchType, aspect: aspect, config: config)
        let clean = polygon.filter { $0.x.isFinite && $0.y.isFinite }
        var r: CGRect? = clean.count >= 3 ? bounds(clean) : box
        if let b = r, b.width <= 1e-5 || b.height <= 1e-5 { r = box }
        if let b = r { p.clamp(to: expanded(b)) }
        return p
    }

    static func expanded(_ b: CGRect) -> CGRect {
        b.insetBy(dx: -b.width * boundsMargin, dy: -b.height * boundsMargin)
    }

    private static func rawPlan(polygon: [CGPoint], box: CGRect?, stitchType: StitchType, aspect: CGFloat, config: Config) -> StitchPlan {
        let a: CGFloat = (aspect.isFinite && aspect > 0.05 && aspect < 20) ? aspect : 1
        let clean = polygon.filter { $0.x.isFinite && $0.y.isFinite && abs($0.x) < 1e4 && abs($0.y) < 1e4 }
        let poly = clean.map { CGPoint(x: $0.x * a, y: $0.y) }
        let usable = poly.count >= 3 && abs(area(poly)) > 1e-7
        let validBox: CGRect? = {
            guard let b = box, b.width.isFinite, b.height.isFinite, b.width > 1e-5, b.height > 1e-5 else { return nil }
            return b
        }()

        if stitchType == .darning {
            let shape: [CGPoint]
            if usable { shape = poly }
            else if let b = validBox {
                shape = [CGPoint(x: b.minX * a, y: b.minY), CGPoint(x: b.maxX * a, y: b.minY),
                         CGPoint(x: b.maxX * a, y: b.maxY), CGPoint(x: b.minX * a, y: b.maxY)]
            } else { return .empty }
            return darning(shape, a)
        }

        if usable, let p = skeletonPlan(poly, a, config) { return p }
        // Fallback: box diagonal (or bbox diagonal of polygon).
        var rect: CGRect?
        if let b = validBox { rect = b }
        else if usable {
            let bb = bounds(poly)
            rect = CGRect(x: bb.minX / a, y: bb.minY, width: bb.width / a, height: bb.height)
        }
        guard let r = rect else { return .empty }
        let p0 = CGPoint(x: r.minX * a, y: r.minY), p1 = CGPoint(x: r.maxX * a, y: r.maxY)
        let hw = min(r.width * a, r.height) / 2
        var plan = buildStitches(path: [p0, p1], halfWidths: [hw, hw], a, config)
        plan.isFallback = true
        return plan
    }

    // MARK: Skeleton path

    private struct Grid {
        var w = 0, h = 0
        var cells: [Bool] = []
        var originX: CGFloat = 0, originY: CGFloat = 0, cell: CGFloat = 1
        func point(_ x: Int, _ y: Int) -> CGPoint {
            CGPoint(x: originX + (CGFloat(x) + 0.5) * cell, y: originY + (CGFloat(y) + 0.5) * cell)
        }
    }

    private static func skeletonPlan(_ poly: [CGPoint], _ a: CGFloat, _ config: Config) -> StitchPlan? {
        let bb = bounds(poly)
        let longSide = max(bb.width, bb.height)
        guard longSide > 1e-5 else { return nil }
        let pad = 3
        let cell = longSide / CGFloat(config.gridLongSide - 2 * pad)
        var g = Grid()
        g.cell = cell
        g.w = Int((bb.width / cell).rounded(.up)) + 2 * pad + 1
        g.h = Int((bb.height / cell).rounded(.up)) + 2 * pad + 1
        g.originX = bb.minX - CGFloat(pad) * cell
        g.originY = bb.minY - CGFloat(pad) * cell
        g.cells = [Bool](repeating: false, count: g.w * g.h)
        for y in 0..<g.h {
            for x in 0..<g.w where pointInPolygon(g.point(x, y), poly) { g.cells[y * g.w + x] = true }
        }
        let mask = g.cells
        thin(&g)
        guard let pathIdx = longestPath(g), pathIdx.count >= 3 else { return nil }

        var pts = pathIdx.map { g.point($0 % g.w, $0 / g.w) }
        for _ in 0..<config.smoothPasses { pts = smooth(pts) }

        // Half-widths from a chamfer distance transform of the original mask.
        let dt = distanceTransform(mask, g.w, g.h)
        let hws: [CGFloat] = pts.map { p in
            let x = min(g.w - 1, max(0, Int(((p.x - g.originX) / cell).rounded(.down))))
            let y = min(g.h - 1, max(0, Int(((p.y - g.originY) / cell).rounded(.down))))
            return max(CGFloat(dt[y * g.w + x]) / 3.0, 0.5) * cell
        }
        let plan = buildStitches(path: pts, halfWidths: hws, a, config)
        return plan.centerline.count >= 2 ? plan : nil
    }

    private static func buildStitches(path: [CGPoint], halfWidths: [CGFloat], _ a: CGFloat, _ config: Config) -> StitchPlan {
        var cum: [CGFloat] = [0]
        for i in 1..<path.count { cum.append(cum[i - 1] + dist(path[i - 1], path[i])) }
        let total = cum.last ?? 0
        guard total > 1e-6 else { return .empty }
        let n = min(config.maxStitches, max(config.minStitches, Int((total / config.stitchUnit).rounded())))

        func sample(_ s: CGFloat) -> (p: CGPoint, hw: CGFloat) {
            let t = min(max(s, 0), total)
            var i = 1
            while i < cum.count - 1 && cum[i] < t { i += 1 }
            let seg = max(cum[i] - cum[i - 1], 1e-9)
            let f = (t - cum[i - 1]) / seg
            let p = CGPoint(x: path[i - 1].x + (path[i].x - path[i - 1].x) * f, y: path[i - 1].y + (path[i].y - path[i - 1].y) * f)
            let hw = halfWidths[i - 1] + (halfWidths[i] - halfWidths[i - 1]) * f
            return (p, hw)
        }

        let m = max(n * 4, 24)
        let center = (0...m).map { sample(total * CGFloat($0) / CGFloat(m)).p }
        var stitches: [StitchPoint] = []
        let delta = total / CGFloat(n * 4)
        for i in 0..<n {
            let s = total * (CGFloat(i) + 0.5) / CGFloat(n)
            let c = sample(s)
            let ahead = sample(s + delta).p, behind = sample(s - delta).p
            var tx = ahead.x - behind.x, ty = ahead.y - behind.y
            let len = max(hypot(tx, ty), 1e-9)
            tx /= len; ty /= len
            let side = i % 2 == 0 ? 1 : -1
            let off = min(config.maxOffset, max(config.minOffset, c.hw * 1.15))
            let pos = CGPoint(x: c.p.x + (-ty) * CGFloat(side) * off, y: c.p.y + tx * CGFloat(side) * off)
            stitches.append(StitchPoint(position: CGPoint(x: pos.x / a, y: pos.y), side: side, index: i + 1))
        }
        var plan = StitchPlan()
        plan.kind = .stitches
        plan.centerline = center.map { CGPoint(x: $0.x / a, y: $0.y) }
        plan.stitches = stitches
        return plan
    }

    // MARK: Darning grid

    /// One needle stroke of the darn. `isTurn` strokes are the U-turn arcs outside the hole.
    /// `coreFrom`/`coreTo` (0...1 along a line) mark the part lying on the mask; the rest is intact fabric.
    struct DarnStroke: Equatable, Sendable {
        var points: [CGPoint]
        var isTurn = false
        var coreFrom: CGFloat = 0
        var coreTo: CGFloat = 1
    }

    private static func darning(_ poly: [CGPoint], _ a: CGFloat) -> StitchPlan {
        guard abs(area(poly)) > 1e-9 else { return .empty }
        // Centroid + principal axis from the rasterised mask (robust against uneven vertex spacing).
        let bb = bounds(poly)
        let n = 90
        var cnt: CGFloat = 0, mx: CGFloat = 0, my: CGFloat = 0
        var cells: [CGPoint] = []
        for iy in 0..<n { for ix in 0..<n {
            let p = CGPoint(x: bb.minX + bb.width * (CGFloat(ix) + 0.5) / CGFloat(n), y: bb.minY + bb.height * (CGFloat(iy) + 0.5) / CGFloat(n))
            if pointInPolygon(p, poly) { cells.append(p); mx += p.x; my += p.y; cnt += 1 }
        } }
        guard cnt > 4 else { return .empty }
        let cx = mx / cnt, cy = my / cnt
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in cells { let dx = p.x - cx, dy = p.y - cy; sxx += dx * dx; syy += dy * dy; sxy += dx * dy }
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        var u = CGPoint(x: cos(theta), y: sin(theta))
        if u.y < -1e-6 || (abs(u.y) <= 1e-6 && u.x < 0) { u = CGPoint(x: -u.x, y: -u.y) }   // travel downwards first
        var v = CGPoint(x: -u.y, y: u.x)
        if v.x > 0 { v = CGPoint(x: -v.x, y: -v.y) }                                        // start on the right side
        func toQ(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - cx) * u.x + (p.y - cy) * u.y, y: (p.x - cx) * v.x + (p.y - cy) * v.y) }
        func fromQ(_ q: CGPoint) -> CGPoint { CGPoint(x: cx + q.x * u.x + q.y * v.x, y: cy + q.x * u.y + q.y * v.y) }
        func out(_ q: CGPoint) -> CGPoint { let p = fromQ(q); return CGPoint(x: p.x / a, y: p.y) }
        let q = poly.map(toQ)
        let b = bounds(q)
        guard b.width > 1e-5, b.height > 1e-5 else { return .empty }

        /// Hull [lo, hi] of the mask along one scan line (vertical: s = const, runs along t; else t = const).
        func span(_ val: CGFloat, alongS: Bool) -> (CGFloat, CGFloat)? {
            var xs: [CGFloat] = []
            for i in 0..<q.count {
                let p0 = q[i], p1 = q[(i + 1) % q.count]
                let a0 = alongS ? p0.y : p0.x, a1 = alongS ? p1.y : p1.x
                guard (a0 <= val) != (a1 <= val) else { continue }
                let t = (val - a0) / (a1 - a0)
                xs.append(alongS ? p0.x + (p1.x - p0.x) * t : p0.y + (p1.y - p0.y) * t)
            }
            guard let lo = xs.min(), let hi = xs.max(), hi > lo else { return nil }
            return (lo, hi)
        }
        func insideMask(_ qp: CGPoint) -> Bool { pointInPolygon(fromQ(qp), poly) }

        // Warp: lines along the principal axis (s), evenly spaced across the width (t).
        let extentT = b.height
        let warpCount = min(9, max(6, Int((extentT / 0.011).rounded()) + 1))
        let tInset = extentT * 0.02
        let tLo = b.minY + tInset, tHi = b.maxY - tInset
        struct Line { var s0: CGFloat; var s1: CGFloat; var t0: CGFloat; var t1: CGFloat; var coreFrom: CGFloat; var coreTo: CGFloat }
        var warp: [Line] = []
        for k in 0..<warpCount {
            let t = tLo + (tHi - tLo) * CGFloat(k) / CGFloat(warpCount - 1)
            guard let (lo, hi) = span(t, alongS: true) else { continue }
            let ext = max(0.008, (hi - lo) * 0.08)
            let s0 = lo - ext, s1 = hi + ext
            warp.append(Line(s0: s0, s1: s1, t0: t, t1: t, coreFrom: ext / (s1 - s0), coreTo: 1 - ext / (s1 - s0)))
        }
        if let longest = warp.map({ $0.s1 - $0.s0 }).max() { warp = warp.filter { $0.s1 - $0.s0 > longest * 0.12 } }
        guard warp.count >= 2 else { return .empty }
        let warpSpacing = (tHi - tLo) / CGFloat(max(warpCount - 1, 1))

        // Weft: perpendicular lines about as dense as the warp (a real darn is a square weave); a wide spacing
        // made the U-turns into large loops sticking out of the darn.
        let sLo = warp.map(\.s0).min()!, sHi = warp.map(\.s1).max()!
        let coreLo = warp.map { $0.s0 + $0.coreFrom * ($0.s1 - $0.s0) }.min()!
        let coreHi = warp.map { $0.s0 + $0.coreTo * ($0.s1 - $0.s0) }.max()!
        _ = (sLo, sHi)
        let weftCount = min(28, max(5, Int(((coreHi - coreLo) / max(warpSpacing * 1.2, 0.012)).rounded()) + 1))
        var weft: [Line] = []
        for k in 0..<weftCount {
            let s = coreLo + (coreHi - coreLo) * CGFloat(k) / CGFloat(weftCount - 1)
            let sv = min(max(s, b.minX + 1e-4), b.maxX - 1e-4)
            guard let (lo, hi) = span(sv, alongS: false) else { continue }
            let ext = max(0.008, (hi - lo) * 0.08)
            let t0 = lo - ext, t1 = hi + ext
            weft.append(Line(s0: s, s1: s, t0: t0, t1: t1, coreFrom: ext / (t1 - t0), coreTo: 1 - ext / (t1 - t0)))
        }

        // Route: serpentine; U-turn arcs bulge away from the hole and stay outside the mask.
        func route(_ lines: [Line], warpDir: Bool) -> (strokes: [DarnStroke], segs: [[CGPoint]]) {
            var strokes: [DarnStroke] = [], segs: [[CGPoint]] = []
            var prevEnd: CGPoint?
            var prevDir: CGFloat = 1
            for (i, l) in lines.enumerated() {
                let forward = i % 2 == 0
                let aQ = warpDir ? CGPoint(x: l.s0, y: l.t0) : CGPoint(x: l.s0, y: l.t0)
                let bQ = warpDir ? CGPoint(x: l.s1, y: l.t1) : CGPoint(x: l.s1, y: l.t1)
                let start = forward ? aQ : bQ, end = forward ? bQ : aQ
                if let pe = prevEnd {
                    // outward direction in q space: along the travel axis of the previous line
                    let dirQ: CGPoint = warpDir ? CGPoint(x: prevDir, y: 0) : CGPoint(x: 0, y: prevDir)
                    var bulge = max(abs(warpDir ? start.y - pe.y : start.x - pe.x) * 0.6, 0.006)
                    var pts: [CGPoint] = []
                    for _ in 0..<8 {
                        let c1 = CGPoint(x: pe.x + dirQ.x * bulge, y: pe.y + dirQ.y * bulge)
                        let c2 = CGPoint(x: start.x + dirQ.x * bulge, y: start.y + dirQ.y * bulge)
                        pts = (0...10).map { j -> CGPoint in
                            let t = CGFloat(j) / 10, m = 1 - t
                            return CGPoint(x: m*m*m*pe.x + 3*m*m*t*c1.x + 3*m*t*t*c2.x + t*t*t*start.x,
                                           y: m*m*m*pe.y + 3*m*m*t*c1.y + 3*m*t*t*c2.y + t*t*t*start.y)
                        }
                        // straight chord and curve must stay outside the mask
                        if pts.allSatisfy({ !insideMask($0) }) { break }
                        bulge *= 1.7
                    }
                    strokes.append(DarnStroke(points: pts.map(out), isTurn: true))
                }
                var dir: CGFloat = 1
                if warpDir { dir = end.x >= start.x ? 1 : -1 } else { dir = end.y >= start.y ? 1 : -1 }
                prevDir = dir
                prevEnd = end
                let cf = forward ? l.coreFrom : 1 - l.coreTo, ct = forward ? l.coreTo : 1 - l.coreFrom
                strokes.append(DarnStroke(points: [out(start), out(end)], coreFrom: cf, coreTo: ct))
                segs.append([out(start), out(end)])
            }
            return (strokes, segs)
        }
        let w = route(warp, warpDir: true)
        let wf = route(weft, warpDir: false)
        var plan = StitchPlan()
        plan.kind = .darning
        plan.gridLines = w.segs + wf.segs
        plan.firstDirectionCount = w.segs.count
        plan.warpStrokes = w.strokes
        plan.weftStrokes = wf.strokes
        return plan.gridLines.isEmpty || wf.segs.isEmpty ? .empty : plan
    }

    // MARK: Raster helpers

    private static func thin(_ g: inout Grid) {
        let w = g.w, h = g.h
        var changed = true
        while changed {
            changed = false
            for step in 0..<2 {
                var del: [Int] = []
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) where g.cells[y * w + x] {
                        let p2 = g.cells[(y - 1) * w + x], p3 = g.cells[(y - 1) * w + x + 1]
                        let p4 = g.cells[y * w + x + 1], p5 = g.cells[(y + 1) * w + x + 1]
                        let p6 = g.cells[(y + 1) * w + x], p7 = g.cells[(y + 1) * w + x - 1]
                        let p8 = g.cells[y * w + x - 1], p9 = g.cells[(y - 1) * w + x - 1]
                        let seq = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
                        let bsum = seq.dropLast().filter { $0 }.count
                        guard bsum >= 2 && bsum <= 6 else { continue }
                        var trans = 0
                        for i in 0..<8 where !seq[i] && seq[i + 1] { trans += 1 }
                        guard trans == 1 else { continue }
                        if step == 0 {
                            if !(p2 && p4 && p6) && !(p4 && p6 && p8) { del.append(y * w + x) }
                        } else {
                            if !(p2 && p4 && p8) && !(p2 && p6 && p8) { del.append(y * w + x) }
                        }
                    }
                }
                if !del.isEmpty { changed = true; for i in del { g.cells[i] = false } }
            }
        }
    }

    private static func neighbors(_ i: Int, _ w: Int, _ h: Int) -> [Int] {
        let x = i % w, y = i / w
        var out: [Int] = []
        for dy in -1...1 { for dx in -1...1 where !(dx == 0 && dy == 0) {
            let nx = x + dx, ny = y + dy
            if nx >= 0 && ny >= 0 && nx < w && ny < h { out.append(ny * w + nx) }
        } }
        return out
    }

    private static func bfs(from start: Int, _ g: Grid) -> (order: [Int], parent: [Int: Int], far: Int) {
        var parent: [Int: Int] = [start: -1]
        var queue = [start], head = 0, far = start
        while head < queue.count {
            let cur = queue[head]; head += 1
            far = cur
            for n in neighbors(cur, g.w, g.h) where g.cells[n] && parent[n] == nil {
                parent[n] = cur; queue.append(n)
            }
        }
        return (queue, parent, far)
    }

    private static func longestPath(_ g: Grid) -> [Int]? {
        let skel = g.cells.indices.filter { g.cells[$0] }
        guard !skel.isEmpty else { return nil }
        // largest component
        var seen = Set<Int>()
        var best: [Int] = []
        for s in skel where !seen.contains(s) {
            let r = bfs(from: s, g)
            seen.formUnion(r.order)
            if r.order.count > best.count { best = r.order }
        }
        guard best.count >= 3 else { return nil }
        let first = bfs(from: best[0], g)
        let a = first.far
        let second = bfs(from: a, g)
        var path: [Int] = []
        var cur = second.far
        while cur != -1 { path.append(cur); cur = second.parent[cur] ?? -1 }
        return path
    }

    private static func smooth(_ pts: [CGPoint]) -> [CGPoint] {
        guard pts.count > 2 else { return pts }
        return pts.indices.map { i in
            let k = min(3, i, pts.count - 1 - i)
            guard k > 0 else { return pts[i] }
            var sx: CGFloat = 0, sy: CGFloat = 0
            for j in (i - k)...(i + k) { sx += pts[j].x; sy += pts[j].y }
            let c = CGFloat(2 * k + 1)
            return CGPoint(x: sx / c, y: sy / c)
        }
    }

    private static func distanceTransform(_ mask: [Bool], _ w: Int, _ h: Int) -> [Int] {
        let inf = 1_000_000
        var d = mask.map { $0 ? inf : 0 }
        func get(_ x: Int, _ y: Int) -> Int { (x < 0 || y < 0 || x >= w || y >= h) ? 0 : d[y * w + x] }
        for y in 0..<h { for x in 0..<w where d[y * w + x] > 0 {
            d[y * w + x] = min(d[y * w + x], get(x - 1, y) + 3, get(x - 1, y - 1) + 4, get(x, y - 1) + 3, get(x + 1, y - 1) + 4)
        } }
        for y in stride(from: h - 1, through: 0, by: -1) { for x in stride(from: w - 1, through: 0, by: -1) where d[y * w + x] > 0 {
            d[y * w + x] = min(d[y * w + x], get(x + 1, y) + 3, get(x + 1, y + 1) + 4, get(x, y + 1) + 3, get(x - 1, y + 1) + 4)
        } }
        return d
    }

    // MARK: Geometry

    static func pointInPolygon(_ p: CGPoint, _ poly: [CGPoint]) -> Bool {
        var inside = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let pi = poly[i], pj = poly[j]
            if (pi.y > p.y) != (pj.y > p.y), p.x < (pj.x - pi.x) * (p.y - pi.y) / (pj.y - pi.y) + pi.x { inside.toggle() }
            j = i
        }
        return inside
    }

    private static func area(_ poly: [CGPoint]) -> CGFloat {
        var s: CGFloat = 0
        for i in 0..<poly.count { let a = poly[i], b = poly[(i + 1) % poly.count]; s += a.x * b.y - b.x * a.y }
        return s / 2
    }

    private static func bounds(_ pts: [CGPoint]) -> CGRect {
        guard let f = pts.first else { return .zero }
        var minX = f.x, maxX = f.x, minY = f.y, maxY = f.y
        for p in pts { minX = min(minX, p.x); maxX = max(maxX, p.x); minY = min(minY, p.y); maxY = max(maxY, p.y) }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// Convenience for a segment.
    static func plan(for segment: Segment, stitchType: StitchType, aspect: CGFloat) -> StitchPlan {
        plan(polygon: segment.polygon, box: segment.normalizedBox, stitchType: stitchType, aspect: aspect)
    }
}

/// Aspect-fit mapping between normalized image coordinates and view coordinates.
enum AspectFit {
    static func rect(content: CGSize, in container: CGSize) -> CGRect {
        guard content.width > 0, content.height > 0, container.width > 0, container.height > 0 else { return CGRect(origin: .zero, size: container) }
        let s = min(container.width / content.width, container.height / content.height)
        let w = content.width * s, h = content.height * s
        return CGRect(x: (container.width - w) / 2, y: (container.height - h) / 2, width: w, height: h)
    }
    static func map(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height)
    }
}
