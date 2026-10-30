import SwiftUI

/// Siri style glow around the whole screen: a soft multi-colour light that flows along the edge. Calm while idle,
/// brighter and reactive to the microphone level while the user speaks. Reduce Motion freezes it.
struct HandsFreeGlow: View {
    var phase: HandsFreeModel.Phase
    var level: Float
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let colors: [Color] = [
        Color(red: 1.00, green: 0.36, blue: 0.62),   // pink
        Color(red: 1.00, green: 0.62, blue: 0.32),   // orange
        Color(red: 1.00, green: 0.86, blue: 0.52),   // warm light
        Color(red: 0.36, green: 0.84, blue: 0.96),   // cyan
        Color(red: 0.30, green: 0.46, blue: 1.00),   // blue
        Color(red: 0.70, green: 0.40, blue: 1.00),   // violet
    ]
    private static let corner: CGFloat = 56

    var body: some View {
        if reduceMotion {
            canvas(t: 1.2, breath: 0.5)
        } else {
            TimelineView(.animation) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                canvas(t: t, breath: 0.5 + 0.5 * sin(t * 1.6))
            }
        }
    }

    private var intensity: Double {
        switch phase {
        case .off: return 0
        case .idle: return 0.34
        case .hearing: return 0.62 + 0.38 * Double(level)
        case .thinking: return 0.62
        case .speaking: return 0.62
        }
    }

    private func canvas(t: Double, breath: Double) -> some View {
        let k = intensity * (phase == .thinking || phase == .speaking ? 0.82 + 0.18 * breath : 1)
        return Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            func path(inset: CGFloat) -> Path {
                RoundedRectangle(cornerRadius: max(8, Self.corner - inset), style: .continuous).path(in: rect.insetBy(dx: inset, dy: inset))
            }
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func conic(_ shift: Double, _ rev: Bool) -> GraphicsContext.Shading {
                var cs = Self.colors
                cs.append(cs[0])
                if rev { cs.reverse() }
                return .conicGradient(Gradient(colors: cs), center: center, angle: .radians(shift))
            }
            let a = t * 0.55, b = -t * 0.38 + 2
            // wide soft bloom, reaching a little into the picture
            ctx.drawLayer { l in
                l.opacity = 0.30 * k
                l.addFilter(.blur(radius: 16))
                l.stroke(path(inset: 2), with: conic(a, false), lineWidth: 16)
            }
            // medium glow, counter-rotating colours for depth
            ctx.drawLayer { l in
                l.opacity = 0.62 * k
                l.blendMode = .plusLighter
                l.addFilter(.blur(radius: 5))
                l.stroke(path(inset: 2), with: conic(b, true), lineWidth: 7)
            }
            // bright thin light right at the screen edge
            ctx.drawLayer { l in
                l.opacity = min(1, 0.95 * k + 0.1)
                l.addFilter(.blur(radius: 1.6))
                l.stroke(path(inset: 1.5), with: conic(a * 1.25, false), lineWidth: 3)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Compact glass capsule above the step panel: dotted orb plus the live state text, or the answer card.
struct HandsFreeCapsule: View {
    var model: HandsFreeModel

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
        HStack(spacing: 10) {
            ThinkingOrb(state: orbState, size: 46, tempo: model.phase == .hearing ? 1.0 : 0.7)
                .scaleEffect(1 + 0.12 * CGFloat(model.phase == .hearing ? model.level : 0))
            VStack(alignment: .leading, spacing: 1) {
                if model.phase == .thinking, !model.caption.isEmpty, model.notice == nil {
                    Text(model.caption).font(.footnote).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                }
                Text(statusText)
                    .font(.body.weight(.medium))
                    .foregroundStyle(model.phase == .idle && model.notice == nil && model.caption.isEmpty ? .white.opacity(0.78) : .white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .contentTransition(.opacity)
            }
        }
        .padding(.leading, 10).padding(.trailing, 20).padding(.vertical, 8)
        .frame(minHeight: 56)
        .frame(maxWidth: 340, alignment: .leading)
        .glass(Capsule(), tint: Color.black.opacity(0.62))
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statusText)
    }

    private func answerCard(_ text: String) -> some View {
        Button { model.dismissAnswer() } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ThinkingOrb(state: .listening, size: 32, tempo: 0.7)
                    if !model.caption.isEmpty {
                        Text(model.caption).font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.62)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                Text(text)
                    .font(.body)
                    .lineSpacing(3)
                    .foregroundStyle(.white)
                    .lineLimit(10)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 16)
            .frame(maxWidth: 420)
            .glass(RoundedRectangle(cornerRadius: 28, style: .continuous), tint: Color.black.opacity(0.62))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(text)
        .accessibilityHint("Double tap to dismiss")
    }
}
