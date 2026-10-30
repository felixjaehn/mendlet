import SwiftUI

/// One segment drawn with Canvas: masks as soft fill + thin contour, damage with glow and marching ants,
/// box-only parts as corner brackets. `reveal` (0...1, top-down) clips to the swept area and draws contours on.
struct SegmentLayer: View {
    let segment: Segment
    let color: Color
    let size: CGSize
    var visible: Bool = true
    var pulsing: Bool = false
    var showLabel: Bool = false
    var reveal: Double? = nil
    @State private var appearedAt = Date()
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.staticRendering) private var staticRendering
    private var reduceMotion: Bool { systemReduceMotion || staticRendering }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !visible)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let boost = pulsing ? (reduceMotion ? 0.5 : 0.5 + 0.5 * sin(t * 6)) : 0
                let drawn = drawProgress(now: tl.date)
                Canvas { ctx, sz in
                    Self.draw(&ctx, size: sz, segment: segment, color: color, boost: boost, time: reduceMotion ? 0 : t,
                              animated: !reduceMotion, drawn: drawn, reveal: reveal)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.45), value: visible)
        .accessibilityHidden(true)
    }

    private func drawProgress(now: Date) -> CGFloat {
        if let reveal {
            guard let b = segment.normalizedBounds else { return 1 }
            return min(1, max(0, (reveal - b.minY) / max(b.height, 0.12)))
        }
        if reduceMotion { return 1 }
        let x = min(1, max(0, (now.timeIntervalSince(appearedAt) - 0.1) / 0.9))
        return 1 - pow(1 - x, 3)
    }

    // MARK: Drawing

    /// Calm marking style: damage = faint white tint and a thin white contour over a dark hairline, parts = a quiet
    /// hairline. No glow, no ring, no marching ants. Box-only segments get corner brackets.
    static func draw(_ ctx: inout GraphicsContext, size sz: CGSize, segment: Segment, color: Color, boost: Double,
                     time: Double, animated: Bool, drawn: CGFloat, reveal: Double?) {
        if let reveal { ctx.clip(to: Path(CGRect(x: 0, y: 0, width: sz.width, height: sz.height * min(1, reveal)))) }
        guard drawn > 0 else { return }
        let damage = segment.isDamage
        let contours = MaskPath.contours(for: segment)
        if contours.isEmpty {
            guard let b = segment.normalizedBox else { return }
            let r = CGRect(x: b.minX * sz.width, y: b.minY * sz.height, width: b.width * sz.width, height: b.height * sz.height)
            let br = brackets(in: r)
            ctx.stroke(trimmed(br, drawn), with: .color(.black.opacity(0.28)), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            ctx.stroke(trimmed(br, drawn), with: .color(color.opacity(damage ? 1 : 0.6)), style: StrokeStyle(lineWidth: damage ? 2 : 1.25, lineCap: .round, lineJoin: .round))
            return
        }
        var fillPath = Path(), outline = Path()
        for c in contours {
            let p = MaskPath.path(c, in: sz)
            if c.closed { fillPath.addPath(p) }
            outline.addPath(p)
        }
        ctx.fill(fillPath, with: .color(color.opacity(damage ? 0.10 + 0.08 * boost : 0.0)), style: FillStyle(eoFill: true))
        let line = trimmed(outline, drawn)
        let w: CGFloat = damage ? 1.5 : 1
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 1))
            l.stroke(line, with: .color(.black.opacity(damage ? 0.28 : 0.18)), style: StrokeStyle(lineWidth: w * 2, lineCap: .round, lineJoin: .round))
        }
        ctx.stroke(line, with: .color(color.opacity(damage ? 1 : 0.55)), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }

    private static func trimmed(_ p: Path, _ t: CGFloat) -> Path { t >= 1 ? p : p.trimmedPath(from: 0, to: max(0.001, t)) }

    /// Four soft corner brackets for box-only segments.
    static func brackets(in r: CGRect) -> Path {
        let l = min(22, max(10, min(r.width, r.height) * 0.22))
        var p = Path()
        for (cx, cy, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            p.move(to: CGPoint(x: cx + dx * l, y: cy)); p.addLine(to: CGPoint(x: cx, y: cy)); p.addLine(to: CGPoint(x: cx, y: cy + dy * l))
        }
        return p
    }

    static func ringPaths(for s: Segment, in size: CGSize) -> [(path: Path, hole: Bool)] {
        s.ringPolygons.map { ring in
            var p = Path()
            p.move(to: CGPoint(x: ring.points[0].x * size.width, y: ring.points[0].y * size.height))
            for q in ring.points.dropFirst() { p.addLine(to: CGPoint(x: q.x * size.width, y: q.y * size.height)) }
            p.closeSubpath()
            return (p, ring.hole)
        }
    }

    static func path(for s: Segment, in size: CGSize) -> Path {
        var p = Path()
        let rings = ringPaths(for: s, in: size)
        if !rings.isEmpty { for r in rings { p.addPath(r.path) } }
        else if let b = s.normalizedBox {
            p.addRoundedRect(in: CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height), cornerSize: CGSize(width: 8, height: 8))
        }
        return p
    }
}
