import SwiftUI

/// Colour and symbol per model family of the agent trace.
enum ModelStyle {
    static func tint(_ model: String) -> Color {
        let m = model.lowercased()
        if m.contains("sam") { return Theme.partColors[0] }
        if m.contains("wonder") { return Theme.partColors[1] }
        if m.contains("image") { return Theme.partColors[2] }
        if m.contains("spark") { return Theme.thread }
        return Theme.inkSecondary
    }
    static func symbol(_ model: String) -> String {
        let m = model.lowercased()
        if m.contains("sam") { return "square.dashed.inset.filled" }
        if m.contains("wonder") { return "wand.and.stars" }
        if m.contains("image") { return "photo.artframe" }
        return "sparkle"
    }
    /// "sam-3.1" -> "SAM 3.1", "muse-spark-1.3" -> "Muse Spark" ...
    static func display(_ model: String) -> String {
        let l = model.lowercased()
        if l.contains("sam") {
            let ver = l.split(whereSeparator: { $0 == "-" || $0 == " " }).last.map(String.init) ?? ""
            return "SAM " + (ver.first?.isNumber == true ? ver : "3.1")
        }
        if l.contains("spark") { return "Muse Spark" }
        if l.contains("wonder") { return "Muse Wonder" }
        if l.contains("image") { return "Muse Image" }
        return model
    }
    static func seconds(_ ms: Int) -> String {
        ms < 100 ? "\(ms) ms" : String(format: "%.1f s", locale: Lang.shared.locale, Double(ms) / 1000)
    }
}

