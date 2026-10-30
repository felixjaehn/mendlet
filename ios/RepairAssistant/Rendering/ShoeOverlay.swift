import SwiftUI

/// What a shoe guide step asks for, derived from its text.
struct ShoeStepKind: Equatable {
    var glue: Bool
    var press: Bool
    var cure: Bool
    var minutes: Int?

    init(step: GuideStep) {
        let t = (step.title + " " + step.text).lowercased()
        glue = ["kleber", "auftrag", "bestreich", "aufstreich", "glue", "adhesive", "brush", "spread"].contains { t.contains($0) }
        press = ["andrück", "andruck", "drück", "pressen", "fixier", "beschwer", "press", "clamp", "weigh"].contains { t.contains($0) }
        cure = ["aushärt", "andrück", "abbind", "ablüft", "trockn", "cure", "curing", "dry", "harden", "tacky", "press"].contains { t.contains($0) }
        minutes = Self.minutes(in: step.text) ?? Self.minutes(in: step.title)
    }

    /// First duration in the text, in minutes ("10 Minuten", "20–30 Min.", "2 Stunden"); a range yields its upper bound.
    static func minutes(in text: String) -> Int? {
        let pattern = #"(\d+)(?:\s*(?:–|-|bis|to)\s*(\d+))?\s*(Minuten|Minutes?|Mins?\.?|Min\.?|Stunden|Hours?|Hrs?\.?|Std\.?|h)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r1 = Range(m.range(at: 1), in: text), let a = Int(text[r1]),
              let ru = Range(m.range(at: 3), in: text) else { return nil }
        var v = a
        if let r2 = Range(m.range(at: 2), in: text), let b = Int(text[r2]) { v = max(a, b) }
        let unit = text[ru].lowercased()
        return unit.hasPrefix("m") ? v : v * 60
    }
}

/// Overlay for glue steps on shoes: hatched glue band with animated brush strokes, press arrows, countdown ring.
struct ShoeOverlay: View {
    let step: GuideStep
    let response: AnalyzeResponse
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.staticRendering) private var staticRendering
    private var reduceMotion: Bool { systemReduceMotion || staticRendering }

    @Environment(\.photoVisibleRect) private var visibleRect
    private var kind: ShoeStepKind { ShoeStepKind(step: step) }
    private var target: Segment? {
        if let id = step.overlay?.segmentId, let s = response.segment(id) { return s }
        for id in step.segmentIds { if let s = response.segment(id), s.isDamage { return s } }
        return response.segments.first { $0.isDamage } ?? step.segmentIds.first.flatMap { response.segment($0) }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let s = target {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
                    Canvas { ctx, sz in
                        Self.draw(&ctx, size: sz, segment: s, kind: kind, time: reduceMotion ? 1.2 : tl.date.timeIntervalSinceReferenceDate, clip: visibleRect)
                    }
                }
                .allowsHitTesting(false)
                if kind.glue { glueLabel(for: s) }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    /// One typographic label in the style of the finding labels: text, hairline leader, dot on the band. Always inside the photo.
    @ViewBuilder private func glueLabel(for s: Segment) -> some View {
        let pts = Self.contour(of: s, in: size)
        let vis = (visibleRect ?? CGRect(origin: .zero, size: size)).insetBy(dx: 14, dy: 14)
        let inside = pts.filter { vis.contains($0) }
        if let anchor = inside.max(by: { $0.y < $1.y }) {
            let text = tr("Glue here")
            let w = LabelPlacer.width(text: text, score: nil, badge: nil), h = LabelPlacer.chipHeight
            let rect = CGRect(x: min(max(anchor.x - w / 2, vis.minX), vis.maxX - w), y: min(anchor.y + 44 - h / 2, vis.maxY - h), width: w, height: h)
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: anchor); p.addLine(to: CGPoint(x: min(max(anchor.x, rect.minX + 8), rect.maxX - 8), y: rect.minY)) }
                    .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 0.75, lineCap: .round)).shadow(color: .black.opacity(0.35), radius: 1.5)
                Circle().fill(.white).frame(width: 4, height: 4).shadow(color: .black.opacity(0.35), radius: 1.5).position(anchor)
                Text(text).font(.footnote.weight(.semibold)).foregroundStyle(.white).shadow(color: .black.opacity(0.35), radius: 2)
                    .lineLimit(1).fixedSize().position(x: rect.midX, y: rect.midY)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading).allowsHitTesting(false)
        }
    }

    // MARK: Geometry

    /// Largest outer ring in pixels.
    static func contour(of s: Segment, in size: CGSize) -> [CGPoint] {
        let rings = s.ringPolygons.filter { !$0.hole }
        let best = rings.max { area($0.points) < area($1.points) }?.points ?? []
        if best.count >= 3 { return best.map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) } }
        guard let b = s.normalizedBox else { return [] }
        let r = CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height)
        return [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
    }

    static func area(_ p: [CGPoint]) -> CGFloat {
        guard p.count >= 3 else { return 0 }
        var a: CGFloat = 0
        for i in 0..<p.count { let q = p[(i + 1) % p.count]; a += p[i].x * q.y - q.x * p[i].y }
        return abs(a) / 2
    }

    /// Long axis (unit), its upward-pointing normal (unit) and the polygon centre / half length along the axis.
    static func axes(_ p: [CGPoint]) -> (center: CGPoint, along: CGVector, normal: CGVector, half: CGFloat) {
        let n = CGFloat(max(p.count, 1))
        let c = CGPoint(x: p.reduce(0) { $0 + $1.x } / n, y: p.reduce(0) { $0 + $1.y } / n)
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for q in p { let dx = q.x - c.x, dy = q.y - c.y; sxx += dx * dx; syy += dy * dy; sxy += dx * dy }
        let theta = 0.5 * atan2(2 * sxy, sxx - syy)
        let u = CGVector(dx: cos(theta), dy: sin(theta))
        var nrm = CGVector(dx: -u.dy, dy: u.dx)
        if nrm.dy > 0 { nrm = CGVector(dx: -nrm.dx, dy: -nrm.dy) }   // press upwards, from the sole towards the shoe
        let half = p.map { abs(($0.x - c.x) * u.dx + ($0.y - c.y) * u.dy) }.max() ?? 20
        return (c, u, nrm, half)
    }

    // MARK: Drawing

    static func draw(_ ctx: inout GraphicsContext, size sz: CGSize, segment: Segment, kind: ShoeStepKind, time t: Double, clip: CGRect? = nil) {
        if let clip { ctx.clip(to: Path(roundedRect: clip.insetBy(dx: 14, dy: 14), cornerRadius: 10)) }
        let pts = contour(of: segment, in: sz)
        guard pts.count >= 3 else { return }
        var path = Path()
        path.move(to: pts[0])
        for q in pts.dropFirst() { path.addLine(to: q) }
        path.closeSubpath()
        let amber = Theme.caution

        // glue band: a calm translucent strip along the contour, no hatch, no extra marks
        let w: CGFloat = max(12, min(sz.width, sz.height) * 0.035)
        let band = path.strokedPath(StrokeStyle(lineWidth: w, lineJoin: .round))
        ctx.fill(band, with: .color(amber.opacity(kind.glue ? 0.30 : 0.18)))

        // press arrows perpendicular to the sole edge
        if kind.press {
            let ax = axes(pts)
            let bounce = CGFloat(sin(t * 4) * 4 + 4)
            for f in [-0.6, 0, 0.6] as [CGFloat] {
                let base = CGPoint(x: ax.center.x + ax.along.dx * ax.half * f, y: ax.center.y + ax.along.dy * ax.half * f)
                let tip = CGPoint(x: base.x + ax.normal.dx * (6 + bounce), y: base.y + ax.normal.dy * (6 + bounce))
                let tailP = CGPoint(x: tip.x - ax.normal.dx * 34, y: tip.y - ax.normal.dy * 34)
                // everything sits below the band and points up at it
                arrow(&ctx, from: CGPoint(x: tailP.x - ax.normal.dx * 14, y: tailP.y - ax.normal.dy * 14),
                      to: CGPoint(x: tip.x - ax.normal.dx * 14, y: tip.y - ax.normal.dy * 14), dir: ax.normal)
            }
        }
    }

    private static func arrow(_ ctx: inout GraphicsContext, from a: CGPoint, to b: CGPoint, dir: CGVector) {
        var p = Path()
        p.move(to: a); p.addLine(to: b)
        let side = CGVector(dx: -dir.dy, dy: dir.dx), h: CGFloat = 11
        p.move(to: CGPoint(x: b.x - dir.dx * h + side.dx * h * 0.7, y: b.y - dir.dy * h + side.dy * h * 0.7))
        p.addLine(to: b)
        p.addLine(to: CGPoint(x: b.x - dir.dx * h - side.dx * h * 0.7, y: b.y - dir.dy * h - side.dy * h * 0.7))
        ctx.stroke(p, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }
}

