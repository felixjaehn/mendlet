import SwiftUI

/// The user's own photo with the damage marked: scrim with a lifted cut-out, a thin white contour, a typographic label.
/// One component for Analysis (reveal), Finding, Verdict, Guide, Home and Project (docs/design/REDESIGN-SPEC.md section 4).
struct MarkedPhoto<Overlay: View>: View {
    enum Mode: Equatable {
        /// Final state: scrim, interior tint, outline, label.
        case resting
        /// Analysis: `arrival` nil = waiting (scan sweep loops), otherwise the reveal runs from that date.
        case analysis(arrival: Date?)
        /// Static outline only (Home, Project cards).
        case thumb
        /// Guide step: light scrim, outline, no label.
        case guide
    }

    let image: UIImage
    var segments: [Segment]
    var mode: Mode = .resting
    var showLabels = true
    var showDimension = false
    /// Normalized region to zoom to (small damage). Nil = no zoom.
    var focus: CGRect? = nil
    /// Tap in normalized photo coordinates (tap to refine).
    var onTap: ((CGPoint) -> Void)? = nil
    var zoomable = true
    @ViewBuilder var overlay: (CGSize) -> Overlay

    @State private var zoomedOut = false
    @State private var ripple: (point: CGPoint, date: Date)?
    @State private var revealDone = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static var revealDuration: Double { 3.6 }

    var body: some View {
        GeometryReader { geo in
            content(container: geo.size)
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Damage outlined on your photo"))
        .accessibilityAddTraits(.isImage)
        .onTapGesture(count: 2) { if focus != nil, zoomable { withAnimation(.smooth(duration: 0.45)) { zoomedOut.toggle() }; Haptics.selection() } }
        .task(id: mode) {
            revealDone = false
            guard case .analysis(let arrival?) = mode else { return }
            // soft haptic when the outline starts to draw, then once more when it closes and the label arrives
            try? await Task.sleep(for: .seconds(max(0, arrival.timeIntervalSinceNow + 0.95)))
            if !Task.isCancelled { Haptics.soft() }
            let wait = max(0, arrival.timeIntervalSinceNow + 2.6 + 0.12 * Double(max(damage.count - 1, 0)))
            try? await Task.sleep(for: .seconds(wait))
            if !Task.isCancelled { Haptics.soft() }
            try? await Task.sleep(for: .seconds(max(0, arrival.timeIntervalSinceNow + Self.revealDuration)))
            if !Task.isCancelled { revealDone = true }
        }
    }

    private var damage: [Segment] { segments.filter(\.isDamage) }

    @ViewBuilder private func content(container: CGSize) -> some View {
        let animating: Bool = {
            if reduceMotion { return false }
            if case .analysis(let a) = mode { return a == nil || !revealDone }
            return false
        }()
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animating)) { tl in
            let state = frameState(now: tl.date)
            ZoomedStage(image: image, segments: segments, damage: damage, container: container, state: state,
                        zoom: zoomedOut ? 1 : Self.targetZoom(image: image, focus: focus, container: container), focusCenter: focusCenter, showLabels: showLabels && mode != .thumb && mode != .guide,
                        showDimension: showDimension, ripple: ripple, onTap: onTap.map { cb in { p in
                            ripple = (p, Date()); cb(p)
                        } }, overlay: overlay)
        }
    }

    private var focusCenter: CGPoint? {
        if let f = focus { return CGPoint(x: f.midX, y: f.midY) }
        let boxes = damage.compactMap(\.normalizedBounds)
        guard let first = boxes.first else { return nil }
        let u = boxes.dropFirst().reduce(first) { $0.union($1) }
        return CGPoint(x: u.midX, y: u.midY)
    }

    // MARK: Timeline

    typealias FrameState = MarkFrameState

    private func ease(_ x: Double) -> Double { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
    private func easeOut(_ x: Double) -> Double { let c = min(1, max(0, x)); return 1 - pow(1 - c, 3) }

    private func frameState(now: Date) -> FrameState {
        var s = FrameState()
        let n = max(damage.count, 1)
        switch mode {
        case .resting:
            s.outline = Array(repeating: 1, count: n)
        case .thumb:
            s.scrim = 0; s.tint = 0; s.drawsHole = false; s.strokeWidth = 1.25
            s.outline = Array(repeating: 1, count: n)
        case .guide:
            s.scrim = 0.22; s.tint = 0
            s.outline = Array(repeating: 1, count: n)
        case .analysis(let arrival):
            if reduceMotion { s.outline = Array(repeating: 1, count: n); break }
            guard let arrival else {
                // waiting: even scrim, a scan band travels top to bottom and loops
                let loop = 2.6, p = now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop) / loop
                s.scrim = 0.30; s.outline = Array(repeating: 0, count: n); s.tint = 0; s.label = 0
                s.drawsHole = false; s.sweep = ease(p); s.zoomMix = 0
                break
            }
            let t = now.timeIntervalSince(arrival)
            s.scrim = 0.30 * easeOut(t / 0.5)
            s.sweep = t >= 0.2 && t <= 1.3 ? ease((t - 0.2) / 1.1) : nil
            s.outline = (0..<n).map { ease((t - 0.9 - 0.12 * Double($0)) / 1.7) }
            s.tint = 0.10 * ease((t - 2.2) / 0.5)
            s.holeScale = 0.96 + 0.04 * CGFloat(easeOut((t - 2.2) / 0.6))
            s.label = ease((t - 2.7) / 0.5)
            s.zoomMix = ease((t - 0.9) / 0.9)
        }
        return s
    }
}

