import SwiftUI

/// Step player: one step per screen, the stitch path / glue zone / solder points drawn on the user's own photo.
struct GuideView: View {
    @Environment(FlowModel.self) private var flow
    @State private var confirmed: Set<Int> = []
    @State private var showHelp = false
    @State private var forward = true
    @State private var expanded: Set<Int> = []

    private var steps: [GuideStep] { flow.response?.guide.steps ?? [] }
    private var index: Int { min(max(flow.currentStep, 0), max(steps.count - 1, 0)) }

    var body: some View {
        GeometryReader { geo in
            if let step = steps[safe: index], let r = flow.response {
                VStack(spacing: 0) {
                    topBand(geo: geo)
                    photo(step, r, geo: geo).frame(height: geo.size.height * 0.36)
                    ScrollView {
                        stepContent(step, r)
                            .id(step.n)
                            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                                    removal: .opacity))
                            .padding(.horizontal, Theme.margin).padding(.top, 16).padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.bottom, 24, for: .scrollContent)
                    .clipped()
                    .mask(VStack(spacing: 0) { Color.black; LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 20) })
                    bottomBar(step)
                }
                .background(Theme.surface)
                .ignoresSafeArea(edges: .top)
            }
        }
        .navigationBarBackButtonHidden()
        .navigationBarHidden(true)
        .sheet(isPresented: $showHelp) { if let s = steps[safe: index] { StepHelpSheet(step: s) } }
    }

    // MARK: Photo

    private func photo(_ step: GuideStep, _ r: AnalyzeResponse, geo: GeometryProxy) -> some View {
        ZStack(alignment: .top) {
            if let img = flow.photo {
                MarkedPhoto(image: img, segments: r.segments, mode: .guide, showLabels: false, focus: DamageFocus.region(for: r.segments)) { size in
                    StepOverlay(step: step, response: r, size: size, aspect: img.size.width / max(img.size.height, 1), darningPhase: darningPhase(for: step, in: r))
                        .id(step.n)
                        .transition(.opacity)
                }
            } else { Color.black }
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Theme.heroRadius, bottomTrailingRadius: Theme.heroRadius, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: step.n)
    }

    /// Close and progress live in their own band above the photo, never on top of the overlay.
    private func topBand(geo: GeometryProxy) -> some View {
        HStack(spacing: 12) {
            CircleIconButton(systemImage: "xmark", label: "Close") { flow.persist(); flow.reset() }
            SegmentBar(count: steps.count, done: index, current: index)
            if steps[safe: index]?.needsConfirmation == true {
                Button("Not working?") { showHelp = true }
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.thread)
            }
        }
        .padding(.horizontal, Theme.margin).padding(.top, geo.safeAreaInsets.top).padding(.bottom, 8)
        .background(Theme.surface)
    }

    private func darningPhase(for step: GuideStep, in r: AnalyzeResponse) -> DarningPhase {
        let dsteps = r.guide.steps.filter { $0.overlay?.type == .stitchPath && $0.overlay?.stitchType == .darning }
        guard dsteps.count >= 2, let i = dsteps.firstIndex(where: { $0.n == step.n }) else { return .all }
        return i == 0 ? .first : (i == 1 ? .second : .all)
    }

    // MARK: Content

    private func stepContent(_ step: GuideStep, _ r: AnalyzeResponse) -> some View {
        let english = Lang.shared.isEnglish
        let parts = DoneWhenLine.split(step.text, english: english)
        let polishedBody = CopyPolish.text(parts.body, english: english)
        let words = polishedBody.split(separator: " ").count
        let sentences = CopyPolish.sentences(polishedBody)
        let long = words > 30 && sentences.count > 1
        var collapsed: [String] = []
        for s in sentences { if collapsed.isEmpty || (collapsed + [s]).joined(separator: " ").split(separator: " ").count <= 30 { collapsed.append(s) } else { break } }
        let showAll = expanded.contains(step.n) || !long
        return VStack(alignment: .leading, spacing: 14) {
            Text("Step \(index + 1) of \(steps.count)").overline()
            Text(step.title).font(.serif(.title2)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text(showAll ? polishedBody : collapsed.joined(separator: " "))
                    .font(.body).lineSpacing(4).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                if !showAll {
                    Button("More") { withAnimation(Theme.spring) { _ = expanded.insert(step.n) } }.font(.body.weight(.medium))
                }
            }
            if let d = parts.doneWhen {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
                    Text(d).font(.subheadline).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            let items = step.usesItems.compactMap { id in r.shoppingList.first { $0.id == id } }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Uses").overline()
                    Text(items.map { Self.shortName($0.name) }.joined(separator: ", "))
                        .font(.footnote).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            if let m = step.commonMistake, !m.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(Theme.thread).frame(width: 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Watch out").overline()
                        Text(CopyPolish.mistake(m, english: english)).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if r.category == .shoe, let t = timerMinutes(step) { TimerRow(minutes: t).id(step.n) }
            if step.overlay?.type == .stitchPath, let image = flow.photo {
                LiveStitchButton(image: image, step: step, response: r, phase: darningPhase(for: step, in: r), demoMode: flow.settings.demoMode)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "soldering iron 25-40W with fine tip and stand" -> "soldering iron 25-40W"
    private static func shortName(_ n: String) -> String {
        var t = n.components(separatedBy: ",").first ?? n
        for sep in [" with ", " for "] { if let r = t.range(of: sep) { t = String(t[..<r.lowerBound]) } }
        return t.lowercasedFirst
    }

    private func timerMinutes(_ step: GuideStep) -> Int? {
        let k = ShoeStepKind(step: step)
        guard k.cure, let m = k.minutes, m >= 1 else { return nil }
        return m
    }

    private func bottomBar(_ step: GuideStep) -> some View {
        let last = index == steps.count - 1
        let locked = step.needsConfirmation && !confirmed.contains(step.n)
        let on = confirmed.contains(step.n)
        return HStack(spacing: 12) {
            if index > 0 {
                CircleIconButton(systemImage: "chevron.left", label: "Back") {
                    forward = false
                    withAnimation(Theme.spring) { flow.currentStep = index - 1 }
                }
            }
            if step.needsConfirmation {
                // one compact bar: the safety check on the left, Done on the right
                Button {
                    if on { confirmed.remove(step.n) } else { confirmed.insert(step.n); Haptics.selection() }
                } label: {
                    HStack(spacing: 10) {
                        CheckCircle(on: on)
                        Text("I've done this safely").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
                Spacer(minLength: 0)
                Button { advance(last: last) } label: { Text(last ? "Finish" : "Done") }
                    .buttonStyle(PrimaryButtonStyle(kind: .primary))
                    .frame(width: 112)
                    .disabled(locked)
            } else {
                Button { advance(last: last) } label: { Text(last ? "Finish" : "Done") }
                    .buttonStyle(PrimaryButtonStyle(kind: .primary))
                Button("Not working?") { showHelp = true }
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.thread)
                    .frame(minWidth: 88, minHeight: 44)
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
    }

    private func advance(last: Bool) {
        flow.markStepDone(index)
        Haptics.success()
        if last { flow.finishRepair() } else {
            forward = true
            withAnimation(Theme.spring) { flow.currentStep = index + 1 }
            flow.persist()
        }
    }
}

/// "Wait 10 min" with a start button and a monospaced countdown (HelloFresh timer row).
struct TimerRow: View {
    let minutes: Int
    @State private var endsAt: Date?
    @State private var tick = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            let left = endsAt.map { max(0, Int($0.timeIntervalSince(tl.date).rounded(.up))) }
            HStack(spacing: 12) {
                Image(systemName: "timer").font(.system(size: 17)).foregroundStyle(Theme.ink)
                Text(minutes >= 120 && minutes % 60 == 0 ? "Wait \(minutes / 60) h" : "Wait \(minutes) min").font(.body.weight(.medium)).foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let left {
                    Text(left == 0 ? "Ready" : String(format: "%d:%02d", left / 60, left % 60)).font(.body.monospacedDigit()).foregroundStyle(Theme.ink)
                } else {
                    Button("Start timer") { endsAt = Date().addingTimeInterval(Double(minutes) * 60); Haptics.tap() }
                        .font(.body.weight(.medium)).foregroundStyle(Theme.thread)
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.thumbRadius + 4, style: .continuous))
        }
        .accessibilityElement(children: .combine)
    }
}

extension String {
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

/// Overlay for one step: stitch path (textile) or highlight.
struct StepOverlay: View {
    let step: GuideStep
    let response: AnalyzeResponse
    let size: CGSize
    let aspect: CGFloat
    var darningPhase: DarningPhase = .all
    /// Precomputed plan for static rendering; the live view computes it in `.task`.
    var staticPlan: StitchPlan? = nil

    @State private var plan: StitchPlan = .empty

    /// Same geometry for the guide.
    static func stitchPlan(step: GuideStep, response: AnalyzeResponse, aspect: CGFloat) -> StitchPlan {
        guard step.overlay?.type == .stitchPath, let s = target(step: step, response: response) else { return .empty }
        return StitchPathPlanner.plan(for: s, stitchType: step.overlay?.stitchType ?? .runningStitch, aspect: aspect)
    }

    static func target(step: GuideStep, response: AnalyzeResponse) -> Segment? {
        if let id = step.overlay?.segmentId, let s = response.segment(id) { return s }
        if let id = step.segmentIds.first, let s = response.segment(id) { return s }
        return response.segments.first { $0.isDamage }
    }

    private var targetSegment: Segment? {
        if let id = step.overlay?.segmentId, let s = response.segment(id) { return s }
        if let id = step.segmentIds.first, let s = response.segment(id) { return s }
        return response.segments.first { $0.isDamage }
    }
    private var isStitch: Bool { step.overlay?.type == .stitchPath }
    private var key: String { "\(step.n)-\(targetSegment?.id ?? "-")-\(step.overlay?.stitchType?.rawValue ?? "-")" }

    var body: some View {
        ZStack {
            if step.overlay?.type == .solder {
                SolderOverlay(step: step, response: response, size: size)
            } else if response.category == .lowVoltageElectronics {
                ElectronicsOverview(step: step, response: response, size: size)
            } else if response.category == .shoe && !isStitch {
                ShoeOverlay(step: step, response: response, size: size)
            } else if isStitch {
                StitchPathView(plan: staticPlan ?? plan, phase: darningPhase)
                    .frame(width: size.width, height: size.height)
                    .id(key + "\(darningPhase)")
            } else {
                let ids = Set(step.segmentIds + (step.overlay?.segmentId.map { [$0] } ?? []))
                // damage is outlined by the photo itself; other referenced parts get a quiet hairline
                ForEach(response.segments.filter { ids.contains($0.id) && !$0.isDamage }) { s in
                    SegmentLayer(segment: s, color: Theme.highlight, size: size, visible: true, pulsing: false, showLabel: false)
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .task(id: key) {
            guard staticPlan == nil else { return }
            plan = Self.stitchPlan(step: step, response: response, aspect: aspect)
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
