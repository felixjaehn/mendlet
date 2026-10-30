import SwiftUI

/// Siri style glow around the whole screen: a soft multi-colour light that flows along the edge. Calm while idle,
/// brighter and reactive to the microphone level while the user speaks. Reduce Motion freezes it.
struct HandsFreeGlow: View {
    var phase: HandsFreeModel.Phase
    var level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [
        Color(red: 1.00, green: 0.37, blue: 0.64),   // #FF5FA2
        Color(red: 1.00, green: 0.62, blue: 0.26),   // #FF9F43
        Color(red: 0.35, green: 0.78, blue: 0.98),   // #5AC8FA
        Color(red: 0.48, green: 0.42, blue: 1.00),   // #7B6CFF
        Color(red: 0.20, green: 0.78, blue: 0.35),   // #34C759
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
                return .conicGradient(Gradient(colors: cs), center: center, angle: .radians(shift))
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
            .background(.ultraThinMaterial, in: shape)
            .background(Color.black.opacity(0.22), in: shape)
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))).allowsHitTesting(false))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.08), .white.opacity(0.22)], startPoint: .top, endPoint: .bottom), lineWidth: 0.5))
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
        HStack(spacing: 12) {
            ThinkingOrb(state: orbState, size: 56, tempo: model.phase == .hearing ? 1.0 : 0.7, level: model.phase == .hearing ? model.level : 0)
                .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 2) {
                if model.phase == .thinking, !model.caption.isEmpty, model.notice == nil {
                    Text(model.caption).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                }
                Text(statusText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(model.phase == .idle && model.notice == nil && model.caption.isEmpty ? .white.opacity(0.78) : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 8).padding(.trailing, 20).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(HandsFreeGlass(shape: Capsule()))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusText)
    }

    private func answerCard(_ text: String) -> some View {
        Button { model.dismissAnswer() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ThinkingOrb(state: .listening, size: 28, tempo: 0.7).frame(width: 34, height: 34)
                    if !model.caption.isEmpty {
                        Text(model.caption).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Text(text)
                    .font(.title3.weight(.medium))
                    .lineSpacing(4)
                    .foregroundStyle(.white)
                    .lineLimit(6)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 20).padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .modifier(HandsFreeGlass(shape: RoundedRectangle(cornerRadius: 30, style: .continuous)))
            .contentShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint("Double tap to dismiss")
    }
}
