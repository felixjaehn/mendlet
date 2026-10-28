import SwiftUI

enum SliderMath {
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

/// Draggable before/after comparison: original photo on the left, Muse Image preview on the right.
struct BeforeAfterSlider: View {
    let before: UIImage
    let after: UIImage
    var aspect: CGFloat = 1.0
    var initial: Double = 0.5
    @State private var frac: Double
    @State private var dragging = false
    @State private var hinted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(before: UIImage, after: UIImage, aspect: CGFloat = 1.0, initial: Double = 0.5) {
        self.before = before; self.after = after; self.aspect = aspect; self.initial = initial
        _frac = State(initialValue: SliderMath.clamp(initial))
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, x = w * frac
            ZStack(alignment: .topLeading) {
                Image(uiImage: after).resizable().scaledToFill().frame(width: w, height: h).clipped()
                Image(uiImage: before).resizable().scaledToFill().frame(width: w, height: h).clipped()
                    .mask(alignment: .leading) { Rectangle().frame(width: x) }
                // divider + knob
                Rectangle().fill(.white).frame(width: 2, height: h)
                    .shadow(color: .black.opacity(0.35), radius: 3).offset(x: x - 1)
                Circle().fill(.white).frame(width: 44, height: 44)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 2)
                    .overlay(Image(systemName: "arrow.left.and.right").font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.thread))
                    .scaleEffect(dragging ? 1.1 : 1)
                    .position(x: x, y: h / 2)
                // side chips
                tag("Vorher").opacity(frac > 0.2 ? 1 : 0).padding(12)
                tag("Nachher").opacity(frac < 0.8 ? 1 : 0).frame(width: w, alignment: .trailing).padding(.trailing, 12).padding(.top, 12)
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.caption.weight(.bold))
                    Text("Vorschau · Muse Image").font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 7)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(12).frame(width: w, height: h, alignment: .bottomLeading)
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if !dragging { dragging = true; Haptics.tap() }
                    frac = SliderMath.fraction(x: v.location.x, width: w)
                }
                .onEnded { _ in withAnimation(Theme.spring) { dragging = false } })
            .animation(.interactiveSpring(response: 0.18, dampingFraction: 0.9), value: dragging)
        }
        .aspectRatio(aspect, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vorher-Nachher-Vergleich, Vorschau von Muse Image")
        .accessibilityValue("\(Int((frac * 100).rounded())) Prozent Nachher")
        .accessibilityAdjustableAction { dir in
            switch dir {
            case .increment: frac = SliderMath.clamp(frac + 0.1)
            case .decrement: frac = SliderMath.clamp(frac - 0.1)
            @unknown default: break
            }
        }
        .task {
            guard !hinted, !reduceMotion else { return }
            hinted = true
            try? await Task.sleep(for: .milliseconds(500))
            withAnimation(.easeInOut(duration: 0.7)) { frac = SliderMath.clamp(initial + 0.18) }
            try? await Task.sleep(for: .milliseconds(750))
            withAnimation(.easeInOut(duration: 0.8)) { frac = SliderMath.clamp(initial - 0.18) }
            try? await Task.sleep(for: .milliseconds(850))
            withAnimation(.easeInOut(duration: 0.6)) { frac = SliderMath.clamp(initial) }
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.caption.weight(.bold)).textCase(.uppercase).tracking(0.5)
            .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 5)
            .background(.black.opacity(0.45), in: Capsule())
            .animation(.easeInOut(duration: 0.2), value: frac > 0.2)
    }
}

/// Before/after card driven by the flow: shimmer while Muse Image works, slider when ready, nothing if unavailable.
struct BeforeAfterCard: View {
    @Environment(FlowModel.self) private var flow
    var aspect: CGFloat = 1.0

    var body: some View {
        Group {
            if let photo = flow.photo {
                switch flow.afterState {
                case .idle, .loading:
                    placeholder(photo).transition(.opacity)
                case .ready:
                    if let after = flow.afterImage {
                        VStack(spacing: 10) {
                            BeforeAfterSlider(before: photo, after: after, aspect: aspect)
                            EstimatePill(text: "So könnte es aussehen – keine Garantie")
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    }
                case .unavailable:
                    EmptyView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.45), value: flow.afterState)
    }

    private func placeholder(_ photo: UIImage) -> some View {
        Color.clear.aspectRatio(aspect, contentMode: .fit).overlay {
          ZStack {
            Image(uiImage: photo).resizable().scaledToFill().blur(radius: 22).overlay(Color.black.opacity(0.35))
            VStack(spacing: 12) {
                Image(systemName: "sparkles").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                Text("Muse Image zeigt, wie es repariert aussieht")
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                ProgressView().tint(.white)
            }
            .padding(.horizontal, 32)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shimmer()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Muse Image erstellt eine Vorschau der Reparatur")
    }
}
