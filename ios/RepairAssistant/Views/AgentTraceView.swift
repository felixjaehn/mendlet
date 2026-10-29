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
    static func seconds(_ ms: Int) -> String {
        ms < 100 ? "\(ms) ms" : String(format: "%.1f s", Double(ms) / 1000).replacingOccurrences(of: ".", with: ",")
    }
}

/// Compact live protocol of the analysis agent: every finished tool call slides in at the bottom.
struct AgentTraceView: View {
    let steps: [AgentStep]
    /// Label and model of the work in progress (shown as the last, pulsing row).
    var active: (label: String, model: String)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                SectionLabel(text: "Agenten-Protokoll")
                Spacer()
                if active != nil { LiveDot() }
            }
            .padding(.bottom, 4)
            ForEach(steps) { s in
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

    private func tile(_ model: String, ok: Bool = true) -> some View {
        let tint = ok ? ModelStyle.tint(model) : Theme.stop
        return Image(systemName: ModelStyle.symbol(model)).font(.system(size: 13, weight: .bold)).foregroundStyle(tint)
            .frame(width: 28, height: 28).background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func badge(_ model: String, ok: Bool = true) -> some View {
        Text(model).font(.system(size: 10.5, weight: .bold)).textCase(.uppercase).tracking(0.3)
            .foregroundStyle(ok ? ModelStyle.tint(model) : Theme.stop)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background((ok ? ModelStyle.tint(model) : Theme.stop).opacity(0.12), in: Capsule())
    }

    private func row(_ s: AgentStep) -> some View {
        let ok = s.status == .done
        return HStack(spacing: 10) {
            tile(s.model, ok: ok)
            Text(s.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                badge(s.model, ok: ok)
                HStack(spacing: 4) {
                    Text(ModelStyle.seconds(s.ms)).font(.caption.monospacedDigit().weight(.medium)).foregroundStyle(Theme.inkSecondary)
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill").font(.caption).foregroundStyle(ok ? Theme.safe : Theme.stop)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.label), \(s.model), \(ModelStyle.seconds(s.ms)), \(ok ? "fertig" : "fehlgeschlagen")")
    }

    private func activeRow(_ a: (label: String, model: String)) -> some View {
        HStack(spacing: 10) {
            tile(a.model)
            Text(a.label).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.inkSecondary).lineLimit(2)
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                badge(a.model)
                ProgressView().controlSize(.mini).tint(ModelStyle.tint(a.model))
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(a.label), läuft")
    }
}

private struct LiveDot: View {
    @State private var on = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Theme.thread).frame(width: 7, height: 7).opacity(on ? 1 : 0.35)
            Text("live").font(.caption2.weight(.bold)).textCase(.uppercase).foregroundStyle(Theme.thread)
        }
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { on = true } } else { on = true } }
        .accessibilityHidden(true)
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
                Text(states.allSatisfy { $0 == .done } ? "Fertig" : "\(i + 1) von \(states.count) · \(titles[i])")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func color(_ s: StageState) -> Color {
        switch s { case .done: Theme.safe; case .active: Theme.threadSoft; case .pending: Theme.hairline }
    }
}
