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
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.staticRendering) private var staticRendering
    private var reduceMotion: Bool { systemReduceMotion || staticRendering }
    @State private var holdStart: Date?
    @State private var finished = false

    private var end: Segment? { step.overlay?.fromSegmentId.flatMap { response.segment($0) } }
    private var pad: Segment? { step.overlay?.toSegmentId.flatMap { response.segment($0) } }
    private var wire: Segment? { end.flatMap { SolderStyle.wire(for: $0, in: response.segments) } }
    private var hold: Double { max(1, step.overlay?.holdSeconds ?? 3) }
    /// Loop: route draws from wire to pad (1.4 s), polarity discs pop (0.5 s), rest, fade. Static / Reduce Motion: complete.
    static func phase(time t: Double, animated: Bool) -> (route: Double, pop: Double, alpha: Double) {
        if let f = OverlayDebug.freeze { return (min(1, f / 0.6), f > 0.6 ? 1 : 0, 1) }
        guard animated else { return (1, 1, 1) }
        let cycle = 4.2, u = t.truncatingRemainder(dividingBy: cycle)
        let a = u > cycle - 0.4 ? max(0, 1 - (u - (cycle - 0.4)) / 0.4) : 1
        return (min(1, u / 1.4), min(1, max(0, (u - 1.4) / 0.5)), a)
    }
    private var padPoint: CGPoint? { pad.flatMap { SolderStyle.centroid($0, in: size) } }

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: (reduceMotion || OverlayDebug.freeze != nil) && holdStart == nil)) { tl in
                let t = reduceMotion ? 0.6 : tl.date.timeIntervalSinceReferenceDate
                let frac = holdFraction(at: tl.date)
                Canvas { ctx, sz in
                    Self.draw(&ctx, size: sz, wire: wire, end: end, pad: pad, time: t, animated: !reduceMotion, hold: frac)
                }
            }
            .allowsHitTesting(false)
            // exactly one red "+" and one dark "−" disc
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || OverlayDebug.freeze != nil)) { tl in
                let ph = Self.phase(time: tl.date.timeIntervalSinceReferenceDate, animated: !reduceMotion)
                ZStack(alignment: .topLeading) {
                    ForEach(["+", "-"], id: \.self) { pol in
                        if let seg = response.segments.first(where: { $0.polarity == pol }), let r = SolderStyle.rect(seg, in: size) {
                            let d: CGFloat = 30
                            let x = pol == "+" ? r.minX - d / 2 - 8 : r.maxX + d / 2 + 8
                            PolarityDisc(polarity: pol, diameter: d)
                                .scaleEffect(max(0.001, ph.pop >= 1 ? 1 : Self.popCurve(ph.pop)))
                                .opacity(ph.alpha)
                                .position(x: min(max(x, d / 2 + 4), size.width - d / 2 - 4), y: r.midY)
                        }
                    }
                }
                .frame(width: size.width, height: size.height)
            }
            .allowsHitTesting(false)
            if pad != nil { holdControl }
        }
        .frame(width: size.width, height: size.height)
        .onChange(of: step.n) { holdStart = nil; finished = false; CureActivityController.shared.end() }
        .onDisappear { CureActivityController.shared.end() }
    }

    static func popCurve(_ x: Double) -> Double { let c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2) }

    // MARK: Hold control

    private func holdFraction(at now: Date) -> Double {
        if finished { return 1 }
        guard let s = holdStart else { return 0 }
        return min(1, now.timeIntervalSince(s) / hold)
    }

    private var holdControl: some View {
        let label = finished ? tr("Zinn zugeführt") : (holdStart == nil ? tr("%lld s erhitzen · Zinn zuführen", Int(hold)) : tr("Halten …"))
        return ZStack {
            if let p = padPoint {
                Circle().fill(.clear).frame(width: 64, height: 64).contentShape(Circle())
                    .position(x: p.x, y: p.y)
                    .onTapGesture { start() }
            }
            Button { start() } label: {
                HStack(spacing: 8) {
                    Image(systemName: finished ? "checkmark.circle.fill" : "flame.fill")
                        .foregroundStyle(finished ? Theme.highlight : Theme.caution)
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
        CureActivityController.shared.start(itemName: ProjectTitle.title(summary: response.diagnosis.summary, english: Lang.shared.isEnglish),
                                            stepTitle: step.title, kind: .solder, seconds: secs)
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
        // One white style: outlines of wire, bare end and pad, one route with an arrow,
        // a progress ring only while the hold timer runs. Polarity discs are drawn by the view.
        func outline(_ seg: Segment, corner: CGFloat, dashed: Bool = false) {
            let rings = SegmentLayer.ringPaths(for: seg, in: sz)
            var all = Path(); for r in rings { all.addPath(r.path) }
            if rings.isEmpty, let r = SolderStyle.rect(seg, in: sz) { all = Path(roundedRect: r, cornerRadius: corner) }
            ctx.stroke(all, with: .color(.white.opacity(0.35)), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
        if let wire { outline(wire, corner: 6) }
        if let end { outline(end, corner: 8, dashed: true) }
        if let pad { outline(pad, corner: 6) }

        guard let a = end.flatMap({ SolderStyle.centroid($0, in: sz) }), let b = pad.flatMap({ SolderStyle.centroid($0, in: sz) }) else { return }

        // route end -> pad: 2 pt white, 8 pt arrow head before the pad
        let dx = b.x - a.x, dy = b.y - a.y, len = max(1, hypot(dx, dy))
        var nrm = CGVector(dx: -dy / len, dy: dx / len)
        if nrm.dy > 0 { nrm = CGVector(dx: -nrm.dx, dy: -nrm.dy) }   // bulge upwards
        let ctrl = CGPoint(x: (a.x + b.x) / 2 + nrm.dx * len * 0.2, y: (a.y + b.y) / 2 + nrm.dy * len * 0.2)
        var route = Path()
        route.move(to: a); route.addQuadCurve(to: b, control: ctrl)
        let ph = phase(time: t, animated: animated)
        ctx.opacity = ph.alpha
        let shown = ph.route >= 1 ? route : route.trimmedPath(from: 0, to: max(0.001, ph.route))
        ctx.stroke(shown, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        ctx.stroke(shown, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        // entry dot on the wire end; a bright head while the route is still drawing
        ctx.fill(Path(ellipseIn: CGRect(x: a.x - 3.5, y: a.y - 3.5, width: 7, height: 7)), with: .color(.white))
        ctx.stroke(Path(ellipseIn: CGRect(x: a.x - 3.5, y: a.y - 3.5, width: 7, height: 7)), with: .color(.black.opacity(0.4)), lineWidth: 1)
        if ph.route < 1, let h = shown.currentPoint {
            ctx.fill(Path(ellipseIn: CGRect(x: h.x - 4.5, y: h.y - 4.5, width: 9, height: 9)), with: .color(.white))
            ctx.stroke(Path(ellipseIn: CGRect(x: h.x - 4.5, y: h.y - 4.5, width: 9, height: 9)), with: .color(.black.opacity(0.4)), lineWidth: 1)
        }
        guard ph.route >= 0.97 else { return }
        let tv = CGVector(dx: b.x - ctrl.x, dy: b.y - ctrl.y), tl = max(1, hypot(tv.dx, tv.dy))
        let u = CGVector(dx: tv.dx / tl, dy: tv.dy / tl), sd = CGVector(dx: -u.dy, dy: u.dx), h: CGFloat = 8
        let tip = CGPoint(x: b.x - u.dx * 14, y: b.y - u.dy * 14)
        var head = Path()
        head.move(to: CGPoint(x: tip.x - u.dx * h + sd.dx * h * 0.7, y: tip.y - u.dy * h + sd.dy * h * 0.7))
        head.addLine(to: tip)
        head.addLine(to: CGPoint(x: tip.x - u.dx * h - sd.dx * h * 0.7, y: tip.y - u.dy * h - sd.dy * h * 0.7))
        ctx.stroke(head, with: .color(.black.opacity(0.25)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
        ctx.stroke(head, with: .color(.white), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        // hold progress ring, only while the timer runs
        if hold > 0 {
            let R: CGFloat = 26
            ctx.stroke(Path(ellipseIn: CGRect(x: b.x - R, y: b.y - R, width: R * 2, height: R * 2)), with: .color(.white.opacity(0.35)), lineWidth: 2)
            var arc = Path()
            arc.addArc(center: b, radius: R, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * hold), clockwise: false)
            ctx.stroke(arc, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
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
        switch SolderStyle.tone(s) { case .red: SolderStyle.red; case .black: Color(hex: 0x4A5058); case .other: Theme.highlight }
    }
}
