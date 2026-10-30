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
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Not working?").font(.serif(.title2)).foregroundStyle(Theme.ink)
                    Text("Step \(step.n): \(step.title)").font(.subheadline).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
                Spacer()
                Button("Close") { dismiss() }.font(.body.weight(.medium))
            }
            .padding(.horizontal, Theme.margin).padding(.top, 24).padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let r = result {
                        if r.escalate { escalateBlock(r) } else { answerBlock(r) }
                    } else {
                        Text("What's happening?").sectionHeader()
                        VoiceTextField(placeholder: "e.g. The thread pulls the fabric together", text: $issue, lines: 2...4)
                        let attached = extraPhoto != nil
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Text(attached ? "Photo attached" : "Add a photo").font(.body.weight(.medium)).foregroundStyle(Theme.thread)
                                .frame(minHeight: 44, alignment: .leading)
                        }
                        if loading { HStack(spacing: 10) { ProgressView(); Text("Checking this step").font(.subheadline).foregroundStyle(Theme.inkSecondary) } }
                        if error != nil { ErrorCard(message: "Couldn't load help. Try again.", retry: { Task { await send() } }) }
                    }
                }
                .padding(.horizontal, Theme.margin).padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)

            if result == nil {
                PrimaryButton(title: "Get help") { Task { await send() } }
                    .disabled(loading || issue.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal, Theme.margin).padding(.vertical, 12)
            } else if result?.escalate != true {
                PrimaryButton(title: "Keep going") { dismiss() }
                    .padding(.horizontal, Theme.margin).padding(.vertical, 12)
            }
        }
        .screenBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { if let d = try? await item.loadTransferable(type: Data.self) { extraPhoto = UIImage(data: d) } }
        }
    }

    private func answerBlock(_ r: StepHelpResponse) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(r.answer).font(.body).foregroundStyle(Theme.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if let hint = r.retryHint, !hint.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(Theme.thread).frame(width: 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Try this").sectionHeader()
                        Text(hint).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Text("The other steps stay the same.").font(.footnote).foregroundStyle(Theme.inkTertiary)
        }
    }

    private func escalateBlock(_ r: StepHelpResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Please stop here.").font(.serif(.title2)).foregroundStyle(Theme.ink)
            Text(r.answer).font(.body).foregroundStyle(Theme.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            PrimaryButton(title: "Stop the repair", kind: .destructive) { dismiss(); flow.reset() }
        }
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
        catch { self.error = (error as? APIError)?.errorDescription ?? "error" }
    }
}
