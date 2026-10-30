import SwiftUI

// MARK: Buttons

/// Primary action: an ink capsule (label colour on the fill, background colour as text), 54 pt. One per screen.
/// Secondary: plain accent text. Destructive: red text. Disabled primary: quiet fill, tertiary text.
struct PrimaryButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(kind == .primary ? .headline : .body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: kind == .primary ? Theme.controlHeight : 44)
            .padding(.horizontal, 20)
            .foregroundStyle(fg)
            .background { if kind == .primary { Capsule().fill(isEnabled ? Theme.ink : Theme.fill) } }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(kind != .primary && configuration.isPressed ? 0.6 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }

    private var fg: Color {
        switch kind {
        case .primary: isEnabled ? Color(uiColor: .systemBackground) : Theme.inkTertiary
        case .secondary: isEnabled ? Theme.thread : Theme.inkTertiary
        case .destructive: Theme.stop
        }
    }
}

struct PrimaryButton: View {
    var title: String
    /// Kept for call sites; the ink capsule carries text only.
    var systemImage: String? = nil
    var kind: PrimaryButtonStyle.Kind = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) { Text(tr(title)) }
            .buttonStyle(PrimaryButtonStyle(kind: kind))
    }
}

/// Soft press feedback for whole cards and rows.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

/// 44 pt glass circle. `onPhoto` keeps the glyph white for use over images.
struct CircleIconButton: View {
    var systemImage: String
    var label: String
    var onPhoto = false
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(onPhoto ? Color.white : Theme.ink)
                .frame(width: 44, height: 44)
                .glass(Circle(), interactive: true)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tr(label))
    }
}

// MARK: Progress

/// N thin segments (Peloton / Kitchen Stories / Hims). Filled = accent, the current one half-filled.
struct SegmentBar: View {
    var count: Int
    /// Number of finished segments.
    var done: Int
    var current: Int? = nil
    var height: CGFloat = 3
    var onPhoto = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                let filled = i < done
                let isCurrent = current == i && !filled
                Capsule().fill(onPhoto ? Color.white.opacity(0.32) : Theme.fill)
                    .overlay(alignment: .leading) {
                        GeometryReader { g in
                            Capsule().fill(onPhoto ? Color.white : Theme.thread)
                                .frame(width: filled ? g.size.width : (isCurrent ? g.size.width * 0.5 : 0))
                                .opacity(isCurrent ? 0.6 : 1)
                        }
                    }
                    .frame(height: height)
            }
        }
        .animation(.easeOut(duration: 0.35), value: done)
        .animation(.easeOut(duration: 0.35), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Step %lld of %lld", min(done + 1, count), count))
    }
}

/// Thin continuous progress line.
struct ProgressLine: View {
    var value: Double
    var body: some View {
        Capsule().fill(Theme.fill).frame(height: 3)
            .overlay(alignment: .leading) {
                GeometryReader { g in Capsule().fill(Theme.thread).frame(width: g.size.width * min(1, max(0, value))) }
            }
            .animation(.easeOut(duration: 0.3), value: value)
    }
}

enum StageState { case pending, active, done }

/// Quiet checkbox circle: empty ring, or accent fill with a white check.
struct CheckCircle: View {
    var on: Bool
    var size: CGFloat = 26
    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.inkTertiary, lineWidth: 1.5).opacity(on ? 0 : 1)
            Circle().fill(Theme.thread).scaleEffect(on ? 1 : 0.8).opacity(on ? 1 : 0)
            Image(systemName: "checkmark").font(.system(size: size * 0.46, weight: .bold)).foregroundStyle(.white)
                .opacity(on ? 1 : 0).scaleEffect(on ? 1 : 0.6)
        }
        .frame(width: size, height: size)
        .animation(.spring(response: 0.18, dampingFraction: 0.7), value: on)
    }
}

// MARK: Errors

struct ErrorCard: View {
    var message: String
    var retryTitle: String = "Try again"
    var retry: (() -> Void)?
    var secondaryTitle: String? = nil
    var secondary: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Text(message).font(.subheadline).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let retry { PrimaryButton(title: retryTitle, action: retry) }
            if let secondaryTitle, let secondary { PrimaryButton(title: secondaryTitle, kind: .secondary, action: secondary) }
        }
    }
}

/// Section header label inside sheets and forms.
struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(tr(text)).font(.headline).foregroundStyle(Theme.ink)
    }
}

extension View {
    /// Bottom action area: material bar with a hairline on top.
    func floatingBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        self.safeAreaInset(edge: .bottom, spacing: 0) {
            bar()
                .background(.bar)
                .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
        }
    }
}
