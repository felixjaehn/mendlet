import SwiftUI

/// Colours and helpers shared by the electronics overlays.
enum SolderStyle {
    static let red = Color(hex: 0xE5322D)
    static let dark = Color(hex: 0x23272F)
    static let copper = Color(hex: 0xE59A45)

    /// Pad colour by polarity: + red, − dark. Nil without polarity.
    static func padColor(_ polarity: String?) -> Color? {
        switch polarity { case "+": red; case "-": dark; default: nil }
    }

    static func isWire(_ s: Segment) -> Bool {
        let t = (s.label + " " + s.prompt).lowercased()
        guard !s.isDamage, !t.contains("strand"), !t.contains("abisol") else { return false }
        return ["wire", "kabel", "leitung", "litze", "cable"].contains { t.contains($0) }
    }

    enum WireTone { case red, black, other }
    static func tone(_ s: Segment) -> WireTone {
        let t = (s.label + " " + s.prompt).lowercased()
        if t.contains("red") || t.contains("rot") { return .red }
        if t.contains("black") || t.contains("schwarz") { return .black }
        return .other
    }

    static func rect(_ s: Segment, in size: CGSize) -> CGRect? {
        (s.normalizedBounds ?? s.normalizedBox).map {
            CGRect(x: $0.minX * size.width, y: $0.minY * size.height, width: $0.width * size.width, height: $0.height * size.height)
        }
    }

    /// Area-weighted centroid of the largest outer ring in pixels, else the box centre.
    static func centroid(_ s: Segment, in size: CGSize) -> CGPoint? {
        let pts = ShoeOverlay.contour(of: s, in: size)
        guard pts.count >= 3 else { return rect(s, in: size).map { CGPoint(x: $0.midX, y: $0.midY) } }
        var a: CGFloat = 0, cx: CGFloat = 0, cy: CGFloat = 0
        for i in 0..<pts.count {
            let p = pts[i], q = pts[(i + 1) % pts.count]
            let f = p.x * q.y - q.x * p.y
            a += f; cx += (p.x + q.x) * f; cy += (p.y + q.y) * f
        }
        guard abs(a) > 0.001 else { return rect(s, in: size).map { CGPoint(x: $0.midX, y: $0.midY) } }
        return CGPoint(x: cx / (3 * a), y: cy / (3 * a))
    }

    /// The wire (red/black) whose bounds overlap the bare end, nearest first.
    static func wire(for end: Segment, in all: [Segment]) -> Segment? {
        guard let eb = end.normalizedBounds else { return nil }
        let grown = eb.insetBy(dx: -0.02, dy: -0.02)
        return all.filter { isWire($0) && ($0.normalizedBounds?.intersects(grown) ?? false) }
            .min { dist($0, eb) < dist($1, eb) }
    }
    private static func dist(_ s: Segment, _ r: CGRect) -> CGFloat {
        guard let b = s.normalizedBounds else { return .infinity }
        return hypot(b.midX - r.midX, b.midY - r.midY)
    }
}

/// Round +/− badge: + red, − dark with a white rim.
struct PolarityDisc: View {
    let polarity: String
    var diameter: CGFloat = 40

    var body: some View {
        let plus = polarity == "+"
        ZStack {
            Circle().fill(SolderStyle.padColor(polarity) ?? .gray)
            Circle().strokeBorder(.white, lineWidth: max(1, diameter * 0.06))
            Image(systemName: plus ? "plus" : "minus")
                .font(.system(size: diameter * 0.52, weight: .heavy)).foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: .black.opacity(0.35), radius: diameter * 0.1, y: 1)
        .accessibilityHidden(true)
    }
}

/// Solder step: wire glows in its colour, bare end pulses, a dashed route leads to the pad (with polarity badge),
/// a soldering-iron tip sits on the pad and a tap-to-start hold ring counts the heating time.
struct SolderOverlay: View {
    let step: GuideStep
    let response: AnalyzeResponse
    let size: CGSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var holdStart: Date?
    @State private var finished = false

