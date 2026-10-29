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

/// Apple system palette (grouped backgrounds, labels, system tints) with one brand accent: the thread orange.
/// References: Apple Health / Fitness / Journal on Mobbin (docs/design-notes.md, "Apple-Qualität").
enum Theme {
    static let paper = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let ink = Color(uiColor: .label)
    static let inkSecondary = Color(uiColor: .secondaryLabel)
    static let hairline = Color(uiColor: .separator)
    /// UI accent = the system accent colour (Assets: AccentColor, system blue). No orange UI.
    static let thread = Color.accentColor
    static let threadSoft = Color.accentColor.opacity(0.14)
    /// Annotations on photos (masks, stitch path, routes): white glow like Visual Intelligence.
    static let highlight = Color.white
    static let safe = Color(uiColor: .systemGreen)
    static let safeSoft = Color(uiColor: .systemGreen).opacity(0.14)
    static let caution = Color(light: 0xB27C00, dark: 0xFFD60A)
    static let cautionSoft = Color(uiColor: .systemYellow).opacity(0.18)
    static let stop = Color(uiColor: .systemRed)
    static let stopSoft = Color(uiColor: .systemRed).opacity(0.12)

    static let partColors: [Color] = [.white, .white, .white]

    static let margin: CGFloat = 20
    static let cardRadius: CGFloat = 24

    static let spring = Animation.spring(response: 0.45, dampingFraction: 0.85)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    static func rounded(_ style: Font.TextStyle, weight: Font.Weight = .bold) -> Font {
        .system(style, design: .rounded, weight: weight)
    }
}

@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
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
