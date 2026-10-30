import Foundation

/// Spoken navigation commands recognised on device in hands-free mode.
enum HandsFreeCommand: Equatable, Sendable {
    case next, back, repeatStep, stop

    private static let table: [(HandsFreeCommand, Set<String>)] = [
        (.next, ["next", "done", "finished", "next step", "go next", "continue", "all done", "im done", "i am done", "go to next step", "move on"]),
        (.back, ["back", "previous", "go back", "previous step", "last step", "step back", "go to previous step"]),
        (.repeatStep, ["repeat", "read", "read it", "read step", "read this", "read that", "repeat that", "repeat step", "read it again", "say it again", "say again", "repeat it"]),
        (.stop, ["stop", "exit", "quit", "stop listening", "exit hands free", "stop hands free", "leave hands free", "hands free off", "turn off hands free"]),
    ]
    private static let fillers: Set<String> = ["please", "ok", "okay", "hey", "now", "just", "uh", "um", "so", "alright", "thanks", "thank", "you"]

    /// Matches only when the whole utterance is a command (after dropping filler words), so questions such as
    /// "should I stop pulling the thread?" stay questions.
    static func parse(_ text: String) -> HandsFreeCommand? {
        let lowered = text.lowercased().replacingOccurrences(of: "\u{2019}", with: "").replacingOccurrences(of: "'", with: "")
        let cleaned = lowered.map { $0.isLetter || $0.isNumber ? $0 : " " }
        let words = String(cleaned).split(separator: " ").map(String.init).filter { !fillers.contains($0) }
        guard !words.isEmpty, words.count <= 4 else { return nil }
        let phrase = words.joined(separator: " ")
        // "hands-free" arrives as "hands free" or "handsfree"
        let normalised = phrase.replacingOccurrences(of: "handsfree", with: "hands free")
        return table.first { $0.1.contains(normalised) }?.0
    }
}

/// Energy based voice activity detector: speech starts after ~90 ms above the threshold and ends after
/// `silenceToEnd` of quiet. The noise floor adapts while nobody speaks. Feed it RMS levels (linear 0...1).
struct VoiceActivityDetector {
    enum Event: Equatable {
        case speechStarted
        /// Speech ended; `duration` is the spoken part without the closing silence.
        case speechEnded(duration: TimeInterval)
        /// A click or cough shorter than `minUtterance`: ignore it.
        case discarded
    }

    var silenceToEnd: TimeInterval = 0.7
    var startAfter: TimeInterval = 0.09
    var minUtterance: TimeInterval = 0.25
    var maxUtterance: TimeInterval = 20

    private(set) var isSpeaking = false
    private(set) var noiseFloor: Float = 0.004
    private var voiced: TimeInterval = 0
    private var silence: TimeInterval = 0
    private var spoken: TimeInterval = 0

    private var onThreshold: Float { max(0.02, noiseFloor * 3.5) }
    private var offThreshold: Float { max(0.012, noiseFloor * 2.2) }

    mutating func reset() { isSpeaking = false; voiced = 0; silence = 0; spoken = 0 }

    mutating func process(rms: Float, dt: TimeInterval) -> Event? {
        if !isSpeaking {
            if rms > onThreshold {
                voiced += dt
                if voiced >= startAfter {
                    isSpeaking = true; spoken = voiced; silence = 0; voiced = 0
                    return .speechStarted
                }
            } else {
                voiced = 0
                noiseFloor = min(0.05, noiseFloor * 0.95 + rms * 0.05)
            }
            return nil
        }
        spoken += dt
        if rms < offThreshold { silence += dt } else { silence = 0 }
        if silence >= silenceToEnd || spoken >= maxUtterance {
            let duration = spoken - silence
            reset()
            return duration >= minUtterance ? .speechEnded(duration: duration) : .discarded
        }
        return nil
    }
}
