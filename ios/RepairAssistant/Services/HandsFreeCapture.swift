import AVFoundation
import Speech

/// Continuous microphone capture for hands-free mode. Runs an energy VAD on the input tap; every utterance is written
/// to a 16 kHz mono WAV (for Muse Voice) and, when available, recognised on device by SFSpeechRecognizer (fast commands).
/// Not actor-isolated on purpose: the tap callback runs on the audio thread.
final class HandsFreeCapture: @unchecked Sendable {
    /// Called on arbitrary threads.
    var onLevel: (@Sendable (Float) -> Void)?
    var onSpeechStart: (@Sendable () -> Void)?
    var onPartial: (@Sendable (String) -> Void)?
    /// WAV of one finished utterance plus the on-device transcript (nil when no recogniser is available).
    var onUtterance: (@Sendable (URL, String?) -> Void)?

    private let lock = NSLock()
    private let engine = AVAudioEngine()
    private var vad = VoiceActivityDetector()
    private var preroll: [AVAudioPCMBuffer] = []
    private var muted = false
    private var running = false
    private var lastLevelTime: CFAbsoluteTime = 0
    private var converter: AVAudioConverter?
    private var utterance: UtteranceBox?
    private var file: AVAudioFile?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private let recognizer: SFSpeechRecognizer?
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: false)!

    init(speechAuthorized: Bool) {
        let r = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        recognizer = (speechAuthorized && r?.isAvailable == true) ? r : nil
    }

    func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: nil) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        running = true
    }

    func stop() {
        lock.lock()
        let wasRunning = running
        running = false
        cancelUtteranceLocked()
        lock.unlock()
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// While muted (thinking, speaking) all input is dropped, so the app cannot hear itself.
    func setMuted(_ value: Bool) {
        lock.lock(); defer { lock.unlock() }
        muted = value
        if value { cancelUtteranceLocked() }
        vad.reset()
        preroll.removeAll()
    }

    // MARK: Audio thread

    private func handle(_ buffer: AVAudioPCMBuffer) {
        let rms = Self.rms(buffer)
        let dt = Double(buffer.frameLength) / buffer.format.sampleRate
        lock.lock()
        guard running, !muted else { lock.unlock(); return }
        let now = CFAbsoluteTimeGetCurrent()
        let reportLevel = now - lastLevelTime > 0.04
        if reportLevel { lastLevelTime = now }
        let event = vad.process(rms: rms, dt: dt)
        var startedCallback = false
        var finished: UtteranceBox?
        switch event {
        case .speechStarted:
            beginUtteranceLocked(format: buffer.format)
            startedCallback = true
        case .speechEnded:
            finished = endUtteranceLocked()
        case .discarded:
            cancelUtteranceLocked()
        case nil:
            break
        }
        if vad.isSpeaking || event == .speechStarted {
            write(buffer)
        } else {
            preroll.append(buffer)
            if preroll.count > 4 { preroll.removeFirst() }
        }
        lock.unlock()
        if reportLevel { onLevel?(rms) }
        if startedCallback { onSpeechStart?() }
        finished?.close()
    }

    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        return (sum / Float(buffer.frameLength)).squareRoot()
    }

    // MARK: Utterances (lock held)

    private func beginUtteranceLocked(format: AVAudioFormat) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hf-\(UUID().uuidString).wav")
        converter = AVAudioConverter(from: format, to: targetFormat)
        file = try? AVAudioFile(forWriting: url, settings: targetFormat.settings, commonFormat: .pcmFormatInt16, interleaved: false)
        let box = UtteranceBox(url: url) { [weak self] url, text in self?.onUtterance?(url, text) }
        utterance = box
        if let recognizer {
            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            req.taskHint = .confirmation
            request = req
            let partial = onPartial
            recognizer.recognitionTask(with: req) { result, error in
                if let result {
                    let text = result.bestTranscription.formattedString
                    box.setText(text, final: result.isFinal)
                    if !result.isFinal { partial?(text) }
                } else if error != nil {
                    box.setText(nil, final: true)
                }
            }
        } else {
            box.setText(nil, final: true)
        }
        for b in preroll { write(b) }
        preroll.removeAll()
    }

    private func write(_ buffer: AVAudioPCMBuffer) {
        guard let file, let converter else { return }
        request?.append(buffer)
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        nonisolated(unsafe) var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 { try? file.write(from: out) }
    }

    private func endUtteranceLocked() -> UtteranceBox? {
        request?.endAudio()
        request = nil
        file = nil          // closing the file finalises the WAV header
        converter = nil
        let box = utterance
        utterance = nil
        return box
    }

    private func cancelUtteranceLocked() {
        request?.endAudio()
        request = nil
        file = nil
        converter = nil
        utterance?.discard()
        utterance = nil
    }
}

/// Waits for the on-device transcript (or a short timeout) before handing an utterance on.
private final class UtteranceBox: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private let deliver: @Sendable (URL, String?) -> Void
    private var text: String?
    private var textFinal = false
    private var closed = false
    private var done = false

    init(url: URL, deliver: @escaping @Sendable (URL, String?) -> Void) { self.url = url; self.deliver = deliver }

    func setText(_ t: String?, final: Bool) {
        lock.lock()
        if let t { text = t }
        if final { textFinal = true }
        lock.unlock()
        tryDeliver(force: false)
    }

    /// Audio is complete; wait up to 1.5 s for the final transcript.
    func close() {
        lock.lock(); closed = true; lock.unlock()
        tryDeliver(force: false)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) { [self] in tryDeliver(force: true) }
    }

    func discard() {
        lock.lock(); done = true; lock.unlock()
        try? FileManager.default.removeItem(at: url)
    }

    private func tryDeliver(force: Bool) {
        lock.lock()
        guard !done, closed, textFinal || force else { lock.unlock(); return }
        done = true
        let t = text
        lock.unlock()
        deliver(url, t)
    }
}
