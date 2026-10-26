import SwiftUI

/// Photo with an aspect-fit image plus an overlay area that matches the image rect exactly.
struct PhotoStage<Overlay: View>: View {
    let image: UIImage
    var cornerRadius: CGFloat = 24
    var dim: Double = 0
    @ViewBuilder var overlay: (CGSize) -> Overlay

    var body: some View {
        GeometryReader { geo in
            let fit = AspectFit.rect(content: image.size, in: geo.size)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                    .blur(radius: 24).overlay(Color.black.opacity(0.45))
                Image(uiImage: image).resizable()
                    .frame(width: fit.width, height: fit.height)
                    .overlay(Color.black.opacity(dim))
                    .position(x: fit.midX, y: fit.midY)
                overlay(fit.size)
                    .frame(width: fit.width, height: fit.height)
                    .position(x: fit.midX, y: fit.midY)
            }
        }
        .aspectRatio(min(1.5, max(0.9, image.size.width / max(image.size.height, 1))), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// One segment drawn with Canvas (polygon mask, or box fallback). Fade and pulse are driven from outside.
struct SegmentLayer: View {
    let segment: Segment
    let color: Color
    let size: CGSize
    var visible: Bool = true
    var pulsing: Bool = false
    var showLabel: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !pulsing || reduceMotion)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                let boost = pulsing ? (reduceMotion ? 0.5 : 0.5 + 0.5 * sin(t * 6)) : 0
                Canvas { ctx, sz in
                    let path = Self.path(for: segment, in: sz)
                    guard !path.isEmpty else { return }
                    ctx.fill(path, with: .color(color.opacity(0.25 + 0.30 * boost)))
                    ctx.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2 + 2 * boost, lineJoin: .round))
                }
            }
            if showLabel, let anchor = Self.anchor(for: segment, in: size) {
                Text(segment.label)
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color, in: Capsule())
                    .fixedSize()
                    .position(x: min(max(anchor.x, 30), size.width - 30), y: max(anchor.y - 16, 12))
            }
        }
        .frame(width: size.width, height: size.height)
        .opacity(visible ? 1 : 0)
        .animation(.easeInOut(duration: 0.45), value: visible)
        .accessibilityHidden(true)
    }

    static func path(for s: Segment, in size: CGSize) -> Path {
        var p = Path()
        let poly = s.polygon
        if poly.count >= 3 {
            p.move(to: CGPoint(x: poly[0].x * size.width, y: poly[0].y * size.height))
            for q in poly.dropFirst() { p.addLine(to: CGPoint(x: q.x * size.width, y: q.y * size.height)) }
            p.closeSubpath()
        } else if let b = s.normalizedBox {
            p.addRoundedRect(in: CGRect(x: b.minX * size.width, y: b.minY * size.height, width: b.width * size.width, height: b.height * size.height), cornerSize: CGSize(width: 8, height: 8))
        }
        return p
    }

    static func anchor(for s: Segment, in size: CGSize) -> CGPoint? {
        let b = s.normalizedBox ?? {
            let poly = s.polygon
            guard let f = poly.first else { return nil }
            var r = CGRect(origin: f, size: .zero)
            for q in poly { r = r.union(CGRect(origin: q, size: .zero)) }
            return r
        }()
        guard let b else { return nil }
        return CGPoint(x: b.midX * size.width, y: b.minY * size.height)
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

    var body: some View {
        ZStack {
            ForEach(segments) { s in
                SegmentLayer(segment: s, color: segmentColor(s, in: segments), size: size,
                             visible: appeared && !hidden.contains(s.id), pulsing: pulsingIDs.contains(s.id),
                             showLabel: showLabels && s.isDamage)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}
