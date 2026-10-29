import SwiftUI
import PhotosUI

struct FollowUpSheet: View {
    @Environment(FlowModel.self) private var flow

    @State private var index = 0
    @State private var typed = ""
    @State private var answers: [AnswerPayload] = []
    @State private var images: [(Purpose, UIImage)] = []
    @State private var transcript: [(question: String, answer: String, image: UIImage?)] = []
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var pickerItem: PhotosPickerItem?

    private var questions: [FollowUpQuestion] { flow.response?.diagnosis.followUpQuestions ?? [] }
    private var current: FollowUpQuestion? { index < questions.count ? questions[index] : nil }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(transcript.enumerated()), id: \.offset) { _, t in
                            AssistantBubble(text: t.question)
                            UserBubble(text: t.answer, image: t.image)
                        }
                        if let q = current {
                            AssistantBubble(text: q.prompt).id("current")
                        }
                    }
                    .padding(.horizontal, Theme.margin).padding(.vertical, 12)
                }
                .onChange(of: index) { _, _ in withAnimation { proxy.scrollTo("current", anchor: .bottom) } }
            }
            if let q = current { answerArea(q).padding(.horizontal, Theme.margin).padding(.vertical, 12) }
        }
        .screenBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { addPhoto($0) }.ignoresSafeArea()
        }
        .photosPicker(isPresented: $showGallery, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { addPhoto(img) }
                pickerItem = nil
            }
        }
        .animation(Theme.spring, value: index)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rückfrage").font(.title2.bold()).foregroundStyle(Theme.ink)
                if questions.count > 0 {
                    Text("\(min(index + 1, questions.count)) von \(questions.count)").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer()
            if current != nil {
                Button("Überspringen") { skip() }.font(.body.weight(.medium)).foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.horizontal, Theme.margin).padding(.top, 24).padding(.bottom, 8)
    }

    @ViewBuilder
    private func answerArea(_ q: FollowUpQuestion) -> some View {
        switch q.type {
        case .photo:
            VStack(spacing: 10) {
                if CameraPicker.isAvailable {
                    PrimaryButton(title: photoTitle(q), systemImage: "camera.fill") { showCamera = true }
                }
                if flow.settings.demoMode {
                    PrimaryButton(title: "Demo-Etikett verwenden", systemImage: "tag.fill", kind: CameraPicker.isAvailable ? .secondary : .primary) {
                        addPhoto(LiveRecordings.recording(for: .textileTear)?.labelPhoto ?? DemoImageFactory.labelImage())
                    }
                }
                PrimaryButton(title: "Aus Galerie", systemImage: "photo.on.rectangle", kind: .secondary) { showGallery = true }
            }
        case .choice:
            let opts = q.options.isEmpty ? [tr("Baumwolle"), tr("Wolle"), tr("Polyester"), tr("Weiß ich nicht")] : q.options
            FlowLayout(spacing: 8) {
                ForEach(opts, id: \.self) { o in
                    Button { answer(text: o) } label: { Chip(title: o, tint: Theme.thread, isOn: true) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .voiceOrText:
            VStack(spacing: 10) {
                VoiceTextField(placeholder: "Deine Antwort", text: $typed, lines: 1...3)
                PrimaryButton(title: "Senden", systemImage: "arrow.up") { answer(text: typed) }
                    .disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func photoTitle(_ q: FollowUpQuestion) -> String {
        switch q.purpose {
        case .label: tr("Etikett fotografieren")
        case .closeup: tr("Nahaufnahme machen")
        case .other: tr("Foto aufnehmen")
        }
    }

    private func addPhoto(_ img: UIImage) {
        guard let q = current else { return }
        images.append((q.purpose, ImageResizer.resized(img)))
        transcript.append((q.prompt, q.purpose == .label ? tr("Etikett-Foto gesendet") : tr("Foto gesendet"), img))
        Haptics.success()
        advance()
    }

    private func answer(text: String) {
        guard let q = current else { return }
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        answers.append(AnswerPayload(questionId: q.id, text: t))
        transcript.append((q.prompt, t, nil))
        typed = ""
        Haptics.selection()
        advance()
    }

    private func skip() {
        guard let q = current else { return }
        answers.append(AnswerPayload(questionId: q.id, text: tr("Keine Angabe")))
        advance(skipped: true)
    }

    private func advance(skipped: Bool = false) {
        index += 1
        if index >= questions.count {
            let a = answers, i = images
            Task {
                try? await Task.sleep(for: .milliseconds(450))
                flow.showFollowUp = false
                flow.submitFollowUp(answers: a, images: i)
            }
        }
    }
}

struct AssistantBubble: View {
    var text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                .font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.thread)
                .frame(width: 32, height: 32).background(Theme.threadSoft, in: Circle())
            Text(text).font(.body).foregroundStyle(Theme.ink)
                .padding(14)
                .background(Theme.card, in: UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 20))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 20, bottomTrailingRadius: 20, topTrailingRadius: 20).strokeBorder(Theme.hairline, lineWidth: 1))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct UserBubble: View {
    var text: String
    var image: UIImage?
    var body: some View {
        HStack {
            Spacer(minLength: 56)
            VStack(alignment: .trailing, spacing: 6) {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill().frame(width: 150, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Text(text).font(.body).foregroundStyle(.white).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Theme.thread, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20, bottomTrailingRadius: 6, topTrailingRadius: 20))
            }
        }
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, width: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxW { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowH)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
