import SwiftUI

enum Fmt {
    static func number(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: Lang.shared.isEnglish ? "." : ",")
    }
    static func range(_ a: [Double], unit: String) -> String {
        switch a.count {
        case 0: return "–"
        case 1: return "\(number(a[0])) \(unit)"
        default: return "\(number(a[0]))–\(number(a[1])) \(unit)"
        }
    }
    static func minutes(_ a: [Int]) -> String { range(a.map(Double.init), unit: tr("Min.")) }
    static func euro(_ a: [Double]) -> String { range(a, unit: "€") }

    /// "About 1 h", "20 to 45 min", "1 to 2 h" (English UI); the German format keeps the old range.
    static func duration(_ a: [Int]) -> String {
        guard Lang.shared.isEnglish else { return minutes(a) }
        guard let lo = a.first else { return "–" }
        let hi = a.count > 1 ? a[1] : lo
        func hours(_ m: Int) -> String { let h = Double(m) / 60; return h.rounded() == h ? String(Int(h)) : String(format: "%.1f", h) }
        if hi <= 0 { return "–" }
        if lo == hi { return hi >= 60 ? "About \(hours(hi)) h" : "About \(hi) min" }
        if hi > 60 && lo >= 60 { return "\(hours(lo)) to \(hours(hi)) h" }
        if hi > 60 { return "About \(hours((lo + hi) / 2)) h" }
        return "\(lo) to \(hi) min"
    }

    /// "€ 5–12"; "None" when nothing is needed.
    static func cost(_ a: [Double]) -> String {
        guard Lang.shared.isEnglish else { return euro(a) }
        guard let lo = a.first else { return "–" }
        let hi = a.count > 1 ? a[1] : lo
        if hi <= 0 { return "None" }
        return lo == hi ? "€ \(number(lo))" : "€ \(number(lo))–\(number(hi))"
    }
}

extension Recommendation {
    var title: String {
        switch self {
        case .repairSelf: tr("Selbst reparieren")
        case .repairPro: tr("Zum Profi")
        case .replace: tr("Ersetzen")
        }
    }
    var headline: String {
        switch self {
        case .repairSelf: "Repair it yourself."
        case .repairPro: "Take it to a pro."
        case .replace: "Time to let it go."
        }
    }
}

extension SecondLife {
    var symbol: String {
        switch kind {
        case .upcycle: "scissors"
        case .recycle: "arrow.3.trianglepath"
        default: "gift"
        }
    }
}

/// Verdict: a confident recommendation with the marked photo still the hero, time and cost as quiet facts, one next action.
struct DecisionView: View {
    @Environment(FlowModel.self) private var flow
    @State private var repaired = false
    @State private var factsShown = false

