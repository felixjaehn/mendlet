import SwiftUI

/// Safety stop: calm, no alarm colour. The gate logic lives in `FlowGate`; this screen only explains.
struct BlockView: View {
    @Environment(FlowModel.self) private var flow

    private enum Variant { case battery, professional, unsupported }
    private var variant: Variant {
        guard let r = flow.response else { return .unsupported }
        if r.riskLevel == .professional { return .professional }
        if r.category == .unsupported && r.riskLevel == .allowed { return .unsupported }
        return r.riskLevel == .warnOnly ? .battery : .unsupported
    }

    private var title: String {
        switch variant {
        case .battery, .professional: "Not one to repair at home."
        case .unsupported: "Not something we can mend."
        }
    }
    private var reason: String {
        if let r = flow.response?.safety.reason, !r.isEmpty { return CopyPolish.text(r, english: Lang.shared.isEnglish) }
        switch variant {
        case .battery: return "This one has a lithium battery. A damaged cell can ignite, and no guide can make that safe at home."
        case .professional: return "A repair here can fail without showing it. Please leave it to a professional."
        case .unsupported: return "Mendlet helps with clothes, shoes and simple low-voltage electronics."
        }
    }
    private var note: String {
        switch variant {
        case .battery: "If it's a battery, bring it to a recycling point. Don't charge it or open it."
        case .professional: "Ask the maker or a specialist shop about an inspection or a replacement. Don't use it until then."
        case .unsupported: "Take a new photo of the item you want to repair, close up and in daylight."
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let photo = flow.photo {
                    Image(uiImage: photo).resizable().scaledToFill().frame(height: 120).frame(maxWidth: .infinity).clipped()
                        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        .accessibilityHidden(true)
                }
                Image(systemName: "hand.raised").font(.system(size: 40, weight: .thin)).foregroundStyle(Theme.inkTertiary)
                    .padding(.top, 8).accessibilityHidden(true)
                VStack(spacing: 10) {
                    Text(title).font(.serif(.title)).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(reason).font(.body).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(note).font(.subheadline).foregroundStyle(Theme.ink).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(.horizontal, Theme.margin).padding(.top, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarBackButtonHidden()
        .navigationBarHidden(true)
        .floatingBar {
            PrimaryButton(title: "Back to Repairs") { flow.reset() }
                .padding(.horizontal, Theme.margin).padding(.vertical, 12)
        }
        .onAppear { Haptics.warning() }
    }
}
