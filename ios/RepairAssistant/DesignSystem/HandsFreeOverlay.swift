import SwiftUI

/// Siri style glow around the whole screen: a soft multi-colour light that flows along the edge. Calm while idle,
/// brighter and reactive to the microphone level while the user speaks. Reduce Motion freezes it.
struct HandsFreeGlow: View {
    var phase: HandsFreeModel.Phase
    var level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Answer card shown: same colours, dimmer (0.35 instead of 0.55).
    var answerShown = false

    private static let colors: [Color] = [
        Color(red: 0.55, green: 0.38, blue: 1.00),   // violet
        Color(red: 0.25, green: 0.55, blue: 1.00),   // blue
        Color(red: 0.20, green: 0.80, blue: 1.00),   // cyan
        Color(red: 0.98, green: 0.35, blue: 0.80),   // magenta
        Color(red: 1.00, green: 0.55, blue: 0.25),   // orange
        Color(red: 0.55, green: 0.38, blue: 1.00),   // violet (closes the loop)
    ]

    var body: some View {
        if reduceMotion {
            canvas(t: 0)
        } else {
            TimelineView(.animation) { tl in canvas(t: tl.date.timeIntervalSinceReferenceDate) }
        }
    }

    /// One soft inner stroke: 0.55 opacity (0.35 while the answer card is up), a touch brighter with the mic level.
    private var opacity: Double {
        if phase == .off { return 0 }
        if answerShown { return 0.35 }
        return 0.55 + (phase == .hearing ? 0.15 * Double(level) : 0)
    }

    private func canvas(t: Double) -> some View {
        let k = opacity
        return Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let radius = max(8, UIScreen.main.displayCornerRadiusApprox)
            let width: CGFloat = 16
            // Stroke centred on the display edge: half of it lies off-screen, so it reads as light bleeding inward.
            let inset: CGFloat = 0
            let path = RoundedRectangle(cornerRadius: max(8, radius - inset), style: .continuous).path(in: rect.insetBy(dx: inset, dy: inset))
            let angle = Angle.radians(t * 2 * .pi / 8)   // 8 s per revolution
            ctx.drawLayer { l in
                l.opacity = k
                l.addFilter(.blur(radius: 12))
                l.stroke(path, with: .conicGradient(Gradient(colors: Self.colors), center: CGPoint(x: size.width / 2, y: size.height / 2), angle: angle), lineWidth: width)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private extension UIScreen {
    /// Corner radius of current iPhones (no public API); good enough for a glow that hugs the display edge.
    var displayCornerRadiusApprox: CGFloat { bounds.height >= 800 ? 52 : 12 }
}

/// One Liquid Glass material for the capsule, the answer card and the collapsed bar: thin material, ~12 % white tint,
/// 0.5 pt white 25 % inner stroke and a soft specular top edge.
struct HandsFreeGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    func body(content: Content) -> some View {
        content
            .background(Color.white.opacity(0.12), in: shape)
            .background(.thinMaterial, in: shape)
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.35))).allowsHitTesting(false))
            .overlay(shape.strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5).allowsHitTesting(false))
            .shadow(color: .black.opacity(0.22), radius: 18, y: 6)
    }
}

/// Compact glass capsule above the step panel: luminous orb plus the live state text, or the answer card.
struct HandsFreeCapsule: View {
    var model: HandsFreeModel
    /// Upper bound for the answer card (about 30 % of the screen).
    var maxHeight: CGFloat = 240