    var body: some View {
        GeometryReader { geo in
            let photoHeight = geo.size.height * 0.40
            ZStack(alignment: .top) {
                Theme.surface.ignoresSafeArea()
                VStack(spacing: 0) {
                    hero(geo: geo).frame(height: photoHeight)
                    sheet
                        .padding(.top, -Theme.heroRadius)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .navigationBarBackButtonHidden()
        .navigationBarHidden(true)
        .onAppear {
            if flow.response?.decision?.recommendation == .repairSelf { flow.loadAfterPreview() }
            withAnimation(.easeOut(duration: 0.5).delay(0.2)) { factsShown = true }
        }
        .floatingBar { cta }
    }

    // MARK: Hero

    private func hero(geo: GeometryProxy) -> some View {
        ZStack(alignment: .top) {
            if let photo = flow.photo, let r = flow.response {
                if repaired, let after = flow.afterImage {
                    BeforeAfterSlider(before: photo, after: after, aspect: nil, cornerRadius: 0, labels: false)
                        .overlay(alignment: .bottomLeading) {
                            Text("Preview").font(.footnote.weight(.semibold)).foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 2)
                                .padding(.leading, Theme.margin).padding(.bottom, Theme.heroRadius + 12)
                        }
                        .transition(.opacity)
                } else {
                    MarkedPhoto(image: photo, segments: r.segments, showDimension: true, focus: DamageFocus.region(for: r.segments))
                        .transition(.opacity)
                }
            } else {
                Color.black
            }
            HStack {
                CircleIconButton(systemImage: "chevron.left", label: "Back", onPhoto: true) { if !flow.path.isEmpty { flow.path.removeLast() } }
                Spacer()
            }
            .padding(.horizontal, Theme.margin).padding(.top, geo.safeAreaInsets.top + 8)
            .frame(maxHeight: .infinity, alignment: .top)
            if flow.afterState == .ready, flow.response?.decision?.recommendation == .repairSelf {
                HeroModeToggle(repaired: $repaired)
                    .padding(.bottom, Theme.heroRadius + 12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 0.3), value: repaired)
    }

    // MARK: Sheet

    private var sheet: some View {
        ScrollView {
            if let d = flow.response?.decision, let r = flow.response {
                VStack(alignment: .leading, spacing: 16) {
                    Text("My advice").overline()
                    Text(d.recommendation.headline).font(.serif(.title)).foregroundStyle(Theme.ink)
                    reasonText(d)
                    switch d.recommendation {
                    case .repairSelf:
                        facts(d)
                        checklistRow(r)
                    case .repairPro:
                        facts(d, pro: true)
                        askFor(d)
                    case .replace:
                        if !d.secondLife.isEmpty { secondLife(d.secondLife) }
                        if let hi = d.costEur.last, hi > 0 {
                            Text("A replacement costs about \(Fmt.number(d.costEur.first ?? hi))–\(Fmt.number(hi)) EUR.").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.margin).padding(.top, 24).padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .background(Theme.surface, in: UnevenRoundedRectangle(topLeadingRadius: Theme.heroRadius, topTrailingRadius: Theme.heroRadius, style: .continuous))
    }

    private func reasonText(_ d: Decision) -> some View {
        let sentences = CopyPolish.sentences(CopyPolish.text(d.reasoning, english: Lang.shared.isEnglish))
        let text = d.recommendation == .repairPro ? (sentences.first ?? "") : sentences.prefix(2).joined(separator: " ")
        return Text(text).font(.body).foregroundStyle(Theme.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
    }

    private func askFor(_ d: Decision) -> some View {
        let s = CopyPolish.sentences(CopyPolish.text(d.reasoning, english: Lang.shared.isEnglish))
        return Group {
            if s.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What to ask for").overline()
                    Text(s.dropFirst().joined(separator: " ")).font(.body).foregroundStyle(Theme.ink).lineSpacing(4)
                }
            }
        }
    }

    /// Effort / time / cost as quiet columns separated by hairlines (Zopa rows, no cards).
    private func facts(_ d: Decision, pro: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 0) {
                fact("Effort", pro ? "Pro job" : effortText(d.effort))
                divider
                fact("Time", pro ? "At the shop" : Fmt.duration(d.timeMinutes))
                divider
                fact("Cost", Fmt.cost(d.costEur))
            }
            Text("Estimates, not quotes.").font(.footnote).foregroundStyle(Theme.inkTertiary)
        }
        .opacity(factsShown ? 1 : 0)
    }

    private var divider: some View { Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 40).padding(.horizontal, 16) }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).overline()
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.8).lineLimit(1).contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func effortText(_ e: Effort) -> String {
        switch e { case .low: "Low"; case .medium: "Medium"; case .high: "High" }
    }

    private func checklistRow(_ r: AnalyzeResponse) -> some View {
        let items = r.shoppingList
        let have = items.filter { flow.statuses[$0.id] == .have }.count
        let subtitle = have == items.count ? "Everything is ready" : (have == 0 ? "\(items.count) things to gather" : "\(items.count) things to gather, you have \(have)")
        return Group {
            if !items.isEmpty {
                Button { startAndGather() } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Before you start").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                            Text(subtitle).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
                    }
                    .padding(16)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                }
                .buttonStyle(PressScaleStyle())
            }
        }
    }

    private func secondLife(_ ideas: [SecondLife]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Give it a second life").overline().padding(.bottom, 4)
            ForEach(Array(ideas.prefix(3).enumerated()), id: \.offset) { i, idea in
                if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 52) }
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: idea.symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(Theme.ink)
                        .frame(width: 36, height: 36).background(Theme.fill, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(idea.title).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                        Text(idea.text).font(.subheadline).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: CTA

    @ViewBuilder private var cta: some View {
        if let d = flow.response?.decision {
            VStack(spacing: 0) {
                switch d.recommendation {
                case .repairSelf:
                    if FlowGate.canNavigate(to: .guide, response: flow.response) {
                        PrimaryButton(title: "Start repair") { startAndGather() }
                    } else {
                        PrimaryButton(title: "Take a new photo") { flow.reset() }
                    }
                case .repairPro:
                    PrimaryButton(title: "Save for later") { flow.startProject(parked: true); flow.reset() }
                    PrimaryButton(title: "Close", kind: .secondary) { flow.reset() }
                case .replace:
                    PrimaryButton(title: "Done") { flow.reset() }
                    PrimaryButton(title: "Scan something else", kind: .secondary) { flow.reset(); flow.showScan = true }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.vertical, 12)
        }
    }

    /// "Start repair" creates the project, then the "Before you start" check (never blocks), then the steps.
    private func startAndGather() {
        flow.startProject()
        if FlowGate.canNavigate(to: .shopping, response: flow.response) { flow.go(.shopping) } else { flow.startRepair() }
    }
}

/// "Marked | Repaired": glass two-segment capsule on the hero.
struct HeroModeToggle: View {
    @Binding var repaired: Bool
    var body: some View {
        HStack(spacing: 0) {
            seg("Marked", on: !repaired) { repaired = false }
            seg("Repaired", on: repaired) { repaired = true }
        }
        .padding(3)
        .glass(Capsule(), tint: Color.black.opacity(0.2))
    }
    private func seg(_ t: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button { action(); Haptics.selection() } label: {
            Text(t).font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.black : Color.white)
                .padding(.horizontal, 16).frame(height: 32)
                .background(on ? Color.white.opacity(0.92) : Color.clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}