extension MarkedPhoto where Overlay == EmptyView {
    init(image: UIImage, segments: [Segment], mode: Mode = .resting, showLabels: Bool = true, showDimension: Bool = false,
         focus: CGRect? = nil, onTap: ((CGPoint) -> Void)? = nil, zoomable: Bool = true) {
        self.init(image: image, segments: segments, mode: mode, showLabels: showLabels, showDimension: showDimension, focus: focus,
                  onTap: onTap, zoomable: zoomable, overlay: { _ in EmptyView() })
    }
}

struct MarkFrameState {
    var scrim: Double = 0.30        // 0...0.30 opacity of the dimming layer
    var holeScale: CGFloat = 1
    var outline: [Double] = []      // per damage segment, 0...1
    var tint: Double = 0.10
    var label: Double = 1
    var sweep: Double? = nil        // 0...1 across the photo, nil = none
    var zoomMix: Double = 1
    var strokeWidth: CGFloat = 1.5
    var drawsHole = true
    var drawsOutline = true
}


// MARK: Stage

/// Draws the photo at its zoomed size and everything on top. `zoom` is animatable so the double-tap toggle interpolates.
private struct ZoomedStage<Overlay: View>: View, @preconcurrency Animatable {
    let image: UIImage
    let segments: [Segment]
    let damage: [Segment]
    let container: CGSize
    let state: MarkFrameState
    var zoom: CGFloat           // used as the "autoZoom" mix target when > 0, see `effective`
    let focusCenter: CGPoint?
    let showLabels: Bool
    let showDimension: Bool
    let ripple: (point: CGPoint, date: Date)?
    let onTap: ((CGPoint) -> Void)?
    @ViewBuilder var overlay: (CGSize) -> Overlay

    var animatableData: CGFloat {
        get { zoom }
        set { zoom = newValue }
    }

    var body: some View {
        let fill = AspectFit.fillSize(content: image.size, in: container)
        let z = effectiveZoom
        let size = CGSize(width: fill.width * z, height: fill.height * z)
        let center = stageCenter(size: size)
        let origin = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        ZStack(alignment: .topLeading) {
            Color(uiColor: .secondarySystemFill)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().frame(width: size.width, height: size.height)
                MarkCanvas(segments: damage, size: size, state: state)
                if showLabels && state.label > 0 {
                    MarkLabels(segments: damage, size: size, visible: CGRect(x: -origin.x, y: -origin.y, width: container.width, height: container.height))
                        .opacity(state.label)
                    if showDimension, let dim = DamageDimension.layout(segments: segments.filter { _ in true }, size: size) {
                        DimensionLineView(layout: dim).opacity(state.label)
                    }
                }
                overlay(size).frame(width: size.width, height: size.height)
                    .environment(\.photoVisibleRect, CGRect(x: -origin.x, y: -origin.y, width: container.width, height: container.height))
                if let onTap {
                    Color.white.opacity(0.001).frame(width: size.width, height: size.height).contentShape(Rectangle())
                        .onTapGesture(coordinateSpace: .local) { p in onTap(CGPoint(x: p.x / size.width, y: p.y / size.height)) }
                }
                if let ripple { RippleView(at: CGPoint(x: ripple.point.x * size.width, y: ripple.point.y * size.height), date: ripple.date) }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .offset(x: origin.x, y: origin.y)
            if let sweep = state.sweep { SweepBand(frac: sweep).frame(width: container.width, height: container.height).allowsHitTesting(false) }
        }
        .frame(width: container.width, height: container.height, alignment: .topLeading)
        .clipped()
    }

