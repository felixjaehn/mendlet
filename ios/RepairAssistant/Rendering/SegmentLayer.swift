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
            if showLabel {
                LabelPinsLayer(segments: [segment], all: [segment], size: size, reveal: reveal)
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

    static func draw(_ ctx: inout GraphicsContext, size sz: CGSize, segment: Segment, color: Color, boost: Double,
                     time: Double, animated: Bool, drawn: CGFloat, reveal: Double?) {
        if let reveal { ctx.clip(to: Path(CGRect(x: 0, y: 0, width: sz.width, height: sz.height * min(1, reveal)))) }
        guard drawn > 0 else { return }
        let rings = ringPaths(for: segment, in: sz)
        let damage = segment.isDamage
        if rings.isEmpty {
            guard let b = segment.normalizedBox else { return }
            let r = CGRect(x: b.minX * sz.width, y: b.minY * sz.height, width: b.width * sz.width, height: b.height * sz.height)
            let br = brackets(in: r)
            ctx.fill(Path(roundedRect: r, cornerRadius: 10), with: .color(color.opacity(0.06 + 0.1 * boost)))
            if damage { glow(&ctx, br, color: color, boost: boost, drawn: drawn) }
            ctx.stroke(trimmed(br, drawn), with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            return
        }
        var all = Path()
        for r in rings { all.addPath(r.path) }
        if damage {
            // Real photos 2026-10-29: a 0.14 fill and 2 pt line vanished on a small sweater hole; draw damage boldly.
            ctx.fill(all, with: .color(color.opacity(0.26 + 0.2 * boost)), style: FillStyle(eoFill: true))
            var outline = Path()
            for r in rings { outline.addPath(trimmed(r.path, drawn)) }
            glow(&ctx, outline, color: color, boost: boost, drawn: 1)
            // dark under-stroke keeps a white outline readable on light fabric (white sneaker, grey shirt)
            ctx.stroke(outline, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 5.5 + 0.8 * boost, lineJoin: .round))
            ctx.stroke(outline, with: .color(color), style: StrokeStyle(lineWidth: 3 + 0.8 * boost, lineJoin: .round))
            let b = all.boundingRect
            if max(b.width, b.height) < 90 {
                // Small damage: a ring around it catches the eye even before the photo zooms in.
                let r = max(b.width, b.height) / 2 + 14 + 3 * boost
                let ring = Path(ellipseIn: CGRect(x: b.midX - r, y: b.midY - r, width: 2 * r, height: 2 * r))
                ctx.stroke(trimmed(ring, drawn), with: .color(.black.opacity(0.3)), style: StrokeStyle(lineWidth: 4.5))
                ctx.stroke(trimmed(ring, drawn), with: .color(color), style: StrokeStyle(lineWidth: 2.5))
            }
            if animated && drawn >= 1 {
                ctx.stroke(outline, with: .color(.white.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round, dash: [2, 9], dashPhase: -time * 14))
            }
        } else {
            ctx.fill(all, with: .color(color.opacity(0.04 + 0.06 * boost)), style: FillStyle(eoFill: true))
            for r in rings {
                ctx.stroke(trimmed(r.path, drawn), with: .color(color.opacity(0.55 + 0.3 * boost)), style: StrokeStyle(lineWidth: 1 + 0.6 * boost, lineJoin: .round))
            }
        }
    }

    private static func glow(_ ctx: inout GraphicsContext, _ p: Path, color: Color, boost: Double, drawn: CGFloat) {
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: 5 + 3 * boost))
            l.stroke(trimmed(p, drawn), with: .color(color.opacity(0.65 + 0.3 * boost)), style: StrokeStyle(lineWidth: 6 + 2 * boost, lineJoin: .round))
        }
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

/// All segments of a response. `appeared` controls fade-in; `hidden` is the user's toggles.
struct SegmentOverlayView: View {
    let segments: [Segment]
    let size: CGSize
    var hidden: Set<String> = []
    var pulsingIDs: Set<String> = []
    var appeared: Bool = true
    var showLabels: Bool = true
    var reveal: Double? = nil
    var showDimension: Bool = false

    var body: some View {
        let live = segments.filter { appeared && !hidden.contains($0.id) }
        let dim = showDimension ? DamageDimension.layout(segments: live, size: size) : nil
        ZStack {
            ForEach(segments) { s in
                SegmentLayer(segment: s, color: segmentColor(s, in: segments), size: size,
                             visible: appeared && !hidden.contains(s.id), pulsing: pulsingIDs.contains(s.id),
                             showLabel: false, reveal: reveal)
            }
            if let dim { DimensionLineView(layout: dim).transition(.opacity) }
            if showLabels {
                LabelPinsLayer(segments: live, all: segments, size: size, reveal: reveal, extraObstacles: dim.map { [$0.chipRect] } ?? [])
            }
        }
        .animation(.easeInOut(duration: 0.35), value: live.map(\.id))
        .frame(width: size.width, height: size.height)
    }
}