/// Compact live protocol of the analysis agent: every finished tool call slides in at the bottom.
struct AgentTraceView: View {
    let steps: [AgentStep]
    /// Label and model of the work in progress (shown as the last, pulsing row).
    var active: (label: String, model: String)?
    /// Demo mode replays recorded runs; the badge must not claim "live" then.
    var replay = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Keeps the card short enough to never clip on screen or in the video (demo review 2026-10-29).
    private let maxVisible = 5
    private var visible: [AgentStep] { Array(steps.suffix(active == nil ? maxVisible : maxVisible - 1)) }
    private var hiddenCount: Int { steps.count - visible.count }
    /// First successful step after a failure: the moment the agent re-routed.
    private var recoveredIDs: Set<Int> {
        var ids = Set<Int>(), failed = false
        for s in steps {
            if s.status != .done { failed = true } else if failed { ids.insert(s.n); failed = false }
        }
        return ids
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                SectionLabel(text: "What happened")
                Spacer()
                if !steps.isEmpty {
                    Text(tr("%lld Schritte · %@", steps.count, ModelStyle.seconds(steps.map(\.ms).reduce(0, +))))
                        .font(.caption.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                }
            }
            .padding(.bottom, 4)
            if hiddenCount > 0 {
                Text(tr("+%lld frühere Schritte", hiddenCount))
                    .font(.caption.weight(.semibold)).foregroundStyle(Theme.inkSecondary).padding(.leading, 30).padding(.bottom, 2)
            }
            ForEach(visible) { s in
                row(s)
                    .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
            }
            if let active {
                activeRow(active).transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 12)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Theme.spring, value: steps.map(\.n))
        .animation(.easeInOut(duration: 0.25), value: active?.label)
    }

    /// One leading glyph style for every row: a small status mark, never a model icon.
    private func glyph(_ state: GlyphState) -> some View {
        Group {
            switch state {
            case .done: Image(systemName: "checkmark").foregroundStyle(Theme.inkSecondary)
            case .failed: Image(systemName: "xmark").foregroundStyle(Theme.stop)
            case .running: ProgressView().controlSize(.mini)
            }
        }
        .font(.system(size: 12, weight: .bold)).frame(width: 20, height: 20)
    }
    private enum GlyphState { case done, failed, running }

    /// Same plain caption for every model: "SAM 3.1", "Muse Spark", "Muse Wonder". Steps without a model are on-device work.
    private func modelLabel(_ model: String) -> some View {
        Text(model.isEmpty ? "On device" : ModelStyle.display(model))
            .font(.caption.weight(.medium)).foregroundStyle(Theme.inkSecondary)
    }

    private func row(_ s: AgentStep) -> some View {
        let ok = s.status == .done
        return HStack(spacing: 10) {
            glyph(ok ? .done : .failed)
            Group {
                if ok && recoveredIDs.contains(s.n) {
                    Text(AgentLabel.localized(s.label)).foregroundStyle(Theme.ink)
                        + Text("\n✓ " + tr("Fehler behoben – Agent hat umgeplant")).font(.caption.weight(.semibold)).foregroundStyle(Theme.safe)
                } else if ok { Text(AgentLabel.localized(s.label)).foregroundStyle(Theme.ink) }
                else { Text(AgentLabel.localized(s.label)).foregroundStyle(Theme.ink) + Text("\nServerfehler – Agent weicht aus").font(.caption.weight(.semibold)).foregroundStyle(Theme.stop) }
            }
            .font(.subheadline.weight(.semibold)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                modelLabel(s.model)
                Text(ModelStyle.seconds(s.ms)).font(.caption.monospacedDigit()).foregroundStyle(Theme.inkTertiary)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, ok ? 0 : 6)
        .background(ok ? Color.clear : Theme.stop.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(AgentLabel.localized(s.label)), \(ModelStyle.display(s.model)), \(ModelStyle.seconds(s.ms)), \(ok ? tr("fertig") : tr("fehlgeschlagen, Serverfehler, Agent weicht aus"))")
    }

    private func activeRow(_ a: (label: String, model: String)) -> some View {
        HStack(spacing: 10) {
            glyph(.running)
            Text(AgentLabel.localized(a.label)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkSecondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                modelLabel(a.model)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("%@, läuft", AgentLabel.localized(a.label)))
    }
}

/// Four-segment stage strip with the current stage as text.
struct StageStrip: View {
    let titles: [String]
    let states: [StageState]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                ForEach(0..<states.count, id: \.self) { i in
                    Capsule().fill(color(states[i])).frame(height: 5)
                        .overlay(alignment: .leading) {
                            if states[i] == .active { Capsule().fill(Theme.thread).frame(height: 5).shimmer() }
                        }
                }
            }
            .animation(Theme.spring, value: states)
            if let i = states.firstIndex(of: .active) ?? (states.allSatisfy { $0 == .done } ? states.count - 1 : nil) {
                Text(states.allSatisfy { $0 == .done } ? tr("Fertig") : tr("%lld von %lld · %@", i + 1, states.count, tr(titles[i])))
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ s: StageState) -> Color {
        switch s { case .done: Theme.safe; case .active: Theme.threadSoft; case .pending: Theme.hairline }
    }
}

/// Agent step labels come from the proxy (already in the request locale) or from German recordings.
/// In English mode the structural German phrases of recorded runs are translated; unknown labels stay unchanged.
enum AgentLabel {
    private static let patterns: [(prefix: String, suffix: String, key: String)] = [
        ("SAM sucht „", "“", "SAM sucht „%@“"),
        ("Spark lokalisiert „", "“", "Spark lokalisiert „%@“"),
        ("Spark prüft Maske ", "", "Spark prüft Maske %@"),
    ]

    static func localized(_ label: String, english: Bool = Lang.shared.isEnglish) -> String {
        guard english else { return label }
        let direct = tr(label)
        if direct != label { return direct }
        for p in patterns where label.hasPrefix(p.prefix) && label.hasSuffix(p.suffix) && label.count >= p.prefix.count + p.suffix.count {
            let inner = String(label.dropFirst(p.prefix.count).dropLast(p.suffix.count))
            return tr(p.key, inner)
        }
        return label
    }
}
