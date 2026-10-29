import SwiftUI

/// Mask contours for the marking: simplified (Ramer-Douglas-Peucker) and smoothed (Chaikin), in normalized photo
/// coordinates. Built once per segment and cached. Spec section 4.1.
enum MaskPath {
    /// One contour: closed rings stay closed; a ring touching the photo edge is cut into open runs so the edge is not stroked.
    struct Contour: Sendable {
        var points: [CGPoint]
        var closed: Bool
    }

    /// 0.4 % of the image diagonal, in normalized units.
    static let epsilon: CGFloat = 0.004 * 1.4142

    static func simplify(_ pts: [CGPoint], epsilon: CGFloat = MaskPath.epsilon, closed: Bool = true) -> [CGPoint] {
        guard pts.count > 3 else { return pts }
        var work = pts
        if closed, let f = work.first, let l = work.last, f == l { work.removeLast() }
        if closed {
            // split the ring at its two farthest-apart points so RDP has stable anchors
            let a = 0
            var b = 0, best: CGFloat = -1
            for (i, p) in work.enumerated() { let d = hypot(p.x - work[a].x, p.y - work[a].y); if d > best { best = d; b = i } }
            let first = rdp(Array(work[a...b]), epsilon)
            let second = rdp(Array(work[b...] + [work[a]]), epsilon)
            return Array(first.dropLast()) + Array(second.dropLast())
        }
        return rdp(work, epsilon)
    }

    private static func rdp(_ p: [CGPoint], _ eps: CGFloat) -> [CGPoint] {
        guard p.count > 2, let a = p.first, let b = p.last else { return p }
        var idx = 0, dmax: CGFloat = 0
        for i in 1..<(p.count - 1) {
            let d = distance(p[i], a, b)
            if d > dmax { dmax = d; idx = i }
        }
        guard dmax > eps else { return [a, b] }
        let l = rdp(Array(p[0...idx]), eps), r = rdp(Array(p[idx...]), eps)
        return Array(l.dropLast()) + r
    }

    private static func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len = hypot(dx, dy)
        if len < 1e-9 { return hypot(p.x - a.x, p.y - a.y) }
        return abs(dy * p.x - dx * p.y + b.x * a.y - b.y * a.x) / len
    }

    static func chaikin(_ pts: [CGPoint], iterations: Int = 2, closed: Bool = true) -> [CGPoint] {
        var p = pts
        for _ in 0..<iterations {
            guard p.count > 2 else { break }
            var out: [CGPoint] = []
            let n = p.count
            for i in 0..<(closed ? n : n - 1) {
                let a = p[i], b = p[(i + 1) % n]
                let q = CGPoint(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y)
                let r = CGPoint(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y)
                if !closed && i == 0 { out.append(a) }
                out.append(q); out.append(r)
                if !closed && i == n - 2 { out.append(b) }
            }
            p = out
        }
        return p
    }

    private static func onEdge(_ p: CGPoint) -> Bool { p.x < 0.004 || p.x > 0.996 || p.y < 0.004 || p.y > 0.996 }

    /// Rotates a closed ring so it starts at its top-most point and runs clockwise (screen coordinates).
    static func startingAtTop(_ ring: [CGPoint]) -> [CGPoint] {
        guard ring.count > 2, let top = ring.indices.min(by: { ring[$0].y < ring[$1].y }) else { return ring }
        var r = Array(ring[top...] + ring[..<top])
        var area: CGFloat = 0
        for i in r.indices { let a = r[i], b = r[(i + 1) % r.count]; area += a.x * b.y - b.x * a.y }
        if area < 0 { r = [r[0]] + r.dropFirst().reversed() }  // y down: positive shoelace area = clockwise on screen
        return r
    }

    static func contours(for ring: [CGPoint]) -> [Contour] {
        guard ring.count >= 3 else { return [] }
        let simp = simplify(ring)
        guard simp.count >= 3 else { return [] }
        if !simp.contains(where: onEdge) {
            return [Contour(points: chaikin(startingAtTop(simp)), closed: true)]
        }
        // cut at edge points, keep runs of free points
        var runs: [[CGPoint]] = [], cur: [CGPoint] = []
        for p in simp {
            if onEdge(p) { if cur.count > 1 { runs.append(cur) }; cur = [] } else { cur.append(p) }
        }
        if cur.count > 1 { runs.append(cur) }
        if runs.count > 1, let f = runs.first, let l = runs.last, !onEdge(simp.first!), !onEdge(simp.last!) { runs = Array(runs.dropFirst().dropLast()) + [l + f] }
        return runs.map { Contour(points: chaikin($0, closed: false), closed: false) }
    }

    nonisolated(unsafe) private static var cache: [String: [Contour]] = [:]
    private static let lock = NSLock()

    /// Outer rings and holes of a damage segment, cached by id and shape.
    static func contours(for s: Segment) -> [Contour] {
        let rings = s.ringPolygons
        let key = "\(s.id)|\(rings.count)|\(rings.map { $0.points.count }.reduce(0, +))|\(rings.first?.points.first.map { "\($0.x),\($0.y)" } ?? "")"
        lock.lock(); defer { lock.unlock() }
        if let c = cache[key] { return c }
        let c = rings.flatMap { contours(for: $0.points) }
        if cache.count > 200 { cache.removeAll() }
        cache[key] = c
        return c
    }

    static func path(_ c: Contour, in size: CGSize) -> Path {
        var p = Path()
        guard let f = c.points.first else { return p }
        p.move(to: CGPoint(x: f.x * size.width, y: f.y * size.height))
        for q in c.points.dropFirst() { p.addLine(to: CGPoint(x: q.x * size.width, y: q.y * size.height)) }
        if c.closed { p.closeSubpath() }
        return p
    }
}
