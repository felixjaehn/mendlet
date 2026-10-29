import SwiftUI

/// Text field with a microphone button. Records 16 kHz WAV (max 60 s), shows a live level meter,
/// and puts the transcript into the field so the user can edit it before sending (FR-27).
struct VoiceTextField: View {
    @Environment(FlowModel.self) private var flow
    var placeholder: String
    @Binding var text: String
    var lines: ClosedRange<Int> = 2...5

    private enum Mode: Equatable { case idle, recording, transcribing, failed(String) }
    @State private var mode: Mode = .idle
    @State private var recorder = AudioRecorder()
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                Group {
                    switch mode {
                    case .recording:
                        recordingBar
                    case .transcribing:
                        HStack(spacing: 10) {
                            ProgressView().tint(Theme.thread)
                            Text("Wird in Text umgewandelt …").foregroundStyle(Theme.inkSecondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    default:
                        TextField(tr(placeholder), text: $text, axis: .vertical)
                            .lineLimit(lines)
                            .focused($focused)
                            .font(.body)
                            .frame(minHeight: 44, alignment: .topLeading)
                    }
                }
                micButton
            }
            .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(mode == .recording ? Theme.thread : Theme.hairline, lineWidth: mode == .recording ? 2 : 1))
            if case .failed(let m) = mode {
                Text(m).font(.footnote).foregroundStyle(Theme.stop)
            } else if recorder.permissionDenied {
                Text("Mikrofonzugriff fehlt. Du kannst den Text auch tippen.").font(.footnote).foregroundStyle(Theme.stop)
            }
        }
        .animation(Theme.spring, value: mode)
    }

    private var micButton: some View {
        Button {
            Task { await toggle() }
        } label: {
            ZStack {
                Circle().fill(mode == .recording ? Theme.thread : Theme.threadSoft).frame(width: 44, height: 44)
                if mode == .recording {
                    Circle().stroke(Theme.thread.opacity(0.35), lineWidth: 4)
                        .frame(width: 44 + CGFloat(recorder.levels.last ?? 0) * 18, height: 44 + CGFloat(recorder.levels.last ?? 0) * 18)
                }
                Image(systemName: mode == .recording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(mode == .recording ? Color.white : Theme.thread)
            }
            .frame(width: 56, height: 56)
        }
        .disabled(mode == .transcribing)
        .accessibilityLabel(mode == .recording ? tr("Aufnahme beenden") : tr("Spracheingabe starten"))
    }

    private var recordingBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 3) {
                ForEach(Array(recorder.levels.enumerated()), id: \.offset) { _, v in
                    Capsule().fill(Theme.thread).frame(width: 3, height: 6 + CGFloat(v) * 28)
                }
            }
            .frame(height: 38)
            .animation(.linear(duration: 0.06), value: recorder.levels)
            Spacer(minLength: 0)
            Text("\(Int(recorder.elapsed) / 60):\(String(format: "%02d", Int(recorder.elapsed) % 60)) / 1:00")
                .font(.footnote.monospacedDigit()).foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func toggle() async {
        if mode == .recording { recorder.stop(); return }
        focused = false
        mode = .idle
        let simulated = flow.settings.demoMode
        await recorder.start(simulated: simulated) { url in
            Task { await transcribe(url) }
        }
        if recorder.isRecording { mode = .recording; Haptics.tap() }
    }

    private func transcribe(_ url: URL?) async {
        mode = .transcribing
        defer { if let url { try? FileManager.default.removeItem(at: url) } }
        do {
            let result = try await flow.service.transcribe(fileURL: url ?? URL(fileURLWithPath: "/dev/null"))
            let t = result.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { text = text.isEmpty ? t : text + " " + t }
            mode = .idle
            focused = true
        } catch {
            mode = .failed(tr("Das hat nicht geklappt. Tippe den Text einfach ein."))
        }
    }
}
