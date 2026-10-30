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
        case .battery, .professional: "This needs a specialist"
        case .unsupported: "Not something we can mend"
        }
    }
    private var reason: String {
        if let r = flow.response?.safety.reason, !r.isEmpty { return CopyPolish.text(r, english: Lang.shared.isEnglish) }
        switch variant {
        case .battery: return "This \(itemNoun) has a lithium battery. Repairs near it can cause a fire."
        case .professional: return "A repair here can fail without showing it. Please leave it to a professional."
        case .unsupported: return "Mendlet helps with clothes, shoes and simple low-voltage electronics."
        }
    }
    private var note: String {
        switch variant {
        case .battery: "Bring the battery to a recycling point and don't charge or open it."
        case .professional: "Ask the maker or a specialist shop about an inspection or a replacement. Don't use it until then."
        case .unsupported: "Take a new photo of the item you want to repair, close up and in daylight."
        }
    }

    private var itemNoun: String {
        let t = ProjectTitle.title(summary: flow.response?.diagnosis.summary ?? "", english: Lang.shared.isEnglish)
        let w = t.split(separator: " ").last.map { String($0).lowercased() } ?? ""
        return w.isEmpty ? "item" : w
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let photo = flow.photo {
                    Group {
                        if let r = flow.response, !r.segments.isEmpty {
                            MarkedPhoto(image: photo, segments: r.segments, mode: .resting, showLabels: true, focus: DamageFocus.region(for: r.segments), zoomable: false, topScrim: false)
                        } else {
                            Image(uiImage: photo).resizable().scaledToFill()
                        }
                    }
                    .frame(height: 340).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .accessibilityLabel(tr("Photo of your item"))
                }
                HStack(spacing: 8) {
                    Image(systemName: "hand.raised").font(.system(size: 14, weight: .semibold))
                    Text("Safety stop").font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.inkSecondary).padding(.top, 4)
                Text(title).font(.title.bold()).foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 12) {
                    Text(reason).font(.body).foregroundStyle(Theme.ink).lineSpacing(4)
                    Text(note).font(.body).foregroundStyle(Theme.ink).lineSpacing(4)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Capsule().fill(Theme.ink).frame(width: 3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.margin).padding(.top, 16).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarBackButtonHidden()
        .navigationBarHidden(true)
        .floatingBar {
            VStack(spacing: 0) {
                PrimaryButton(title: "Scan something else") { flow.reset(); flow.showScan = true }
                PrimaryButton(title: "Back to Repairs", kind: .secondary) { flow.reset() }
            }
            .padding(.horizontal, Theme.margin).padding(.vertical, 12)
        }
        .onAppear { Haptics.warning() }
    }
}