    /// Zoom factor relative to the aspect-fill size: `zoom` carries the target (1 = none), `zoomMix` blends toward it while revealing.
    private var effectiveZoom: CGFloat { 1 + (zoom - 1) * CGFloat(state.zoomMix) }

    private func stageCenter(size: CGSize) -> CGPoint {
        let f = focusCenter ?? CGPoint(x: 0.5, y: 0.5)
        func axis(_ c: CGFloat, _ len: CGFloat, _ box: CGFloat) -> CGFloat {
            let p = box / 2 - (c - 0.5) * len
            return len >= box ? min(len / 2, max(box - len / 2, p)) : box / 2
        }
        return CGPoint(x: axis(f.x, size.width, container.width), y: axis(f.y, size.height, container.height))
    }
}

extension MarkedPhoto {
    /// Target zoom for the focus region inside a container (aspect-fill base).
    static func targetZoom(image: UIImage, focus: CGRect?, container: CGSize) -> CGFloat {
        guard let f = focus, f.width > 0, f.height > 0, container.width > 0 else { return 1 }
        let fill = AspectFit.fillSize(content: image.size, in: container)
        let auto = min(container.width / (f.width * fill.width), container.height / (f.height * fill.height))
        return max(1, min(2.6, auto))
    }
}

// MARK: Canvas

private struct MarkCanvas: View {
    let segments: [Segment]
    let size: CGSize
    let state: MarkFrameState

    var body: some View {
        Canvas { ctx, sz in
            var holes = Path()
            var centroids: [CGPoint] = []
            var perSegment: [(Path, [MaskPath.Contour], CGRect?)] = []
            for s in segments {
                let contours = MaskPath.contours(for: s)
                var p = Path()
                if contours.isEmpty, let b = s.normalizedBox {
                    let r = CGRect(x: b.minX * sz.width, y: b.minY * sz.height, width: b.width * sz.width, height: b.height * sz.height)
                    p.addRoundedRect(in: r, cornerSize: CGSize(width: 10, height: 10))
                    perSegment.append((p, [], r))
                } else {
                    for c in contours where c.closed { p.addPath(MaskPath.path(c, in: sz)) }
                    perSegment.append((p, contours, nil))
                }
                holes.addPath(p)
                let r = p.boundingRect
                centroids.append(CGPoint(x: r.midX, y: r.midY))
            }
            // 1. scrim with the lifted cut-out
            if state.scrim > 0.001 {
                ctx.drawLayer { l in
                    l.fill(Path(CGRect(origin: .zero, size: sz)), with: .color(.black.opacity(state.scrim)))
                    if state.drawsHole && !holes.isEmpty {
                        l.blendMode = .destinationOut
                        l.drawLayer { h in
                            h.addFilter(.blur(radius: 1.0))
                            var scaled = Path()
                            for (i, e) in perSegment.enumerated() {
                                let c = centroids[i]
                                let t = CGAffineTransform(translationX: c.x, y: c.y).scaledBy(x: state.holeScale, y: state.holeScale).translatedBy(x: -c.x, y: -c.y)
                                scaled.addPath(e.0, transform: t)
                            }
                            h.fill(scaled, with: .color(.black), style: FillStyle(eoFill: true))
                        }
                    }
                }
            }
            // 2. interior tint
            if state.tint > 0.001 { ctx.fill(holes, with: .color(.white.opacity(state.tint)), style: FillStyle(eoFill: true)) }
            // 3. outline (under-stroke for legibility on pale fabric, then white)
            guard state.drawsOutline else { return }
            for (i, e) in perSegment.enumerated() {
                let prog = i < state.outline.count ? state.outline[i] : (state.outline.last ?? 1)
                guard prog > 0.001 else { continue }
                var line = Path()
                if let r = e.2 {
                    line = bracketPath(r)
                } else {
                    for c in e.1 { line.addPath(MaskPath.path(c, in: sz)) }
                }
                let drawn = prog >= 1 ? line : line.trimmedPath(from: 0, to: max(0.001, prog))
                ctx.drawLayer { l in
                    l.addFilter(.blur(radius: 1))
                    l.stroke(drawn, with: .color(.black.opacity(0.28)), style: StrokeStyle(lineWidth: state.strokeWidth * 2, lineCap: .round, lineJoin: .round))
                }
                ctx.stroke(drawn, with: .color(.white), style: StrokeStyle(lineWidth: state.strokeWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    /// Box-only damage: four corner brackets (Google Lens).
    private func bracketPath(_ r: CGRect) -> Path {
        let l = min(24, max(10, min(r.width, r.height) * 0.28))
        var p = Path()
        for (cx, cy, dx, dy) in [(r.minX, r.minY, 1.0, 1.0), (r.maxX, r.minY, -1.0, 1.0), (r.minX, r.maxY, 1.0, -1.0), (r.maxX, r.maxY, -1.0, -1.0)] {
            p.move(to: CGPoint(x: cx + dx * l, y: cy)); p.addLine(to: CGPoint(x: cx, y: cy)); p.addLine(to: CGPoint(x: cx, y: cy + dy * l))
        }
        return p
    }
}

/// Thin light band with a hairline at its centre sweeping over the photo (BitePal scan line).
private struct SweepBand: View {
    var frac: Double
    var body: some View {
        Canvas { ctx, sz in
            let band: CGFloat = 140
            let y = -band / 2 + (sz.height + band) * frac
            let rect = CGRect(x: 0, y: y - band / 2, width: sz.width, height: band)
            ctx.blendMode = .plusLighter
            ctx.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [.clear, .white.opacity(0.20), .clear]),
                startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)))
            ctx.fill(Path(CGRect(x: 0, y: y - 0.5, width: sz.width, height: 1)),
                     with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.6), .white.opacity(0.6), .clear]),
                                           startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: sz.width, y: y)))
        }
    }
}

