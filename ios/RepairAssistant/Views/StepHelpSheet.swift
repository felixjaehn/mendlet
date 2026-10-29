import SwiftUI
import PhotosUI

struct StepHelpSheet: View {
    @Environment(FlowModel.self) private var flow
    @Environment(\.dismiss) private var dismiss
    let step: GuideStep

    @State private var issue = ""
    @State private var loading = false
    @State private var result: StepHelpResponse?
    @State private var error: String?
    @State private var pickerItem: PhotosPickerItem?
    @State private var extraPhoto: UIImage?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hilfe zu diesem Schritt").font(.title2.bold()).foregroundStyle(Theme.ink)
                    Text("Schritt \(step.n): \(step.title)").font(.subheadline).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
                Spacer()
                Button("Schließen") { dismiss() }.font(.body.weight(.medium)).foregroundStyle(Theme.inkSecondary)
            }
            .padding(.horizontal, Theme.margin).padding(.top, 24).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let r = result {
                        if r.escalate { escalateCard(r) } else { answerCards(r) }
                    } else {
                        SectionLabel(text: "Was klappt nicht?")
                        VoiceTextField(placeholder: "z. B. Der Faden zieht den Stoff zusammen", text: $issue, lines: 2...4)
                        HStack {
                            let attached = extraPhoto != nil
                            PhotosPicker(selection: $pickerItem, matching: .images) {
                                Label(attached ? tr("Foto angehängt") : tr("Foto anhängen"), systemImage: attached ? "checkmark.circle.fill" : "paperclip")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(attached ? Theme.safe : Theme.thread)
                            }
                            Spacer()
                        }
                        if let error { ErrorCard(message: error, retry: { Task { await send() } }) }
                    }
                }
                .padding(.horizontal, Theme.margin).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            if result == nil {
                PrimaryButton(title: loading ? "Ich überlege …" : "Frage senden", systemImage: "arrow.up") { Task { await send() } }
                    .disabled(loading || issue.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal, Theme.margin).padding(.vertical, 12)
            } else if result?.escalate != true {
                PrimaryButton(title: "Weiter versuchen") { dismiss() }
                    .padding(.horizontal, Theme.margin).padding(.vertical, 12)
            }
        }
        .screenBackground()
        .presentationDetents([.large])
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { if let d = try? await item.loadTransferable(type: Data.self) { extraPhoto = UIImage(data: d) } }
        }
    }

    private func answerCards(_ r: StepHelpResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Antwort", systemImage: "text.bubble.fill").font(.subheadline.weight(.bold)).foregroundStyle(Theme.thread)
                Text(r.answer).font(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading).card()
            if let hint = r.retryHint, !hint.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(Theme.caution)
                    Text(hint).font(.subheadline).foregroundStyle(Theme.ink)
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cautionSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            Text("Die übrigen Schritte bleiben unverändert.").font(.footnote).foregroundStyle(Theme.inkSecondary)
        }
    }

    private func escalateCard(_ r: StepHelpResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "hand.raised.fill").font(.title2).foregroundStyle(Theme.stop)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Bitte hier aufhören").font(.title3.bold()).foregroundStyle(Theme.stop)
                    Text(r.answer).font(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            PrimaryButton(title: "Reparatur abbrechen", kind: .destructive) { dismiss(); flow.reset() }
        }
        .padding(16)
        .background(Theme.stopSoft, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onAppear { Haptics.warning() }
    }

    private func send() async {
        loading = true; error = nil
        defer { loading = false }
        let req = StepHelpRequest(
            step: StepRef(n: step.n, title: step.title, text: step.text),
            diagnosisSummary: flow.response?.diagnosis.summary ?? "",
            riskLevel: flow.response?.riskLevel ?? .allowed,
            issueText: issue, imageBase64: extraPhoto.map { ImageResizer.base64($0) })
        do { result = try await flow.service.stepHelp(req) }
        catch { self.error = (error as? APIError)?.errorDescription ?? tr("Das hat nicht geklappt.") }
    }
}
