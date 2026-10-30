import SwiftUI

/// Photo step guide: every step is a full-bleed photo (the user's own, zoomed to the damage, with the animated overlay,
/// or the Muse Image picture of the step) and the step text sits on a material panel at the bottom.
/// Full-screen size plus the real safe-area insets (the guide draws edge to edge).
private struct FullGeo { var size: CGSize; var safeAreaInsets: EdgeInsets }

struct GuideView: View {
    @Environment(FlowModel.self) private var flow
    @State private var showHelp = false
    @State private var forward = true
    @State private var expanded: Set<Int> = []
    @State private var showStepImage: Set<Int> = []
    @State private var drag: CGFloat = 0
    @State private var handsFree = HandsFreeModel()

    private var steps: [GuideStep] { flow.response?.guide.steps ?? [] }
    private var index: Int { min(max(flow.currentStep, 0), max(steps.count - 1, 0)) }

    var body: some View {
        GeometryReader { safe in
            let inset = safe.safeAreaInsets
            let geo = FullGeo(size: CGSize(width: safe.size.width, height: safe.size.height + inset.top + inset.bottom), safeAreaInsets: inset)
            if let step = steps[safe: index], let r = flow.response {
                let stepPhoto = flow.stepImage(for: step)
                let showMuse = stepPhoto != nil && showStepImage.contains(step.n)
                ZStack(alignment: .bottom) {
                    Color.black
                    ZStack {
                        if showMuse, let stepPhoto {
                            Image(uiImage: stepPhoto).resizable().scaledToFill()
                                .frame(width: geo.size.width, height: geo.size.height).clipped()
                                .overlay(alignment: .topTrailing) { previewTag.padding(.top, geo.safeAreaInsets.top + 112).padding(.trailing, Theme.margin) }
                        } else {
                            photo(step, r, geo: geo)
                        }
                    }
                    .id("\(step.n)-\(showMuse)")
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity), removal: .opacity))
                    .offset(x: drag * 0.25)
                    .overlay { Color.black.opacity(handsFree.isActive ? 0.18 : 0).allowsHitTesting(false).animation(.easeInOut(duration: 0.4), value: handsFree.isActive) }
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.4), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: geo.safeAreaInsets.top + 90).allowsHitTesting(false)
                        Spacer(minLength: 0)
                    }
                    Group {
                        if handsFree.isActive {
                            compactBar(step, bottomInset: geo.safeAreaInsets.bottom)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        } else {
                            panel(step, r, bottomInset: geo.safeAreaInsets.bottom, maxHeight: geo.size.height * 0.7)
                                .id(step.n)
                                .transition(.opacity)
                        }
                    }
                    .animation(Theme.spring, value: handsFree.isActive)
                    if handsFree.isActive {
                        let lay = voicePlacement(r, geo: geo)
                        HandsFreeCapsule(model: handsFree, maxHeight: lay.voice.height)
                            .frame(width: geo.size.width, alignment: .bottom)
                            .frame(height: lay.voice.height, alignment: .bottom)
                            .padding(.bottom, geo.size.height - lay.voice.maxY)
                            .transition(.opacity)
                    }
                    topArea(step, hasStepImage: stepPhoto != nil, topInset: geo.safeAreaInsets.top)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .opacity(handsFree.isActive ? 0.4 : 1)
                        .animation(Theme.spring, value: handsFree.isActive)
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .offset(y: -inset.top)
                .contentShape(Rectangle())
                .gesture(swipe)
                .onAppear { flow.loadStepImage(for: step) }
                .onChange(of: index) { _, _ in if let s = steps[safe: index] { flow.loadStepImage(for: s) } }
            }
        }
        .overlay {
            if handsFree.isActive { HandsFreeGlow(phase: handsFree.phase, level: handsFree.level, answerShown: handsFree.answer != nil).transition(.opacity) }
        }
        .animation(.easeInOut(duration: 0.6), value: handsFree.isActive)
        .background(Color.black.ignoresSafeArea())
        .navigationBarBackButtonHidden()
        .navigationBarHidden(true)
        .statusBarHidden(false)
        .sheet(isPresented: $showHelp) { if let s = steps[safe: index] { StepHelpSheet(step: s) } }
        .onAppear { debugStepImage(); setUpHandsFree() }
        .onDisappear { handsFree.stop() }
    }

    // MARK: Hands-free

    private func setUpHandsFree() {
        handsFree.service = { [flow] in flow.service }
        handsFree.context = { [flow] in
            let steps = flow.response?.guide.steps ?? []
            guard let r = flow.response, let step = steps[safe: min(max(flow.currentStep, 0), max(steps.count - 1, 0))] else { return nil }
            return HandsFreeContext(step: StepRef(n: step.n, title: step.title, text: step.text), diagnosisSummary: r.diagnosis.summary,
                                    riskLevel: r.riskLevel, spoken: spokenText(step, of: steps.count))
        }
        handsFree.perform = { cmd in
            switch cmd {
            case .next: advance(last: index == steps.count - 1)
            case .back: if index > 0 { go(to: index - 1) }
            case .repeatStep, .stop: break
            }
        }
        #if DEBUG
        if let state = UserDefaults.standard.string(forKey: "uiHandsFree") { handsFree.debugShow(state) }
        #endif
    }

    private func spokenText(_ step: GuideStep, of count: Int) -> String {
        let parts = DoneWhenLine.split(step.text, english: true)
        let body = CopyPolish.text(parts.body, english: true)
        return ["Step \(step.n) of \(count).", step.title + ".", body, parts.doneWhen ?? ""]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var handsFreeButton: some View {
        Button {
            Haptics.tap()
            Task { await handsFree.toggle() }
        } label: {
            Image(systemName: "waveform")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.3), in: Circle())
                .glass(Circle(), tint: nil, interactive: true)
                .overlay { if handsFree.isActive { Circle().fill(Color.white.opacity(0.16)) } }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hands-free")
        .accessibilityValue(handsFree.isActive ? "On" : "Off")
        .accessibilityAddTraits(handsFree.isActive ? .isSelected : [])
    }

    // MARK: Swipe

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onChanged { v in if abs(v.translation.width) > abs(v.translation.height) { drag = v.translation.width } }
            .onEnded { v in
                let dx = v.translation.width
                withAnimation(Theme.spring) { drag = 0 }
                guard abs(dx) > 60, abs(dx) > abs(v.translation.height) else { return }
                if dx < 0, index < steps.count - 1 { go(to: index + 1) } else if dx > 0, index > 0 { go(to: index - 1) }
            }
    }

    private func go(to i: Int) {
        forward = i > index
        Haptics.soft()
        withAnimation(Theme.spring) { flow.currentStep = i }
        flow.persist()
    }

    // MARK: Photo

    private static let barContentHeight: CGFloat = 46
    /// Floating bar: 8 pt from the screen edge, lifted a little above the home indicator.
    private static func barBottomGap(_ inset: CGFloat) -> CGFloat { max(8, inset - 12) }
    private static let baseAnchor: CGFloat = 0.33

    private func barHeight(_ geo: FullGeo) -> CGFloat { Self.barContentHeight + 20 + Self.barBottomGap(geo.safeAreaInsets.bottom) }

    /// The work area on screen at the normal anchor: damage bounds scaled by the zoom, padded for stitch overlay and labels.
    private func workRect(_ r: AnalyzeResponse, size: CGSize) -> CGRect {
        let boxes = r.segments.filter(\.isDamage).compactMap(\.normalizedBounds).filter { $0.height > 0 }
        let cy = size.height * Self.baseAnchor
        guard let img = flow.photo, let first = boxes.first else { return CGRect(x: 0, y: cy - 90, width: size.width, height: 180) }
        let u = boxes.dropFirst().reduce(first) { $0.union($1) }
        let zoom = MarkedPhoto<EmptyView>.targetZoom(image: img, focus: DamageFocus.region(for: r.segments), container: size)
        let fill = AspectFit.fillSize(content: img.size, in: size)
        let h = u.height * fill.height * zoom, w = u.width * fill.width * zoom
        let pad: CGFloat = 44
        return CGRect(x: (size.width - w) / 2 - pad, y: cy - h / 2 - pad, width: w + 2 * pad, height: h + 2 * pad)
    }

    private func voicePlacement(_ r: AnalyzeResponse, geo: FullGeo) -> VoiceLayout.Placement {
        let H = geo.size.height
        let vh: CGFloat = handsFree.answer != nil ? min(H * 0.34, 270) : 92
        return VoiceLayout.place(container: geo.size, work: workRect(r, size: geo.size), topReserved: geo.safeAreaInsets.top + 70,
                                 barTop: H - barHeight(geo), voiceHeight: vh)
    }

    private func photoAnchor(_ r: AnalyzeResponse, geo: FullGeo) -> CGFloat {
        let size = geo.size
        guard handsFree.isActive else { return Self.baseAnchor }
        return Self.baseAnchor - voicePlacement(r, geo: geo).photoShift / max(size.height, 1)
    }

    /// Collapsed panel while hands-free is on: opaque, same material, step line and Done only.
    private func compactBar(_ step: GuideStep, bottomInset: CGFloat) -> some View {
        let last = index == steps.count - 1
        return HStack(spacing: 12) {
            Text("Step \(index + 1) of \(steps.count) · \(step.title)")
                .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                .lineLimit(1).minimumScaleFactor(0.8).multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Button { advance(last: last) } label: {
                Text(last ? "Finish" : "Done").font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    .frame(width: 88, height: 38).background(Capsule().fill(Color.white.opacity(0.18)))
            }
            .buttonStyle(.plain)
        }
        .frame(height: Self.barContentHeight)
        .padding(.horizontal, Theme.margin).padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .modifier(HandsFreeGlass(shape: RoundedRectangle(cornerRadius: 28, style: .continuous)))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 8).padding(.bottom, Self.barBottomGap(bottomInset))
    }

    private func photo(_ step: GuideStep, _ r: AnalyzeResponse, geo: FullGeo) -> some View {
        let size = geo.size
        return Group {
            if let img = flow.photo {
                MarkedPhoto(image: img, segments: r.segments, mode: .guide, showLabels: false, focus: DamageFocus.region(for: r.segments), zoomable: false, anchorY: photoAnchor(r, geo: geo)) { sz in
                    StepOverlay(step: step, response: r, size: sz, aspect: img.size.width / max(img.size.height, 1), darningPhase: darningPhase(for: step, in: r))
                }
            } else { Color.black }
        }
        .frame(width: size.width, height: size.height)
    }

    private var previewTag: some View {
        Text("Preview").font(.caption.weight(.semibold)).photoLabel()
    }

    // MARK: Top

    private func topArea(_ step: GuideStep, hasStepImage: Bool, topInset: CGFloat) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                CircleIconButton(systemImage: "xmark", label: "Close", onPhoto: true) { flow.persist(); flow.reset() }
                SegmentBar(count: steps.count, done: index, current: index, height: 4, onPhoto: true)
                handsFreeButton
            }
            if let hint = handsFree.hint {
                Text(hint).font(.footnote.weight(.medium)).photoLabel().transition(.opacity)
            }
            if hasStepImage {
                HStack(spacing: 0) {
                    ForEach([false, true], id: \.self) { muse in
                        let on = showStepImage.contains(step.n) == muse
                        Button {
                            Haptics.tap()
                            withAnimation(.easeInOut(duration: 0.25)) { if muse { _ = showStepImage.insert(step.n) } else { showStepImage.remove(step.n) } }
                        } label: {
                            Text(muse ? "This step" : "Your photo").font(.footnote.weight(.semibold))
                                .foregroundStyle(on ? Color.black : Color.white)
                                .padding(.horizontal, 14).frame(height: 30)
                                .background { if on { Capsule().fill(Color.white) } }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2).glass(Capsule())
            }
        }
        .padding(.horizontal, Theme.margin).padding(.top, topInset + 6)
    }

    private func darningPhase(for step: GuideStep, in r: AnalyzeResponse) -> DarningPhase {
        let dsteps = r.guide.steps.filter { $0.overlay?.type == .stitchPath && $0.overlay?.stitchType == .darning }
        guard dsteps.count >= 2, let i = dsteps.firstIndex(where: { $0.n == step.n }) else { return .all }
        return i == 0 ? .first : (i == 1 ? .second : .all)
    }

    // MARK: Panel

    private func panel(_ step: GuideStep, _ r: AnalyzeResponse, bottomInset: CGFloat, maxHeight: CGFloat) -> some View {
        let english = Lang.shared.isEnglish
        let parts = DoneWhenLine.split(step.text, english: english)
        let body = CopyPolish.text(parts.body, english: english)
        let open = expanded.contains(step.n)
        let items = step.usesItems.compactMap { id in r.shoppingList.first { $0.id == id } }
        let last = index == steps.count - 1
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Step \(index + 1) of \(steps.count)").overline()
                    Text(step.title).font(.title2.weight(.semibold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    Text(body).font(.body).lineSpacing(3).foregroundStyle(Theme.ink)
                        .lineLimit(open ? nil : 3).fixedSize(horizontal: false, vertical: true)
                    if !open && body.count > 130 {
                        Button("More") { withAnimation(Theme.spring) { _ = expanded.insert(step.n) } }.font(.subheadline.weight(.medium))
                    }
                    if let d = parts.doneWhen {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
                            Text(d).font(.subheadline).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if open {
                        if !items.isEmpty {
                            Text("Uses  " + items.map { Self.shortName($0.name) }.joined(separator: ", "))
                                .font(.footnote).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                        }
                        if let m = step.commonMistake, !m.isEmpty {
                            HStack(alignment: .top, spacing: 12) {
                                Rectangle().fill(Theme.thread).frame(width: 2)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Watch out").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Text(CopyPolish.mistake(m, english: english)).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Less") { withAnimation(Theme.spring) { _ = expanded.remove(step.n) } }.font(.subheadline.weight(.medium))
                    }
                    if r.category == .shoe, let t = timerMinutes(step) {
                        TimerRow(minutes: t, itemName: ProjectTitle.title(summary: r.diagnosis.summary, english: english), stepTitle: step.title).id(step.n)
                    }
                    if step.overlay?.type == .stitchPath, let image = flow.photo {
                        LiveStitchButton(image: image, step: step, response: r, phase: darningPhase(for: step, in: r), demoMode: flow.settings.demoMode, compact: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.margin).padding(.top, 20)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maxHeight - 90)
            .fixedSize(horizontal: false, vertical: true)
            actions(last: last)
                .padding(.horizontal, Theme.margin).padding(.top, 10).padding(.bottom, max(bottomInset, 12))
        }
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .overlay(alignment: .top) {
            Capsule().fill(Theme.inkTertiary.opacity(0.5)).frame(width: 36, height: 4).padding(.top, 8)
        }
        .animation(Theme.spring, value: open)
    }

    /// No safety checkbox or "confirm safe" gate on steps. Dangerous items are blocked before any guide exists.
    private func actions(last: Bool) -> some View {
        HStack(spacing: 8) {
            Button { go(to: index - 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.ink).frame(width: 36, height: 44)
            }
            .accessibilityLabel(tr("Back"))
            .opacity(index > 0 ? 1 : 0).disabled(index == 0)
            Button("Not working?") { showHelp = true }
                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.thread)
                .lineLimit(1).fixedSize().frame(minHeight: 44).padding(.horizontal, 6)
            Spacer(minLength: 8)
            Button { advance(last: last) } label: { Text(last ? "Finish" : "Done").lineLimit(1) }
                .buttonStyle(PrimaryButtonStyle(kind: .primary))
                .frame(width: 104)
        }
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

    private func advance(last: Bool) {
        flow.markStepDone(index)
        Haptics.success()
        if last { flow.finishRepair() } else {
            forward = true
            withAnimation(Theme.spring) { flow.currentStep = index + 1 }
            flow.persist()
        }
    }

    /// Screenshot helper: `-uiStepImage YES` opens the "This step" state of the shown step.
    private func debugStepImage() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "uiStepImage"), let s = steps[safe: index] { showStepImage.insert(s.n) }
        #endif
    }
}

/// "Wait 10 min" with a start button and a monospaced countdown (HelloFresh timer row).
struct TimerRow: View {
    let minutes: Int
    var itemName = ""
    var stepTitle = ""
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
                    Button("Start timer") {
                        endsAt = Date().addingTimeInterval(Double(minutes) * 60); Haptics.tap()
                        CureActivityController.shared.start(itemName: itemName, stepTitle: stepTitle, kind: .cure, seconds: Double(minutes) * 60)
                    }
                        .font(.body.weight(.medium)).foregroundStyle(Theme.thread)
                }
            }
            .padding(.horizontal, 16).frame(minHeight: 52)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: Theme.thumbRadius + 4, style: .continuous))
        }
        .accessibilityElement(children: .combine)
        // leaving the step or closing the guide ends the Live Activity
        .onDisappear { CureActivityController.shared.end() }
        .onChange(of: (endsAt.map { max(0, Int($0.timeIntervalSinceNow.rounded(.up))) } ?? -1) == 0) { _, ready in if ready { Haptics.success() } }
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