    private var end: Segment? { step.overlay?.fromSegmentId.flatMap { response.segment($0) } }
    private var pad: Segment? { step.overlay?.toSegmentId.flatMap { response.segment($0) } }
    private var wire: Segment? { end.flatMap { SolderStyle.wire(for: $0, in: response.segments) } }
    private var hold: Double { max(1, step.overlay?.holdSeconds ?? 3) }
    private var padPoint: CGPoint? { pad.flatMap { SolderStyle.centroid($0, in: size) } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion && holdStart == nil)) { tl in
                let t = reduceMotion ? 0.6 : tl.date.timeIntervalSinceReferenceDate
                let frac = holdFraction(at: tl.date)
                Canvas { ctx, sz in
                    Self.draw(&ctx, size: sz, wire: wire, end: end, pad: pad, time: t, animated: !reduceMotion, hold: frac)
                }
            }
            .allowsHitTesting(false)
            if let pad, let r = SolderStyle.rect(pad, in: size), let pol = pad.polarity {
                let d: CGFloat = 40
                let x = pol == "+" ? r.minX - d / 2 - 8 : r.maxX + d / 2 + 8
                PolarityDisc(polarity: pol, diameter: d)
                    .position(x: min(max(x, d / 2 + 4), size.width - d / 2 - 4), y: r.midY)
            }
            if pad != nil { holdControl }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: step.n) { holdStart = nil; finished = false }
    }

    // MARK: Hold control

    private func holdFraction(at now: Date) -> Double {
        if finished { return 1 }
        guard let s = holdStart else { return 0 }
        return min(1, now.timeIntervalSince(s) / hold)
    }

    private var holdControl: some View {
        let label = finished ? "Zinn zugeführt" : (holdStart == nil ? "\(Int(hold)) s erhitzen · Zinn zuführen" : "Halten …")
        return ZStack {
            if let p = padPoint {
                Circle().fill(.clear).frame(width: 64, height: 64).contentShape(Circle())
                    .position(x: p.x, y: p.y)
                    .onTapGesture { start() }
            }
            Button { start() } label: {
                HStack(spacing: 8) {
                    Image(systemName: finished ? "checkmark.circle.fill" : "flame.fill")
                        .foregroundStyle(finished ? Theme.safe : Theme.caution)
                    Text(label).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(minHeight: 36)
                .background(Capsule().fill(.black.opacity(0.6)))
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            }
            .buttonStyle(.plain)
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .padding(.bottom, 12)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityHint("Tippen startet die Haltezeit von \(Int(hold)) Sekunden")
    }

    private func start() {
        guard holdStart == nil else { return }
        Haptics.tap()
        finished = false
        let began = Date()
        holdStart = began
        let secs = hold
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(Int(secs * 1000)))
            guard holdStart == began else { return }
            finished = true
            Haptics.success()
            try? await Task.sleep(for: .seconds(2.5))
            if holdStart == began { holdStart = nil; finished = false }
        }
    }

    // MARK: Drawing

    static func draw(_ ctx: inout GraphicsContext, size sz: CGSize, wire: Segment?, end: Segment?, pad: Segment?,
                     time t: Double, animated: Bool, hold: Double) {
        let pulse = 0.5 + 0.5 * sin(t * 5)

        // 1. wire mask in its own colour
        if let wire {
            let tone = SolderStyle.tone(wire)
            let fill: Color = tone == .red ? SolderStyle.red : (tone == .black ? .black : Theme.thread)
            let edge: Color = tone == .black ? .white : fill
            var all = Path(); for r in SegmentLayer.ringPaths(for: wire, in: sz) { all.addPath(r.path) }
            ctx.fill(all, with: .color(fill.opacity(tone == .black ? 0.5 : 0.38)), style: FillStyle(eoFill: true))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 5))
                l.stroke(all, with: .color(edge.opacity(tone == .black ? 0.75 : 0.85)), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            }
            ctx.stroke(all, with: .color(edge.opacity(0.95)), style: StrokeStyle(lineWidth: 1.8, lineJoin: .round))
        }

        // 2. bare end pulses
        if let end {
            let rings = SegmentLayer.ringPaths(for: end, in: sz)
            var all = Path(); for r in rings { all.addPath(r.path) }
            if rings.isEmpty, let r = SolderStyle.rect(end, in: sz) { all = Path(roundedRect: r, cornerRadius: 8) }
            ctx.fill(all, with: .color(SolderStyle.copper.opacity(0.25 + 0.25 * pulse)), style: FillStyle(eoFill: true))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 4 + 4 * pulse))
                l.stroke(all, with: .color(SolderStyle.copper.opacity(0.7 + 0.3 * pulse)), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
            }
            ctx.stroke(all, with: .color(.white.opacity(0.95)), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
            if let c = SolderStyle.centroid(end, in: sz), animated {
                let k = CGFloat((t * 1.2).truncatingRemainder(dividingBy: 1))
                let rr = 8 + 16 * k
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)),
                           with: .color(SolderStyle.copper.opacity(Double(1 - k))), lineWidth: 2)
            }
        }

        // 3. pad
        let padTint = SolderStyle.padColor(pad?.polarity) ?? Theme.thread
        if let pad {
            let rings = SegmentLayer.ringPaths(for: pad, in: sz)
            var all = Path(); for r in rings { all.addPath(r.path) }
            if rings.isEmpty, let r = SolderStyle.rect(pad, in: sz) { all = Path(roundedRect: r, cornerRadius: 6) }
            let isDark = pad.polarity == "-"
            ctx.fill(all, with: .color(padTint.opacity(isDark ? 0.55 : 0.45)), style: FillStyle(eoFill: true))
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 5))
                l.stroke(all, with: .color((isDark ? Color.white : padTint).opacity(0.7 + 0.2 * pulse)), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
            }
            ctx.stroke(all, with: .color(isDark ? .white : padTint), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
        }

        guard let a = end.flatMap({ SolderStyle.centroid($0, in: sz) }), let b = pad.flatMap({ SolderStyle.centroid($0, in: sz) }) else { return }

        // 4. curved, animated route end -> pad
        let dx = b.x - a.x, dy = b.y - a.y, len = max(1, hypot(dx, dy))
        var nrm = CGVector(dx: -dy / len, dy: dx / len)
        if nrm.dy > 0 { nrm = CGVector(dx: -nrm.dx, dy: -nrm.dy) }   // bulge upwards
        let ctrl = CGPoint(x: (a.x + b.x) / 2 + nrm.dx * len * 0.28, y: (a.y + b.y) / 2 + nrm.dy * len * 0.28)
        var route = Path()
        route.move(to: a); route.addQuadCurve(to: b, control: ctrl)
        let phase: CGFloat = animated ? CGFloat(-t * 36) : 0
        ctx.stroke(route, with: .color(.black.opacity(0.4)), style: StrokeStyle(lineWidth: 6.5, lineCap: .round))
        ctx.stroke(route, with: .color(padTint), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, dash: [9, 8], dashPhase: phase))
        ctx.stroke(route, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [9, 8], dashPhase: phase))
        // arrow head near the pad (tangent of the quad at its end)
        let tv = CGVector(dx: b.x - ctrl.x, dy: b.y - ctrl.y), tl = max(1, hypot(tv.dx, tv.dy))
        let u = CGVector(dx: tv.dx / tl, dy: tv.dy / tl), s = CGVector(dx: -u.dy, dy: u.dx), h: CGFloat = 12
        let tip = CGPoint(x: b.x - u.dx * 34, y: b.y - u.dy * 34)
        var head = Path()
        head.move(to: CGPoint(x: tip.x - u.dx * h + s.dx * h * 0.7, y: tip.y - u.dy * h + s.dy * h * 0.7))
        head.addLine(to: tip)
        head.addLine(to: CGPoint(x: tip.x - u.dx * h - s.dx * h * 0.7, y: tip.y - u.dy * h - s.dy * h * 0.7))
        ctx.stroke(head, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
        ctx.stroke(head, with: .color(.white), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

        // 5. hold ring around the pad, 6. iron on top
        let R: CGFloat = 30
        let ring = Path(ellipseIn: CGRect(x: b.x - R, y: b.y - R, width: R * 2, height: R * 2))
        ctx.stroke(ring, with: .color(.black.opacity(0.45)), lineWidth: 7)
        ctx.stroke(ring, with: .color(.white.opacity(0.4)), lineWidth: 4)
        if hold > 0 {
            var arc = Path()
            arc.addArc(center: b, radius: R, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * hold), clockwise: false)
            ctx.stroke(arc, with: .color(hold >= 1 ? Theme.safe : Theme.caution), style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        drawIron(&ctx, at: b, time: t, animated: animated, active: hold > 0 && hold < 1)
    }

    /// Slim iron: tip touches `p`, body leans up-right, glowing tip.
    private static func drawIron(_ ctx: inout GraphicsContext, at p: CGPoint, time t: Double, animated: Bool, active: Bool) {
        let dir = CGVector(dx: 0.55, dy: -0.835)    // from the tip upwards
        let hover: CGFloat = animated ? CGFloat(sin(t * 3)) * 1.5 : 0
        let tip = CGPoint(x: p.x + dir.dx * hover, y: p.y + dir.dy * hover)
        func pt(_ d: CGFloat) -> CGPoint { CGPoint(x: tip.x + dir.dx * d, y: tip.y + dir.dy * d) }
        func seg(_ a: CGFloat, _ b: CGFloat, _ w: CGFloat, _ c: Color) {
            var l = Path(); l.move(to: pt(a)); l.addLine(to: pt(b))
            ctx.stroke(l, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round))
        }
        seg(0, 70, 11, .black.opacity(0.4))
        seg(2, 22, 5, Color(hex: 0xC9CDD3))
        seg(22, 34, 8, Color(hex: 0x6D737D))
        seg(34, 76, 12, Color(hex: 0x2B2F36))
        seg(38, 72, 2, .white.opacity(0.35))
        ctx.drawLayer { l in
            l.addFilter(.blur(radius: active ? 7 : 4))
            l.fill(Path(ellipseIn: CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10)), with: .color(Theme.caution.opacity(active ? 0.95 : 0.6)))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 2.5, y: tip.y - 2.5, width: 5, height: 5)), with: .color(.white))
    }
}