private struct RippleView: View {
    let at: CGPoint
    let date: Date
    @State private var go = false
    var body: some View {
        Circle().strokeBorder(.white, lineWidth: 1.5)
            .frame(width: 24, height: 24)
            .scaleEffect(go ? 2.2 : 0.6).opacity(go ? 0 : 1)
            .position(at)
            .onAppear { withAnimation(.easeOut(duration: 0.35)) { go = true } }
            .id(date)
            .allowsHitTesting(false)
    }
}

// MARK: Labels

/// Typographic labels: text with a hairline leader to a dot on the contour. No chips, no scores.
struct MarkLabels: View {
    let segments: [Segment]
    let size: CGSize
    var visible: CGRect? = nil

    var body: some View {
        let placed = LabelPlacer.place(LabelPinsLayer(segments: segments, all: segments, size: size).items(), in: size, clip: visible)
        ZStack(alignment: .topLeading) {
            ForEach(placed) { p in
                let r = p.rect
                let beside = p.dot.y >= r.minY && p.dot.y <= r.maxY
                let tail = beside ? CGPoint(x: p.dot.x < r.midX ? r.minX - 4 : r.maxX + 4, y: r.midY)
                                  : CGPoint(x: min(max(p.dot.x, r.minX + 8), r.maxX - 8), y: p.dot.y < r.midY ? r.minY : r.maxY)
                let dots = p.item.dots.isEmpty ? [p.dot] : p.item.dots
                Path { path in for d in dots { path.move(to: d); path.addLine(to: tail) } }
                    .stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 0.75, lineCap: .round))
                    .shadow(color: .black.opacity(0.35), radius: 1.5)
                ForEach(Array(dots.enumerated()), id: \.offset) { _, d in
                    Circle().fill(.white).frame(width: 4, height: 4).shadow(color: .black.opacity(0.35), radius: 1.5).position(d)
                }
                Text(p.item.text).font(.footnote.weight(.semibold)).foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 2)
                    .lineLimit(1).fixedSize()
                    .position(x: r.midX, y: r.midY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

// MARK: Geometry helpers

extension AspectFit {
    /// Smallest size that covers `box` with the content's aspect ratio.
    static func fillSize(content: CGSize, in box: CGSize) -> CGSize {
        guard content.width > 0, content.height > 0 else { return box }
        let s = max(box.width / content.width, box.height / content.height)
        return CGSize(width: content.width * s, height: content.height * s)
    }
}
