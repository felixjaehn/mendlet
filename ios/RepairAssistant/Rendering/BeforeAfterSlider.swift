import SwiftUI

enum SliderMath {
    /// Both layers are drawn into exactly this rect so features line up at the divider.
    static func layerFrame(container: CGSize) -> CGRect { CGRect(origin: .zero, size: container) }
    /// The handle never reaches the very edge so it stays grabbable.
    static let range: ClosedRange<Double> = 0.03...0.97
    static func clamp(_ f: Double) -> Double {
        guard f.isFinite else { return 0.5 }
        return min(range.upperBound, max(range.lowerBound, f))
    }
    static func fraction(x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return 0.5 }
        return clamp(Double(x / width))
    }
}

/// Draggable before/after comparison (Photoroom): the original on one side, the preview on the other, a hairline divider
/// with a white thumb and tiny caps labels. Fills its container when `aspect` is nil.
struct BeforeAfterSlider: View {
    let before: UIImage
    let after: UIImage
    var aspect: CGFloat? = 1.0
    var cornerRadius: CGFloat = Theme.heroRadius
    var initial: Double = 0.5
    /// true = divider runs left-right (before on top).
    var horizontalSplit = false
    var labels = true
    /// Sweep the divider once when the slider appears.
    var sweepOnAppear = true
    @State private var frac: Double
    @State private var dragging = false
    @State private var hinted = false
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.staticRendering) private var staticRendering
    private var reduceMotion: Bool { systemReduceMotion || staticRendering }

    init(before: UIImage, after: UIImage, aspect: CGFloat? = 1.0, cornerRadius: CGFloat = Theme.heroRadius, initial: Double = 0.5,
         horizontalSplit: Bool = false, labels: Bool = true, sweepOnAppear: Bool = true) {
        self.before = before; self.after = after; self.aspect = aspect; self.cornerRadius = cornerRadius; self.initial = initial
        self.horizontalSplit = horizontalSplit; self.labels = labels; self.sweepOnAppear = sweepOnAppear
        _frac = State(initialValue: SliderMath.clamp(initial))
    }

    var body: some View {
        let core = GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pos = (horizontalSplit ? h : w) * frac
            ZStack(alignment: .topLeading) {
                let lf = SliderMath.layerFrame(container: geo.size)
                layer(after, lf)
                if horizontalSplit {
                    layer(before, lf).mask(alignment: .top) { Rectangle().frame(height: pos) }
                    Rectangle().fill(.white).frame(width: w, height: 1.5).shadow(color: .black.opacity(0.3), radius: 2).offset(y: pos - 0.75)
                } else {
                    layer(before, lf).mask(alignment: .leading) { Rectangle().frame(width: pos) }
                    Rectangle().fill(.white).frame(width: 1.5, height: h).shadow(color: .black.opacity(0.3), radius: 2).offset(x: pos - 0.75)
                }
                Circle().fill(.white).frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.25), radius: 6, y: 1)
                    .overlay(Image(systemName: horizontalSplit ? "chevron.up.chevron.down" : "chevron.left.chevron.right")
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(.black))
                    .scaleEffect(dragging ? 1.1 : 1)
                    .position(x: horizontalSplit ? w / 2 : pos, y: horizontalSplit ? pos : h / 2)
                if labels {
                    tag("Before").opacity(frac > 0.2 ? 1 : 0).padding(12).frame(width: w, height: h, alignment: .topLeading)
                    tag("After").opacity(frac < 0.8 ? 1 : 0).padding(12)
                        .frame(width: w, height: h, alignment: horizontalSplit ? .bottomTrailing : .topTrailing)
                }
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging { dragging = true; Haptics.tap() }
                    frac = horizontalSplit ? SliderMath.fraction(x: v.location.y, width: h) : SliderMath.fraction(x: v.location.x, width: w)
                }
                .onEnded { _ in withAnimation(Theme.spring) { dragging = false } })
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: dragging)
        }
        Group {
            if let aspect { core.aspectRatio(aspect, contentMode: .fit) } else { core }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Before and after"))
        .accessibilityValue(tr("%lld percent after", Int((frac * 100).rounded())))
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: frac = SliderMath.clamp(frac + 0.1)
            case .decrement: frac = SliderMath.clamp(frac - 0.1)
            @unknown default: break
            }
        }
        .task {
            guard !hinted, sweepOnAppear, !reduceMotion else { return }
            hinted = true
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeInOut(duration: 0.45)) { frac = SliderMath.clamp(initial - 0.4) }
            try? await Task.sleep(for: .milliseconds(480))
            withAnimation(.easeInOut(duration: 0.45)) { frac = SliderMath.clamp(initial) }
        }
    }

    private func layer(_ img: UIImage, _ f: CGRect) -> some View {
        Image(uiImage: img).resizable()
            .aspectRatio(before.size.width / max(before.size.height, 1), contentMode: .fill)
            .frame(width: f.width, height: f.height).clipped()
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).tracking(0.8).textCase(.uppercase)
            .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
            .background(.black.opacity(0.25), in: Capsule())
            .animation(.easeInOut(duration: 0.2), value: frac > 0.2)
    }
}
