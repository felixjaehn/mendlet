import SwiftUI

enum DarningPhase: Sendable { case all, first, second }

/// Animated stitch path: a thin thread is drawn progressively with a needle at its head.
/// Darning: warp threads first (down one line, U-turn outside the hole, back up the next), then the weft woven over/under.
/// Running/ladder stitch: zig-zag thread across the centerline with sparse numbered markers.
struct StitchPathView: View {
    let plan: StitchPlan
    var phase: DarningPhase = .all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// A polyline piece of the thread. Invisible pieces advance the needle without leaving thread (jumps, "under" gaps).
    private struct Piece { var pts: [CGPoint]; var visible = true; var dashed = false }
    private struct Marker { var at: CGFloat; var point: CGPoint; var number: Int; var filled: Bool; var small: Bool }
    private struct Trace { var pieces: [Piece] = []; var markers: [Marker] = []; var total: CGFloat = 0 }

    var body: some View {
        if plan.kind == .none {
            Color.clear
        } else if reduceMotion {
            Canvas { ctx, size in draw(&ctx, size, progress: 1, alpha: 1) }
                .accessibilityHidden(true)
        } else {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let (p, a) = timing(tl.date.timeIntervalSince(start))
                    draw(&ctx, size, progress: p, alpha: a)
                }
            }
            .accessibilityHidden(true)
            .onAppear { start = Date() }
        }
    }

    // MARK: Timing

    private var drawDuration: Double {
        switch plan.kind {
        case .stitches: return 1.2 + 0.30 * Double(plan.stitches.count)
        case .darning:
            let n = (phase == .second ? 0 : plan.warpStrokes.count) + (phase == .first ? 0 : plan.weftStrokes.count)
            return 1.2 + 0.11 * Double(n)
        case .none: return 1
        }
    }
    private let pause = 1.8

    private func timing(_ elapsed: Double) -> (progress: Double, alpha: Double) {
        let cycle = drawDuration + pause
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        let p = min(1, t / drawDuration)
        let fadeStart = drawDuration + pause - 0.35
        let alpha = t > fadeStart ? max(0, 1 - (t - fadeStart) / 0.35) : 1
        return (p, alpha)
    }

    // MARK: Geometry -> traces

    private func px(_ p: CGPoint, _ size: CGSize) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
    private func length(_ pts: [CGPoint]) -> CGFloat {
        guard pts.count > 1 else { return 0 }
        return (1..<pts.count).reduce(0) { $0 + hypot(pts[$1].x - pts[$1 - 1].x, pts[$1].y - pts[$1 - 1].y) }
    }
    private func lerp(_ a: CGPoint, _ b: CGPoint, _ f: CGFloat) -> CGPoint { CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f) }

    private func intersection(_ a0: CGPoint, _ a1: CGPoint, _ b0: CGPoint, _ b1: CGPoint) -> CGFloat? {
        let d1 = CGPoint(x: a1.x - a0.x, y: a1.y - a0.y), d2 = CGPoint(x: b1.x - b0.x, y: b1.y - b0.y)
        let den = d1.x * d2.y - d1.y * d2.x
        guard abs(den) > 1e-9 else { return nil }
        let t = ((b0.x - a0.x) * d2.y - (b0.y - a0.y) * d2.x) / den
        let u = ((b0.x - a0.x) * d1.y - (b0.y - a0.y) * d1.x) / den
        return (t > 0 && t < 1 && u > 0 && u < 1) ? t : nil
    }

    private func darnTrace(warp: Bool, weft: Bool, size: CGSize) -> Trace {
        var tr = Trace()
        var cum: CGFloat = 0
        var last: CGPoint?
        let warpLines = plan.gridLines.prefix(plan.firstDirectionCount).map { $0.map { px($0, size) } }
        func add(_ pts: [CGPoint], visible: Bool = true, dashed: Bool = false) {
            guard pts.count >= 2 else { return }
            tr.pieces.append(Piece(pts: pts, visible: visible, dashed: dashed))
            cum += length(pts); last = pts.last
        }
        func addStrokes(_ strokes: [StitchPathPlanner.DarnStroke], isWeft: Bool) {
            var lineIndex = 0
            for s in strokes {
                let pts = s.points.map { px($0, size) }
                if let l = last, let f = pts.first, hypot(l.x - f.x, l.y - f.y) > 0.5 { add([l, f], visible: false) }
                if s.isTurn { add(pts); continue }
                guard pts.count == 2 else { add(pts); continue }
                let p0 = pts[0], p1 = pts[1]
                if tr.markers.isEmpty { tr.markers.append(Marker(at: 0, point: p0, number: 1, filled: true, small: false)) }
                add([p0, lerp(p0, p1, s.coreFrom)], dashed: true)
                // core: the weft passes under every other warp thread
                var gaps: [(CGFloat, CGFloat)] = []
                if isWeft {
                    let gHalf = 2.4 / max(hypot(p1.x - p0.x, p1.y - p0.y), 1)
                    for (k, w) in warpLines.enumerated() where (k + lineIndex) % 2 == 0 && w.count == 2 {
                        if let f = intersection(p0, p1, w[0], w[1]) { gaps.append((f - gHalf, f + gHalf)) }
                    }
                    gaps.sort { $0.0 < $1.0 }
                }
                var cursor = s.coreFrom
                for g in gaps where g.1 > s.coreFrom && g.0 < s.coreTo {
                    let g0 = max(g.0, cursor), g1 = min(g.1, s.coreTo)
                    guard g1 > g0 else { continue }
                    if g0 > cursor { add([lerp(p0, p1, cursor), lerp(p0, p1, g0)]) }
                    add([lerp(p0, p1, g0), lerp(p0, p1, g1)], visible: false)
                    cursor = g1
                }
                if s.coreTo > cursor { add([lerp(p0, p1, cursor), lerp(p0, p1, s.coreTo)]) }
                add([lerp(p0, p1, s.coreTo), p1], dashed: true)
                lineIndex += 1
            }
        }
        if warp { addStrokes(plan.warpStrokes, isWeft: false) }
        if weft { addStrokes(plan.weftStrokes, isWeft: true) }
        tr.total = cum
        if let l = last, cum > 1 { tr.markers.append(Marker(at: cum, point: l, number: 2, filled: false, small: true)) }
        return tr
    }

    private func stitchTrace(size: CGSize) -> Trace {
        var tr = Trace()
        let pts = plan.stitches.map { px($0.position, size) }
        guard pts.count >= 2 else { return tr }
        var cum: [CGFloat] = [0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        tr.pieces = [Piece(pts: pts)]
        tr.total = cum.last ?? 0
        for i in pts.indices where i % 3 == 0 || i == pts.count - 1 {
            tr.markers.append(Marker(at: cum[i], point: pts[i], number: plan.stitches[i].index, filled: i % 2 == 0, small: false))
        }
        return tr
    }

    // MARK: Drawing

    private func partial(_ pts: [CGPoint], _ amount: CGFloat) -> ([CGPoint], CGFloat) {
        guard amount > 0, pts.count >= 2 else { return ([], 0) }
        var out = [pts[0]], acc: CGFloat = 0, ang: CGFloat = 0
        for i in 1..<pts.count {
            let d = hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            ang = atan2(pts[i].y - pts[i - 1].y, pts[i].x - pts[i - 1].x)
            if acc + d <= amount { out.append(pts[i]); acc += d }
            else { out.append(lerp(pts[i - 1], pts[i], (amount - acc) / max(d, 1e-6))); break }
        }
        return (out, ang)
    }

    /// Strokes the thread (shadow, thread, highlight). Returns head position and angle.
    @discardableResult
    private func strokeTrace(_ ctx: inout GraphicsContext, _ tr: Trace, drawn: CGFloat) -> (CGPoint, CGFloat)? {
        var solid = Path(), dashed = Path()
        var start: CGFloat = 0
        var head: (CGPoint, CGFloat)?
        for p in tr.pieces {
            let len = length(p.pts)
            let amt = min(max(drawn - start, 0), len)
            start += len
            if amt <= 0 { break }
            let (pts, ang) = partial(p.pts, amt)
            if pts.count >= 2 {
                head = (pts.last!, ang)
                if p.visible {
                    var path = Path(); path.addLines(pts)
                    if p.dashed { dashed.addPath(path) } else { solid.addPath(path) }
                }
            }
            if amt < len { break }
        }
        let thread = Theme.highlight
        let shadowT = CGAffineTransform(translationX: 0.9, y: 1.0), hiT = CGAffineTransform(translationX: -0.5, y: -0.6)
        let dash: [CGFloat] = [5, 4]
        for (path, d) in [(solid, [CGFloat]()), (dashed, dash)] {
            ctx.stroke(path.applying(shadowT), with: .color(.black.opacity(0.32)), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round, dash: d))
            ctx.stroke(path, with: .color(thread), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round, dash: d))
            ctx.stroke(path.applying(hiT), with: .color(.white.opacity(0.32)), style: StrokeStyle(lineWidth: 0.8, lineCap: .round, lineJoin: .round, dash: d))
        }
        return head
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, progress: Double, alpha: Double) {
        ctx.opacity = alpha
        let thread = Theme.highlight
        var tr: Trace
        switch plan.kind {
        case .stitches:
            tr = stitchTrace(size: size)
            if plan.centerline.count >= 2 {
                var c = Path(); c.addLines(plan.centerline.map { px($0, size) })
                ctx.stroke(c, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [1.5, 6]))
            }
        case .darning:
            if phase == .second {
                let still = darnTrace(warp: true, weft: false, size: size)
                strokeTrace(&ctx, still, drawn: still.total + 1)
            }
            tr = darnTrace(warp: phase != .second, weft: phase != .first, size: size)
        case .none:
            return
        }
        guard tr.total > 1 else { return }
        let drawn = tr.total * CGFloat(progress)
        let head = strokeTrace(&ctx, tr, drawn: drawn)

        // individual stitch holes
        if plan.kind == .stitches {
            var idx = 0
            for s in plan.stitches {
                let c = px(s.position, size)
                idx += 1
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2.6, y: c.y - 2.6, width: 5.2, height: 5.2)), with: .color(.white.opacity(0.9)))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 1.5, y: c.y - 1.5, width: 3, height: 3)), with: .color(thread))
            }
        }

        // markers
        for m in tr.markers {
            guard drawn + 0.5 >= m.at else { continue }
            let sinceSec = progress >= 1 ? 1.0 : Double((drawn - m.at) / tr.total) * drawDuration
            let s = pop(min(1, max(0, sinceSec / 0.35)))
            let r: CGFloat = (m.small ? 5 : 8) * CGFloat(s)
            let rect = CGRect(x: m.point.x - r, y: m.point.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: -1.5, dy: -1.5)), with: .color(.black.opacity(0.25)))
            ctx.fill(Path(ellipseIn: rect), with: .color(m.filled ? thread : .white))
            ctx.stroke(Path(ellipseIn: rect), with: .color(m.filled ? .white : thread), lineWidth: 1.8)
            if s > 0.6 && !m.small {
                let label = Text("\(m.number)").font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundColor(m.filled ? .white : thread)
                ctx.draw(label, at: m.point)
            }
        }

        // needle
        if progress > 0 && progress < 1, let (hp, ang) = head {
            var n = ctx
            n.translateBy(x: hp.x, y: hp.y)
            n.rotate(by: .radians(Double(ang)))
            let needle = Path(roundedRect: CGRect(x: -16, y: -1.1, width: 28, height: 2.2), cornerRadius: 1.1)
            n.fill(needle, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.7)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 3)))
            n.stroke(needle, with: .color(.black.opacity(0.4)), lineWidth: 0.5)
            n.stroke(Path(ellipseIn: CGRect(x: -14, y: -0.8, width: 4.5, height: 1.6)), with: .color(.black.opacity(0.55)), lineWidth: 0.7)
        }
    }

    private func pop(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}
