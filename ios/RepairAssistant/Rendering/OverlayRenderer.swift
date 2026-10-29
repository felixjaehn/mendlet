import SwiftUI

/// Photo with an aspect-fit image plus an overlay area that matches the image rect exactly.
struct PhotoStage<Overlay: View>: View {
    let image: UIImage
    var cornerRadius: CGFloat = 24
    var dim: Double = 0
    var minAspect: CGFloat = 0.9
    /// Normalized photo region to zoom to (small damage, see `DamageFocus`). Nil = whole photo, no gestures.
    var focus: CGRect? = nil
    /// Overlay is drawn at the zoomed size, so strokes and label pins stay crisp instead of being scaled up.
    @ViewBuilder var overlay: (CGSize) -> Overlay
    @State private var zoomedOut = false
    @State private var pinch: CGFloat = 1
    @GestureState private var livePinch: CGFloat = 1
    @Environment(\.staticRendering) private var staticRendering

    var body: some View {
        GeometryReader { geo in
            let fit = AspectFit.rect(content: image.size, in: geo.size)
            let z = zoom(fit: fit.size, stage: geo.size)
            let size = CGSize(width: fit.width * z, height: fit.height * z)
            let center = zoomCenter(fit: fit, stage: geo.size, z: z)
            ZStack(alignment: .topLeading) {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height).clipped()
                    .blur(radius: 24).overlay(Color.black.opacity(0.45))
                Image(uiImage: image).resizable()
                    .frame(width: size.width, height: size.height)
                    .overlay(Color.black.opacity(dim))
                    .position(center)
                overlay(size)
                    .frame(width: size.width, height: size.height)
                    .position(center)
                if focus != nil && !staticRendering { zoomBadge(zoomed: z > 1.01) }
            }
            .animation(.smooth(duration: 0.45), value: zoomedOut)
        }
        .aspectRatio(min(1.5, max(minAspect, image.size.width / max(image.size.height, 1))), contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .simultaneousGesture(MagnifyGesture()
            .updating($livePinch) { v, st, _ in st = v.magnification }
            .onEnded { v in pinch = min(2.5, max(0.4, pinch * v.magnification)) }, including: focus == nil ? .none : .all)
        .onTapGesture(count: 2) { if focus != nil { zoomedOut.toggle(); pinch = 1; Haptics.selection() } }
    }

    private func zoom(fit: CGSize, stage: CGSize) -> CGFloat {
        guard let f = focus, f.width > 0, f.height > 0 else { return 1 }
        let user = pinch * livePinch
        if zoomedOut { return max(1, min(4, user)) }
        let auto = min(stage.width / (f.width * fit.width), stage.height / (f.height * fit.height))
        return max(1, min(4, min(DamageFocus.maxZoom, auto) * user))
    }

    /// Centre of the zoomed image so the focus sits mid-stage, clamped so no blurred edge shows when the image covers the stage.
    private func zoomCenter(fit: CGRect, stage: CGSize, z: CGFloat) -> CGPoint {
        guard z > 1.001, let f = focus else { return CGPoint(x: fit.midX, y: fit.midY) }
        let w = fit.width * z, h = fit.height * z
        func axis(_ c: CGFloat, _ len: CGFloat, _ stageLen: CGFloat) -> CGFloat {
            let p = stageLen / 2 - (c - 0.5) * len
            return len >= stageLen ? min(len / 2, max(stageLen - len / 2, p)) : stageLen / 2
        }
        return CGPoint(x: axis(f.midX, w, stage.width), y: axis(f.midY, h, stage.height))
    }

    private func zoomBadge(zoomed: Bool) -> some View {
        Button {
            zoomedOut.toggle(); pinch = 1; Haptics.selection()
        } label: {
            Label(zoomed ? tr("Whole photo") : tr("Zoom to damage"),
                  systemImage: zoomed ? "arrow.down.right.and.arrow.up.left" : "plus.magnifyingglass")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .glass(Capsule(), interactive: true)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .accessibilityHint(tr("Double-tap the photo to switch as well"))
    }
}

/// Small damage is hard to see on a whole-photo view: zoom so the damage fills about a third of the stage.
enum DamageFocus {
    static let maxZoom: CGFloat = 3.5
    /// Damage whose bounds cover less than this share of the photo counts as small.
    static let smallArea: CGFloat = 0.04

    static func region(for segments: [Segment]) -> CGRect? {
        let boxes = segments.filter(\.isDamage).compactMap(\.normalizedBounds).filter { $0.width > 0 && $0.height > 0 }
        guard let first = boxes.first else { return nil }
        let u = boxes.dropFirst().reduce(first) { $0.union($1) }
        guard u.width * u.height < smallArea else { return nil }
        let side = max(0.28, max(u.width, u.height) * 3)
        return CGRect(x: u.midX - side / 2, y: u.midY - side / 2, width: side, height: side)
    }
}
