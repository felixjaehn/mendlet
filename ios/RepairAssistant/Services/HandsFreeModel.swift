import AVFoundation
import Observation
import Speech
import UIKit

/// Text-to-speech for answers (en-US, natural rate). `speak` returns when the utterance has finished.
@MainActor
final class SpeechOutput: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?
    private var current: ObjectIdentifier?

    override init() { super.init(); synth.delegate = self }

    private static var voice: AVSpeechSynthesisVoice? {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "en-US" }
        return voices.max { $0.quality.rawValue < $1.quality.rawValue } ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    func speak(_ text: String) async {
        stop()
        let u = AVSpeechUtterance(string: text)
        u.voice = Self.voice
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        current = ObjectIdentifier(u)
        await withCheckedContinuation { c in
            continuation = c
            synth.speak(u)
        }
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        finish()
    }

    private func finish() {
        current = nil
        let c = continuation
        continuation = nil
        c?.resume()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in if self.current == id { self.finish() } }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in if self.current == id { self.finish() } }
    }
}

/// What hands-free mode needs to know about the step on screen.
struct HandsFreeContext {
    var step: StepRef
    var diagnosisSummary: String
    var riskLevel: RiskLevel
    /// What "repeat" reads aloud.
    var spoken: String
}

/// Hands-free mode of the photo guide: listens continuously, runs fast commands on device and sends questions
/// to Muse Voice (transcribe) and Muse Spark (step help). The overlay reads `phase`, `level`, `caption` and `answer`.
@MainActor
@Observable
final class HandsFreeModel {
    enum Phase: Equatable { case off, idle, hearing, thinking, speaking }

    private(set) var phase: Phase = .off
    /// Smoothed microphone level, 0...1.
    private(set) var level: Float = 0
    /// Live words (on-device partial) while the user speaks, then the transcribed question.
    private(set) var caption = ""
    private(set) var answer: String?
    /// Short feedback after a command ("Next step").
    private(set) var notice: String?
    /// Inline hint under the top band (permissions).
    private(set) var hint: String?

    var isActive: Bool { phase != .off }

    @ObservationIgnored var context: () -> HandsFreeContext? = { nil }
    @ObservationIgnored var perform: (HandsFreeCommand) -> Void = { _ in }
    @ObservationIgnored var service: () -> AnalysisService = { MockAPIClient() }

    @ObservationIgnored private var capture: HandsFreeCapture?
    @ObservationIgnored private let speech = SpeechOutput()
    @ObservationIgnored private var simulated = false
    @ObservationIgnored private var pipeline: Task<Void, Never>?
    @ObservationIgnored private var simulation: Task<Void, Never>?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    #if targetEnvironment(simulator)
    static let microphoneAvailable = false
    #else
    static let microphoneAvailable = true
    #endif

    func toggle() async { if isActive { stop() } else { await start() } }

    func start() async {
        guard !isActive else { return }
        hint = nil
        simulated = !Self.microphoneAvailable
        UIApplication.shared.isIdleTimerDisabled = true
        if simulated {
            phase = .idle
            runSimulation()
            Haptics.tap()
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            UIApplication.shared.isIdleTimerDisabled = false
            showHint("Allow the microphone in Settings to use hands-free.")
            return
        }
        let speechOK = await Self.requestSpeechAccess()
        let cap = HandsFreeCapture(speechAuthorized: speechOK)
        cap.onLevel = { [weak self] rms in Task { @MainActor in self?.receive(level: rms) } }
        cap.onSpeechStart = { [weak self] in Task { @MainActor in self?.speechStarted() } }
        cap.onPartial = { [weak self] text in Task { @MainActor in self?.receive(partial: text) } }
        cap.onUtterance = { [weak self] url, text in Task { @MainActor in self?.received(url: url, local: text) } }
        do { try cap.start() } catch {
            UIApplication.shared.isIdleTimerDisabled = false
            showHint("Hands-free could not start the microphone.")
            return
        }
        capture = cap
        phase = .idle
        Haptics.tap()
    }

    func stop() {
        guard isActive else { return }
        pipeline?.cancel(); pipeline = nil
        simulation?.cancel(); simulation = nil
        noticeTask?.cancel()
        speech.stop()
        capture?.stop(); capture = nil
        UIApplication.shared.isIdleTimerDisabled = false
        phase = .off
        level = 0; caption = ""; answer = nil; notice = nil
    }

    func dismissAnswer() {
        guard answer != nil, phase == .speaking || phase == .idle else { return }
        speech.stop()
        answer = nil; caption = ""
        if phase == .speaking { phase = .idle; capture?.setMuted(false) }
    }