/// Non-solder steps of electronics: all wire, bare-end and pad masks with polarity badges.
struct ElectronicsOverview: View {
    let step: GuideStep
    let response: AnalyzeResponse
    let size: CGSize

    var body: some View {
        let shown = response.segments.filter { $0.polarity != nil || $0.isDamage || SolderStyle.isWire($0) }
        let focus = Set(step.segmentIds)
        ZStack(alignment: .topLeading) {
            ForEach(shown) { s in
                let color: Color = SolderStyle.padColor(s.polarity) ?? (s.isDamage ? SolderStyle.copper : wireColor(s))
                SegmentLayer(segment: s, color: color, size: size, visible: true, pulsing: s.isDamage && (focus.isEmpty || focus.contains(s.id)), showLabel: false)
                    .opacity(focus.isEmpty || focus.contains(s.id) ? 1 : 0.45)
            }
            ForEach(shown.filter { $0.polarity != nil }) { s in
                if let r = SolderStyle.rect(s, in: size), let pol = s.polarity {
                    let d: CGFloat = 30
                    let x = pol == "+" ? r.minX - d / 2 - 6 : r.maxX + d / 2 + 6
                    PolarityDisc(polarity: pol, diameter: d)
                        .position(x: min(max(x, d / 2 + 4), size.width - d / 2 - 4), y: r.midY)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func wireColor(_ s: Segment) -> Color {
        switch SolderStyle.tone(s) { case .red: SolderStyle.red; case .black: Color(hex: 0x4A5058); case .other: Theme.thread }
    }
}