/// Tap-to-start countdown ring for curing / pressing times.
struct CureRing: View {
    let minutes: Int?
    var label: String
    @State private var startedAt: Date?
    @State private var pausedRemaining: Double?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.staticRendering) private var staticRendering
    private var reduceMotion: Bool { systemReduceMotion || staticRendering }

    private var total: Double { Double((minutes ?? 10) * 60) }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { tl in
            let remaining = remainingSeconds(at: tl.date)
            let frac = total > 0 ? remaining / total : 0
            let done = startedAt != nil && remaining <= 0
            Button { toggle(at: tl.date) } label: {
                ZStack {
                    Circle().fill(.black.opacity(0.55))
                    Circle().stroke(.white.opacity(0.2), lineWidth: 6)
                    Circle().trim(from: 0, to: frac).stroke(done ? Theme.highlight : Theme.caution, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90)).animation(reduceMotion ? nil : .linear(duration: 0.5), value: frac)
                    VStack(spacing: 0) {
                        Text(done ? tr("Fertig") : Self.format(remaining)).font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
                        Text(startedAt == nil && pausedRemaining == nil ? tr("Start") : label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.75))
                    }
                }
                .frame(width: 84, height: 84)
            }
            .buttonStyle(.plain)
        }
        .accessibilityLabel("Countdown \(label)")
        .accessibilityValue(Self.format(remainingSeconds(at: .now)))
        .accessibilityHint("Tippen zum Starten oder Pausieren")
    }

    private func remainingSeconds(at now: Date) -> Double {
        if let s = startedAt { return max(0, (pausedRemaining ?? total) - now.timeIntervalSince(s)) }
        return pausedRemaining ?? total
    }

    private func toggle(at now: Date) {
        Haptics.tap()
        if startedAt != nil { pausedRemaining = remainingSeconds(at: now); startedAt = nil }
        else { startedAt = now }
    }

    static func format(_ s: Double) -> String {
        let t = Int(s.rounded(.up)); return String(format: "%d:%02d", t / 60, t % 60)
    }
}