    private static func requestSpeechAccess() async -> Bool {
        await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0 == .authorized) }
        }
    }

    private func showHint(_ text: String) {
        hint = text
        Task { try? await Task.sleep(for: .seconds(5)); if hint == text { hint = nil } }
    }

    private func showNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { try? await Task.sleep(for: .seconds(1.4)); if !Task.isCancelled { notice = nil } }
    }

    // MARK: Microphone events

    private func receive(level rms: Float) {
        guard phase == .idle || phase == .hearing else { return }
        // Speech sits around 0.02...0.2 RMS: log-ish curve to 0...1, then ease towards it.
        let target = min(1, max(0, (20 * log10(max(rms, 1e-4)) + 56) / 40))
        level += (target - level) * 0.5
    }

    private func speechStarted() {
        guard phase == .idle else { return }
        caption = ""
        phase = .hearing
    }

    private func receive(partial: String) {
        if phase == .hearing { caption = partial }
    }

    private func received(url: URL, local: String?) {
        guard isActive, phase == .hearing || phase == .idle else { try? FileManager.default.removeItem(at: url); return }
        let heard = (local ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let cmd = HandsFreeCommand.parse(heard) {
            try? FileManager.default.removeItem(at: url)
            handle(cmd)
            return
        }
        capture?.setMuted(true)
        phase = .thinking
        level = 0
        let hasLocal = !heard.isEmpty
        pipeline = Task { await ask(audio: url, localRecognised: hasLocal) }
    }

    // MARK: Commands

    private func handle(_ cmd: HandsFreeCommand) {
        caption = ""
        phase = .idle
        level = 0
        switch cmd {
        case .next: showNotice("Next step"); perform(.next)
        case .back: showNotice("Previous step"); perform(.back)
        case .stop: stop()
        case .repeatStep:
            guard let spoken = context()?.spoken else { return }
            showNotice("Reading step")
            pipeline = Task { await speakAndResume(spoken, showing: nil) }
        }
        if cmd == .next || cmd == .back { Haptics.soft() }
    }

    // MARK: Questions

    private func ask(audio: URL?, localRecognised: Bool) async {
        defer { if let audio { try? FileManager.default.removeItem(at: audio) } }
        let svc = service()
        var question: String
        do {
            question = try await svc.transcribe(fileURL: audio ?? URL(fileURLWithPath: "/dev/null/hf-demo.wav"))
        } catch {
            if simulated { question = "How tight should I pull the thread?" } else { return await fail("Couldn't understand that. Try again.") }
        }
        question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        if Task.isCancelled { return }
        guard !question.isEmpty else { return await fail("I didn't catch that.") }
        // Without an on-device recogniser the Muse transcript also has to carry the fast commands.
        if !localRecognised, let cmd = HandsFreeCommand.parse(question) {
            capture?.setMuted(false)
            return handle(cmd)
        }
        caption = question
        guard let ctx = context() else { return await fail("Couldn't load the step.") }
        do {
            let req = StepHelpRequest(step: ctx.step, diagnosisSummary: ctx.diagnosisSummary, riskLevel: ctx.riskLevel, issueText: question, imageBase64: nil)
            let help = try await svc.stepHelp(req)
            if Task.isCancelled { return }
            let text = help.answer.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return await fail("I don't have an answer for that.") }
            await speakAndResume(text, showing: question)
        } catch {
            if !Task.isCancelled { await fail("Couldn't reach the assistant. Try again.") }
        }
    }

    private func fail(_ text: String) async {
        caption = text
        phase = .idle
        capture?.setMuted(false)
        try? await Task.sleep(for: .seconds(2.2))
        if caption == text { caption = "" }
    }

    /// Shows the answer (when there is one), speaks it with the microphone muted, then leaves the card up briefly.
    private func speakAndResume(_ text: String, showing question: String?) async {
        capture?.setMuted(true)
        phase = .speaking
        if question != nil { answer = text }
        await speech.speak(text)
        if Task.isCancelled { return }
        if question != nil { try? await Task.sleep(for: .seconds(1.6)) }
        if Task.isCancelled { return }
        try? await Task.sleep(for: .milliseconds(300))   // let the room go quiet before listening again
        answer = nil; caption = ""
        phase = .idle
        capture?.setMuted(false)
    }

    // MARK: Simulator (no microphone)

    /// The simulator has no microphone: wait, "hear" one plausible question, and run the real pipeline against the service.
    private func runSimulation() {
        simulation = Task {
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled, phase == .idle else { return }
            phase = .hearing
            caption = ""
            let words = "How tight should I pull the thread?".split(separator: " ").map(String.init)
            for (i, w) in words.enumerated() {
                for _ in 0..<4 { level = Float.random(in: 0.35...0.85); try? await Task.sleep(for: .milliseconds(70)) }
                caption += (i == 0 ? "" : " ") + w
            }
            level = 0
            phase = .thinking
            pipeline = Task { await ask(audio: nil, localRecognised: true) }
        }
    }

    #if DEBUG
    /// Screenshot helper: `-uiHandsFree idle|listening|thinking|answer` shows one frozen state of the overlay.
    func debugShow(_ state: String) {
        guard ["idle", "listening", "thinking", "answer"].contains(state) else { return }
        simulated = true
        UIApplication.shared.isIdleTimerDisabled = false
        let question = "How tight should I pull the thread?"
        switch state {
        case "idle": phase = .idle; level = 0
        case "listening": phase = .hearing; level = 0.72; caption = "How tight should I pull the thread?"
        case "thinking": phase = .thinking; caption = question
        default:
            phase = .speaking; caption = question
            answer = "Pull just until the thread lies flat against the fabric. If the cloth puckers, you are pulling too hard, so loosen the last two stitches a little."
        }
    }
    #endif
}
