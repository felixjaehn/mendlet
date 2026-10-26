import SwiftUI

struct ReviewSheet: View {
    @Environment(FlowModel.self) private var flow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var flow = flow
        VStack(spacing: 0) {
            HStack {
                Text("Foto prüfen").font(.title2.bold()).foregroundStyle(Theme.ink)
                Spacer()
                Button("Abbrechen") { flow.showReview = false; flow.photo = nil }
                    .font(.body.weight(.medium)).foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, Theme.margin).padding(.top, 24).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let photo = flow.photo {
                        PhotoStage(image: photo) { _ in EmptyView() }
                            .overlay(alignment: .bottomLeading) {
                                HStack(spacing: 6) {
                                    Image(systemName: "lightbulb.fill").foregroundStyle(Theme.caution)
                                    Text("Tipp: Schaden mittig, gutes Licht").font(.footnote.weight(.semibold))
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(.black.opacity(0.55), in: Capsule())
                                .padding(12)
                            }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "Was ist kaputt? (optional)")
                        VoiceTextField(placeholder: "z. B. Riss am Knie, ca. 6 cm", text: $flow.note)
                    }
                }
                .padding(.horizontal, Theme.margin).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            PrimaryButton(title: "Analysieren", systemImage: "sparkle.magnifyingglass") { flow.startAnalysis() }
                .padding(.horizontal, Theme.margin).padding(.vertical, 12)
        }
        .screenBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