    var body: some View {
        Group {
            if let answer = model.answer {
                answerCard(answer)
                    .transition(.scale(scale: 0.94, anchor: .bottom).combined(with: .opacity))
            } else if model.phase != .off {
                capsule
                    .transition(.scale(scale: 0.9, anchor: .bottom).combined(with: .opacity))
            }
        }
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 8)
        .animation(Theme.spring, value: model.phase)
        .animation(Theme.spring, value: model.answer)
        .animation(Theme.spring, value: model.caption.isEmpty)
        .animation(Theme.spring, value: model.notice)
    }

    private var statusText: String {
        if let n = model.notice { return n }
        switch model.phase {
        case .thinking: return "Thinking…"
        case .hearing: return model.caption.isEmpty ? "Listening…" : model.caption
        default: return model.caption.isEmpty ? "Listening…" : model.caption
        }
    }

    private var orbState: OrbState { model.phase == .thinking ? .working : .listening }

    private var capsule: some View {
        let twoLines = statusText.count > 26
        let content = HStack(spacing: 10) {
            ThinkingOrb(state: orbState, size: 72, tempo: model.phase == .hearing ? 1.0 : 0.7, level: model.phase == .hearing ? model.level : 0)
                .frame(width: 76, height: 76)
                .background(Circle().fill(Color.black.opacity(0.45)).overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)).frame(width: 66, height: 66))
            VStack(alignment: .leading, spacing: 2) {
                if model.phase == .thinking, !model.caption.isEmpty, model.notice == nil {
                    Text(model.caption).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Text(statusText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(model.phase == .idle && model.notice == nil && model.caption.isEmpty ? .white.opacity(0.78) : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: 260, alignment: .leading)
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.leading, 6).padding(.trailing, 16).padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusText)
        return HStack(spacing: 0) {
            Group {
                if twoLines { content.modifier(HandsFreeGlass(shape: RoundedRectangle(cornerRadius: 28, style: .continuous))) }
                else { content.modifier(HandsFreeGlass(shape: Capsule())) }
            }
            Spacer(minLength: 0)
        }
    }

    private func answerCard(_ text: String) -> some View {
        Button { model.dismissAnswer() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ThinkingOrb(state: .listening, size: 36, tempo: 0.7).frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.45)).overlay(Circle().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5)).frame(width: 34, height: 34))
                    if !model.caption.isEmpty {
                        Text(model.caption).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Text(text)
                    .font(.system(size: 22, weight: .regular))
                    .lineSpacing(3)
                    .foregroundStyle(.white)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 36)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(HandsFreeGlass(shape: RoundedRectangle(cornerRadius: 28, style: .continuous)))
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint("Double tap to dismiss")
    }
}

/// Where the voice UI (capsule or answer card) goes while hands-free is on. Rects in screen points, container coordinates.
/// Rule: the voice UI never intersects the work area (damage, stitch/glue/solder overlay and their labels).
/// 1. Below the work area and above the collapsed bar if it fits.
/// 2. Otherwise the photo shifts up (`photoShift`) as far as the top reserve allows.
/// 3. Otherwise the voice UI moves onto the collapsed bar area (`overBar`) and the photo shifts up so the work stays clear of it.
enum VoiceLayout {
    struct Placement: Equatable {
        var voice: CGRect
        var photoShift: CGFloat
        var overBar: Bool
        /// The work rect after the photo shift.
        var work: CGRect
    }

    static func place(container: CGSize, work: CGRect, topReserved: CGFloat, barTop: CGFloat, voiceHeight: CGFloat, gap: CGFloat = 12, margin: CGFloat = 20) -> Placement {
        let width = container.width - 2 * margin
        let maxShift = max(0, work.minY - topReserved)
        func result(_ rect: CGRect, _ shift: CGFloat, _ over: Bool) -> Placement {
            Placement(voice: rect, photoShift: shift, overBar: over, work: work.offsetBy(dx: 0, dy: -shift))
        }
        // 1 / 2: above the bar
        let top = barTop - gap - voiceHeight
        let needed = max(0, work.maxY + gap - top)
        if needed <= maxShift {
            return result(CGRect(x: margin, y: top, width: width, height: voiceHeight), needed, false)
        }
        // 3: over the bar area, photo up so the work ends above it
        let barRect = CGRect(x: margin, y: barTop + 6, width: width, height: max(0, min(voiceHeight, container.height - barTop - 12)))
        let shift = min(maxShift, max(0, work.maxY + gap - barRect.minY))
        return result(barRect, shift, true)
    }
}
