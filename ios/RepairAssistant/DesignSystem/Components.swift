import SwiftUI

// MARK: Buttons

struct PrimaryButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 20)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
            .overlay(Capsule().strokeBorder(kind == .secondary ? Theme.hairline : .clear, lineWidth: 1.5))
            .opacity(isEnabled ? 1 : 0.55)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
    private var fg: Color {
        switch kind {
        case .primary, .destructive: isEnabled ? .white : Theme.inkSecondary
        case .secondary: Theme.ink
        }
    }
    private var bg: Color {
        switch kind {
        case .primary: isEnabled ? Theme.thread : Theme.hairline
        case .destructive: isEnabled ? Theme.stop : Theme.hairline
        case .secondary: Theme.card
        }
    }
}

struct PrimaryButton: View {
    var title: String
    var systemImage: String? = nil
    var kind: PrimaryButtonStyle.Kind = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage { Image(systemName: systemImage) }
                Text(tr(title))
            }
        }
        .buttonStyle(PrimaryButtonStyle(kind: kind))
    }
}

struct CircleIconButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .frame(width: 56, height: 56)
                .background(Theme.card, in: Circle())
                .overlay(Circle().strokeBorder(Theme.hairline, lineWidth: 1.5))
        }
        .accessibilityLabel(tr(label))
    }
}

// MARK: Chip

struct Chip: View {
    var title: String
    var systemImage: String? = nil
    var tint: Color = Theme.thread
    var isOn: Bool = true
    var filled: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.caption.weight(.semibold)) }
            Text(tr(title)).font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .foregroundStyle(filled ? Color.white : (isOn ? tint : Theme.inkSecondary))
        .background(filled ? tint : (isOn ? tint.opacity(0.14) : Theme.card), in: Capsule())
        .overlay(Capsule().strokeBorder(isOn ? tint.opacity(0.0) : Theme.hairline, lineWidth: 1))
        .animation(Theme.spring, value: isOn)
    }
}

// MARK: Pills

struct EstimatePill: View {
    var text: String = "Schätzung"
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text(tr(text))
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.caution)
        .padding(.horizontal, 12).frame(minHeight: 30)
        .background(Theme.cautionSoft, in: Capsule())
    }
}

struct Badge: View {
    var text: String
    var tint: Color
    var body: some View {
        Text(tr(text)).font(.caption2.weight(.bold)).textCase(.uppercase)
            .foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Small tasteful marker for the demo mode (real recorded model answers).
struct DemoChip: View {
    var text: String = LiveRecordings.chipText
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.caution).frame(width: 6, height: 6)
            Text(tr(text)).font(.caption.weight(.semibold))
        }
        .foregroundStyle(Theme.inkSecondary)
        .padding(.horizontal, 10).frame(minHeight: 26)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        .accessibilityLabel(Text("Demo-Modus mit echten Modellantworten vom 28. Oktober"))
    }
}

// MARK: Confidence

struct ConfidenceMeter: View {
    var confidence: Double
    @State private var shown = 0.0

    static func level(_ c: Double) -> (text: String, color: Color) {
        if c >= 0.75 { return (tr("ziemlich sicher"), Theme.safe) }
        if c >= 0.6 { return (tr("eher sicher"), Theme.caution) }
        return (tr("unsicher"), Theme.stop)
    }

    var body: some View {
        let lv = Self.level(confidence)
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 7)
                Circle().trim(from: 0, to: shown).stroke(lv.color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((confidence * 100).rounded()))")
                    .font(.rounded(.headline)).monospacedDigit()
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text("Konfidenz").font(.footnote).foregroundStyle(Theme.inkSecondary)
                Text(lv.text).font(.headline).foregroundStyle(lv.color)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("Konfidenz %lld Prozent, %@", Int((confidence * 100).rounded()), lv.text))
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { shown = confidence } }
        .onChange(of: confidence) { _, v in withAnimation(.easeOut(duration: 0.6)) { shown = v } }
    }
}

// MARK: Progress

struct SegmentedProgressBar: View {
    var count: Int
    var current: Int          // 0-based current step
    var completed: Set<Int> = []

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(count, 1), id: \.self) { i in
                Capsule()
                    .fill(i <= current || completed.contains(i) ? Theme.thread : Theme.hairline)
                    .frame(height: 5)
                    .opacity(i == current ? 1 : (completed.contains(i) ? 0.55 : (i < current ? 0.55 : 1)))
            }
        }
        .animation(Theme.spring, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Schritt \(current + 1) von \(count)")
    }
}

enum StageState { case pending, active, done }

struct StageRow: View {
    var title: String
    var subtitle: String
    var state: StageState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(state == .done ? Theme.safe : (state == .active ? Theme.threadSoft : Theme.hairline.opacity(0.6)))
                    .frame(width: 32, height: 32)
                switch state {
                case .done:
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                        .transition(.scale.combined(with: .opacity))
                case .active:
                    ProgressView().controlSize(.small).tint(Theme.thread)
                case .pending:
                    EmptyView()
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(tr(title)).font(.body.weight(.semibold))
                    .foregroundStyle(state == .pending ? Theme.inkSecondary : Theme.ink)
                Text(tr(subtitle)).font(.caption).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .animation(Theme.spring, value: state)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Errors

struct ErrorCard: View {
    var message: String
    var retryTitle: String = "Erneut versuchen"
    var retry: (() -> Void)?
    var secondaryTitle: String? = nil
    var secondary: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.title3).foregroundStyle(Theme.stop)
                Text(message).font(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let retry {
                PrimaryButton(title: tr(retryTitle), systemImage: "arrow.clockwise", action: retry)
            }
            if let secondaryTitle, let secondary {
                PrimaryButton(title: secondaryTitle, kind: .secondary, action: secondary)
            }
        }
        .padding(16)
        .background(Theme.stopSoft, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.stop.opacity(0.3), lineWidth: 1))
    }
}

struct MetricTile: View {
    var icon: String
    var title: String
    var value: String
    var detail: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.thread)
            Text(value).font(.rounded(.title3)).monospacedDigit().foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.7).lineLimit(1)
            VStack(alignment: .leading, spacing: 0) {
                Text(tr(title)).font(.caption).foregroundStyle(Theme.inkSecondary)
                if let detail { Text(tr(detail)).font(.caption2).foregroundStyle(Theme.inkSecondary) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Shimmer

struct Shimmer: ViewModifier {
    var active: Bool
    @State private var phase: CGFloat = -1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if active && !reduceMotion {
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.28), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.5)
                        .offset(x: phase * geo.size.width * 1.5)
                        .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
                .clipped()
                .onAppear {
                    withAnimation(.linear(duration: 1.8).repeatForever(autoreverses: false)) { phase = 1 }
                }
            }
        }
    }
}

extension View {
    func shimmer(_ active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}

/// Section header label.
struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(tr(text)).font(.footnote.weight(.semibold)).textCase(.uppercase)
            .foregroundStyle(Theme.inkSecondary).tracking(0.6)
    }
}
