import SwiftUI

struct BlockView: View {
    @Environment(FlowModel.self) private var flow

    private enum Variant { case warn, professional, unsupported }
    private var variant: Variant {
        guard let r = flow.response else { return .unsupported }
        if r.riskLevel == .professional { return .professional }
        if r.category == .unsupported && r.riskLevel == .allowed { return .unsupported }
        return r.riskLevel == .warnOnly ? .warn : .unsupported
    }

    private var tint: Color { variant == .professional ? Theme.stop : (variant == .warn ? Theme.caution : Theme.inkSecondary) }
    private var icon: String {
        switch variant {
        case .warn: "bolt.trianglebadge.exclamationmark.fill"
        case .professional: "shield.lefthalf.filled"
        case .unsupported: "questionmark.circle.fill"
        }
    }
    private var title: String {
        switch variant {
        case .warn: tr("Hier reparieren wir lieber nicht selbst")
        case .professional: tr("Das gehört in Profi-Hände")
        case .unsupported: tr("Dafür bin ich nicht gemacht")
        }
    }
    private var tips: [String] {
        switch variant {
        case .warn: [tr("Lass das Teil vom Hersteller oder einem Fachbetrieb prüfen."), tr("Akkus getrennt an einer Sammelstelle abgeben, nie in den Hausmüll."), tr("Frag in einem Reparaturcafé, ob dort Elektrofachleute helfen.")]
        case .professional: [tr("Frag den Hersteller oder einen Fachbetrieb nach Prüfung oder Ersatz."), tr("Benutze das Teil bis dahin nicht."), tr("Ein Reparaturcafé kann dir sagen, wer in deiner Nähe helfen kann.")]
        case .unsupported: [tr("Ich helfe bei Kleidung und Schuhen."), tr("Mach ein neues Foto von dem Teil, das du reparieren willst."), tr("Für andere Dinge hilft ein Reparaturcafé in deiner Nähe.")]
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                if let photo = flow.photo {
                    PhotoStage(image: photo, cornerRadius: 20, dim: 0.1) { size in
                        if let r = flow.response { SegmentOverlayView(segments: r.segments, size: size, showLabels: false) }
                    }
                    .frame(height: 170)

                }
                VStack(spacing: 14) {
                    Image(systemName: icon).font(.system(size: 34, weight: .semibold)).foregroundStyle(tint)
                        .frame(width: 76, height: 76).background(tint.opacity(0.14), in: Circle())
                    Text(title).font(.title.bold()).multilineTextAlignment(.center).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let reason = flow.response?.safety.reason, !reason.isEmpty {
                        Text(reason).font(.body).multilineTextAlignment(.center).foregroundStyle(Theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionLabel(text: "Was du stattdessen tun kannst")
                    ForEach(tips, id: \.self) { t in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "arrow.right.circle.fill").foregroundStyle(Theme.inkSecondary)
                            Text(t).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading).card(padding: 18)
            }
            .padding(.horizontal, Theme.margin).padding(.top, 12).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarBackButtonHidden()
        .floatingBar {
            VStack(spacing: 10) {
                PrimaryButton(title: "Neues Foto", systemImage: "camera.fill") { flow.reset() }
                Button("Verstanden") { flow.reset() }.font(.headline).foregroundStyle(Theme.inkSecondary).frame(minHeight: 44)
            }
            .padding(.horizontal, Theme.margin).padding(.vertical, 10)
        }
        .onAppear { Haptics.warning() }
    }
}
