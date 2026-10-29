import SwiftUI

/// Analysis overlay: a luminous scan beam loops over the photo while analyzing; once segments arrive they are
/// revealed along one sweep (mask clipped to the swept area, contours draw on).
struct ScanRevealView: View {
    let segments: [Segment]
    let size: CGSize
    var isScanning: Bool
    @State private var arrival: Date?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.staticRendering) private var staticRendering
    private var reduceMotion: Bool { systemReduceMotion || staticRendering }

    private let sweep: TimeInterval = 1.7
    private let loop: TimeInterval = 2.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
            let now = tl.date
            let t = segments.isEmpty ? 0 : (arrival.map { now.timeIntervalSince($0) / sweep } ?? 1)
            let reveal: Double? = reduceMotion || t >= 1 ? nil : max(0, t * t * (3 - 2 * t))
            let revealing = !segments.isEmpty && reveal != nil
            let frac = revealing ? (reveal ?? 1) : (now.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: loop) / loop)
            ZStack {
                SegmentOverlayView(segments: segments, size: size, appeared: !segments.isEmpty, showLabels: true, reveal: reveal)
                if isScanning && !reduceMotion { Beam(frac: frac, fade: revealing ? 1 : sin(.pi * frac)) }
            }
        }
        .onAppear { if !segments.isEmpty && arrival == nil { arrival = .distantPast } }
        .onChange(of: segments.isEmpty) { _, empty in arrival = empty ? nil : Date() }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private struct Beam: View {
        let frac: Double, fade: Double
        var body: some View {
            Canvas { ctx, sz in
                let y = sz.height * frac, trail: CGFloat = 120
                let band = CGRect(x: 0, y: y - trail, width: sz.width, height: trail + 16)
                ctx.blendMode = .plusLighter
                ctx.fill(Path(band), with: .linearGradient(
                    Gradient(stops: [.init(color: .clear, location: 0), .init(color: Theme.highlight.opacity(0.30), location: 0.88),
                                     .init(color: Color.white.opacity(0.22), location: 0.93), .init(color: .clear, location: 1)]),
                    startPoint: CGPoint(x: 0, y: band.minY), endPoint: CGPoint(x: 0, y: band.maxY)))
                let line = Path(CGRect(x: 0, y: y - 0.75, width: sz.width, height: 1.5))
                ctx.drawLayer { l in l.addFilter(.blur(radius: 4)); l.fill(line, with: .color(Theme.highlight.opacity(0.9))) }
                ctx.fill(line, with: .linearGradient(
                    Gradient(colors: [.clear, .white.opacity(0.95), .white.opacity(0.95), .clear]),
                    startPoint: CGPoint(x: 0, y: y), endPoint: CGPoint(x: sz.width, y: y)))
            }
            .opacity(fade)
        }
    }
}
