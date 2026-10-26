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

enum Theme {
    static let paper = Color(light: 0xF6F3EE, dark: 0x121110)
    static let card = Color(light: 0xFFFFFF, dark: 0x1E1C1A)
    static let ink = Color(light: 0x1C1A17, dark: 0xF2EFEA)
    static let inkSecondary = Color(light: 0x6B655D, dark: 0xA39D94)
    static let hairline = Color(light: 0xE6E0D7, dark: 0x2E2B27)
    static let thread = Color(light: 0xE2552B, dark: 0xFF6A3D)
    static let threadSoft = Color(light: 0xE2552B, dark: 0xFF6A3D, lightAlpha: 0.12, darkAlpha: 0.18)
    static let safe = Color(light: 0x2F7D5B, dark: 0x4CC38A)
    static let safeSoft = Color(light: 0x2F7D5B, dark: 0x4CC38A, lightAlpha: 0.12, darkAlpha: 0.18)
    static let caution = Color(light: 0xC98A00, dark: 0xF5B83D)
    static let cautionSoft = Color(light: 0xC98A00, dark: 0xF5B83D, lightAlpha: 0.14, darkAlpha: 0.18)
    static let stop = Color(light: 0xC2372B, dark: 0xFF5A4E)
    static let stopSoft = Color(light: 0xC2372B, dark: 0xFF5A4E, lightAlpha: 0.12, darkAlpha: 0.18)

    static let partColors: [Color] = [Color(hex: 0x3A7BD5), Color(hex: 0x8E5BD9), Color(hex: 0x2BA39A)]

    static let margin: CGFloat = 20
    static let cardRadius: CGFloat = 20

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
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
    }

    func screenBackground() -> some View {
        self.background(Theme.paper.ignoresSafeArea())
    }
}

/// Segment colours: damage = thread, parts cycle through the palette.
func segmentColor(_ segment: Segment, in all: [Segment]) -> Color {
    if segment.isDamage { return Theme.thread }
    let parts = all.filter { !$0.isDamage }
    let idx = parts.firstIndex(where: { $0.id == segment.id }) ?? 0
    return Theme.partColors[idx % Theme.partColors.count]
}
