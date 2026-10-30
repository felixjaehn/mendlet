import SwiftUI

/// Siri style glow around the whole screen: a soft multi-colour light that flows along the edge. Calm while idle,
/// brighter and reactive to the microphone level while the user speaks. Reduce Motion freezes it.
struct HandsFreeGlow: View {
    var phase: HandsFreeModel.Phase
    var level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [
        Color(red: 0.55, green: 0.38, blue: 1.00),   // violet
        Color(red: 0.20, green: 0.80, blue: 1.00),   // cyan
        Color(red: 0.98, green: 0.30, blue: 0.80),   // magenta
        Color(red: 1.00, green: 0.55, blue: 0.20),   // orange
        Color(red: 0.30, green: 0.55, blue: 1.00),   // blue
        Color(red: 0.55, green: 0.38, blue: 1.00),   // violet
        Color(red: 0.20, green: 0.80, blue: 1.00),   // cyan
        Color(red: 0.98, green: 0.30, blue: 0.80),   // magenta
        Color(red: 1.00, green: 0.55, blue: 0.20),   // orange
    ]

    var body: some View {
        if reduceMotion {
            canvas(t: 1.0, breath: 0.5)
        } else {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                canvas(t: t, breath: 0.5 + 0.5 * sin(t * 1.4))
            }
        }
    }

    /// Calmer while the answer is spoken or the model thinks, brighter and mic-reactive while the user speaks.
    private var intensity: Double {
        switch phase {
        case .off: return 0
        case .idle: return 0.55
        case .hearing: return 0.75 + 0.25 * Double(level)
        case .thinking: return 0.7
        case .speaking: return 0.6
        }
    }

    private func canvas(t: Double, breath: Double) -> some View {
        let pulse: Double = {
            switch phase {
            case .hearing: return 0.9 + 0.1 * breath + 0.25 * Double(level)
            case .speaking, .thinking: return 0.86 + 0.14 * breath
            default: return 1
            }
        }()
        let k = intensity * pulse
        let wide = 1 + (phase == .hearing ? 0.35 * Double(level) : 0)
        return Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let radius = max(8, UIScreen.main.displayCornerRadiusApprox)
            func path(inset: CGFloat) -> Path {
                RoundedRectangle(cornerRadius: max(8, radius - inset), style: .continuous).path(in: rect.insetBy(dx: inset, dy: inset))
            }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func conic(_ shift: Double) -> GraphicsContext.Shading {
                var cs = Self.colors
                cs.append(cs[0])
                let r = max(size.width, size.height) * 0.5
                let d = CGPoint(x: cos(shift) * r, y: sin(shift) * r)
                return .linearGradient(Gradient(colors: cs), startPoint: CGPoint(x: center.x - d.x, y: center.y - d.y), endPoint: CGPoint(x: center.x + d.x, y: center.y + d.y))
            }
            let a = t * 2 * .pi / 6
            ctx.drawLayer { l in
                l.opacity = 0.35 * k
                l.addFilter(.blur(radius: 28))
                l.stroke(path(inset: 6), with: conic(a), lineWidth: 24 * wide)
            }
            ctx.drawLayer { l in
                l.opacity = 0.7 * k
                l.blendMode = .plusLighter
                l.addFilter(.blur(radius: 10))
                l.stroke(path(inset: 3), with: conic(a), lineWidth: 10 * wide)
            }
            ctx.drawLayer { l in
                l.opacity = min(1, k + 0.1)
                l.addFilter(.blur(radius: 2))
                l.stroke(path(inset: 1.5), with: conic(a), lineWidth: 3)
            }
        }
        .mask {
            // No bleed into the bottom bar: fade to 0.4 over the bottom 190 pt.
            GeometryReader { g in
                VStack(spacing: 0) {
                    Color.white.frame(height: max(0, g.size.height - 190))
                    LinearGradient(colors: [.white, .white.opacity(0.4)], startPoint: .top, endPoint: .bottom).frame(height: min(190, g.size.height))
                }
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

/// Real glass: ultra thin material, light tint, inner gradient stroke and a soft top highlight.
private struct HandsFreeGlass<S: InsettableShape>: ViewModifier {
    var shape: S
    func body(content: Content) -> some View {
        content
            .background(Color.black.opacity(0.10), in: shape)
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))).allowsHitTesting(false))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .white.opacity(0.08), .white.opacity(0.22)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.3), radius: 22, y: 8)
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
        .padding(.horizontal, Theme.margin)
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
                .background(Circle().fill(Color.black.opacity(0.45)).frame(width: 66, height: 66))
            VStack(alignment: .leading, spacing: 2) {
                if model.phase == .thinking, !model.caption.isEmpty, model.notice == nil {
                    Text(model.caption).font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                }
                Text(statusText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(model.phase == .idle && model.notice == nil && model.caption.isEmpty ? .white.opacity(0.78) : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .contentTransition(.opacity)
            }
            .frame(maxWidth: 260, alignment: .leading)
        }
        .padding(.leading, 6).padding(.trailing, 22).padding(.vertical, 4)
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
                        .background(Circle().fill(Color.black.opacity(0.45)).frame(width: 34, height: 34))
                    if !model.caption.isEmpty {
                        Text(model.caption).font(.system(size: 14)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
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
