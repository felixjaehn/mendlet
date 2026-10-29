import SwiftUI
import UIKit

extension Color {
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(uiColor: UIColor { trait in
            let dk = trait.userInterfaceStyle == .dark
            let v = dk ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: dk ? darkAlpha : lightAlpha)
        })
    }
}

/// Mendlet design tokens (docs/design/REDESIGN-SPEC.md 1.1): neutral ink and paper, one accent (system blue, state only),
/// white for everything drawn on photos. Serif (New York) only for editorial moments.
enum Theme {
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let ink = Color(uiColor: .label)
    static let inkSecondary = Color(uiColor: .secondaryLabel)
    static let inkTertiary = Color(uiColor: .tertiaryLabel)
    static let hairline = Color(uiColor: .separator)
    /// UI accent = the system accent colour (Assets: AccentColor, system blue). No orange anywhere.
    static let thread = Color.accentColor
    static let threadSoft = Color.accentColor.opacity(0.14)
    /// Everything drawn on a photo (masks, stitch path, routes) is white.
    static let highlight = Color.white
    static let scrim = Color.black.opacity(0.30)
    /// Legacy names kept for the trace drawer and overlays: no extra hues, white on photos, red only for destructive.
    static let safe = Color.accentColor
    static let safeSoft = Color.accentColor.opacity(0.14)
    static let caution = Color.white
    static let cautionSoft = Color(uiColor: .tertiarySystemFill)
    static let stop = Color(uiColor: .systemRed)
    static let stopSoft = Color(uiColor: .systemRed).opacity(0.12)

    static let partColors: [Color] = [.white, .white, .white]

    static let margin: CGFloat = 20
    static let heroRadius: CGFloat = 28
    static let cardRadius: CGFloat = 20
    static let thumbRadius: CGFloat = 12
    static let controlHeight: CGFloat = 54

    /// `ui` spring (state change) and `press` spring.
    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    static let press = Animation.spring(response: 0.25, dampingFraction: 0.7)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    static func serif(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font { .system(style, design: .serif, weight: weight) }
    static let overline = Font.caption.weight(.semibold)
}

extension View {
    /// Small caps label above a block of content ("What we found").
    func overline() -> some View {
        self.font(.overline).tracking(0.8).textCase(.uppercase).foregroundStyle(Theme.inkSecondary)
    }
}

@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func soft() { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// Liquid Glass on iOS 26+, a system material before.
    @ViewBuilder func glass<S: Shape>(_ shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.tint(tint).interactive() : Glass.regular.tint(tint), in: shape)
        } else {
            self.background(tint ?? Color.clear, in: shape).background(.ultraThinMaterial, in: shape)
        }
    }

    func screenBackground() -> some View {
        self.background(Theme.paper.ignoresSafeArea())
    }
}

/// Segment colours: damage = thread, parts cycle through the palette.
func segmentColor(_ segment: Segment, in all: [Segment]) -> Color {
    if segment.isDamage { return Theme.highlight }
    let parts = all.filter { !$0.isDamage }
    let idx = parts.firstIndex(where: { $0.id == segment.id }) ?? 0
    return Theme.partColors[idx % Theme.partColors.count]
}

extension EnvironmentValues {
    /// Static render: animated overlays draw their final state, like with Reduce Motion.
    @Entry var staticRendering = false
}
