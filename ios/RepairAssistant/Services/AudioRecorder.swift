import AVFoundation
import Observation

/// Records 16 kHz mono 16-bit PCM WAV (required by Muse Voice Transcribe), capped at 60 s.
@MainActor
@Observable
final class AudioRecorder {
    static let maxDuration: TimeInterval = 60

    private(set) var isRecording = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = Array(repeating: 0.05, count: 28)
    private(set) var permissionDenied = false

    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var onFinish: (@MainActor (URL?) -> Void)?
    private var simulated = false

    func start(simulated: Bool = false, onFinish: @escaping @MainActor (URL?) -> Void) async {
        guard !isRecording else { return }
        self.simulated = simulated
        self.onFinish = onFinish
        permissionDenied = false
        if !simulated {
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else { permissionDenied = true; return }
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
                try session.setActive(true)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("rec-\(UUID().uuidString).wav")
                let settings: [String: Any] = [
                    AVFormatIDKey: Int(kAudioFormatLinearPCM),
                    AVSampleRateKey: 16000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                ]
                let rec = try AVAudioRecorder(url: url, settings: settings)
                rec.isMeteringEnabled = true
                guard rec.record(forDuration: Self.maxDuration) else { return }
                recorder = rec
            } catch {
                return
            }
        }
        isRecording = true
        elapsed = 0
        levels = Array(repeating: 0.05, count: levels.count)
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(60))
                guard let self else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard isRecording else { return }
        elapsed += 0.06
        var level: Float
        if simulated {
            level = Float.random(in: 0.15...0.95) * (0.55 + 0.45 * Float(sin(elapsed * 4) * 0.5 + 0.5))
        } else if let r = recorder {
            r.updateMeters()
            let db = r.averagePower(forChannel: 0)            // -160...0
            level = max(0.04, min(1, pow(10, db / 40)))
            if !r.isRecording { stop(); return }
        } else { level = 0.05 }
        levels.removeFirst()
        levels.append(level)
        if elapsed >= Self.maxDuration { stop() }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        meterTask?.cancel(); meterTask = nil
        let url = recorder?.url
        recorder?.stop()
        recorder = nil
        if !simulated { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        let cb = onFinish
        onFinish = nil
        cb?(simulated ? nil : url)
    }
}
