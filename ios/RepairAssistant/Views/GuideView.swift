import SwiftUI

struct GuideView: View {
    @Environment(FlowModel.self) private var flow
    @State private var confirmed: Set<Int> = []
    @State private var showHelp = false
    @State private var forward = true

    private var steps: [GuideStep] { flow.response?.guide.steps ?? [] }
    private var index: Int { min(max(flow.currentStep, 0), max(steps.count - 1, 0)) }

    var body: some View {
        VStack(spacing: 0) {
            if let step = steps[safe: index], let r = flow.response {
                topBar
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        photo(step, r)
                        if step.overlay?.type == .stitchPath, let image = flow.photo {
                            LiveStitchButton(image: image, step: step, response: r, phase: darningPhase(for: step, in: r), demoMode: flow.settings.demoMode)
                        }
                        stepContent(step, r)
                    }
                    .id(step.n)
                    .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                            removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                    .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 16)
                }
                .scrollIndicators(.hidden)
                bottomBar(step)
            }
        }
        .clipped()
        .screenBackground()
        .navigationBarBackButtonHidden()
        .navigationBarHidden(true)
        .sheet(isPresented: $showHelp) { if let s = steps[safe: index] { StepHelpSheet(step: s) } }
    }

    // MARK: Top

    private var topBar: some View {
        VStack(spacing: 10) {
            SegmentedProgressBar(count: steps.count, current: index, completed: flow.completedSteps)
            HStack {
                Text("Schritt \(index + 1) von \(steps.count)").font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.inkSecondary)
                Spacer()
                if let r = flow.response, let photo = flow.photo {
                    ShareLink(item: GuidePDF(response: r, photo: photo, after: flow.afterImage),
                              preview: SharePreview(tr("Reparaturanleitung"), image: Image(systemName: "doc.richtext"))) {
                        Image(systemName: "square.and.arrow.up").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                            .frame(width: 36, height: 36).glass(Circle(), interactive: true)
                    }
                    .accessibilityLabel(tr("Anleitung exportieren"))
                }
                Button {
                    flow.persist(); flow.reset()
                } label: {
                    Text("Schließen").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).frame(minHeight: 36).glass(Capsule(), interactive: true)
                }
                .accessibilityHint("Der Stand bleibt gespeichert")
            }
        }
        .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 4)
    }

    // MARK: Photo

    private func photo(_ step: GuideStep, _ r: AnalyzeResponse) -> some View {
        Group {
            if let img = flow.photo {
                PhotoStage(image: img) { size in
                    StepOverlay(step: step, response: r, size: size, aspect: img.size.width / max(img.size.height, 1), darningPhase: darningPhase(for: step, in: r))
                }
                .overlay(alignment: .topLeading) {
                    if let st = step.overlay?.stitchType, step.overlay?.type == .stitchPath {
                        HStack(spacing: 6) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                            Text(st.germanName)
                        }
                        .font(.footnote.weight(.bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Theme.thread, in: Capsule()).padding(12)
                    }
                }
            }
        }
    }

    private func darningPhase(for step: GuideStep, in r: AnalyzeResponse) -> DarningPhase {
        let dsteps = r.guide.steps.filter { $0.overlay?.type == .stitchPath && $0.overlay?.stitchType == .darning }
        guard dsteps.count >= 2, let i = dsteps.firstIndex(where: { $0.n == step.n }) else { return .all }
        return i == 0 ? .first : (i == 1 ? .second : .all)
    }

    // MARK: Content

    private func stepContent(_ step: GuideStep, _ r: AnalyzeResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let items = step.usesItems.compactMap { id in r.shoppingList.first { $0.id == id } }
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Du brauchst")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(items) { it in
                                Chip(title: it.name.components(separatedBy: ",").first ?? it.name, systemImage: it.kind == .tool ? "scissors" : "tag", tint: Theme.inkSecondary, isOn: true)
                            }
                        }
                        .padding(.horizontal, Theme.margin)
                    }
                    .padding(.horizontal, -Theme.margin)
                }
            }
            if step.needsConfirmation { safetyBanner(step) }
            Text(step.title).font(.title2.bold()).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Text(step.text).font(.title3).foregroundStyle(Theme.ink).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if let m = step.commonMistake, !m.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.bubble.fill").foregroundStyle(Theme.caution).font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Typischer Fehler").font(.subheadline.weight(.bold)).foregroundStyle(Theme.caution)
                        Text(m).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.cautionSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func safetyBanner(_ step: GuideStep) -> some View {
        let on = confirmed.contains(step.n)
        return Button {
            if on { confirmed.remove(step.n) } else { confirmed.insert(step.n); Haptics.selection() }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.title2)
                    .foregroundStyle(on ? Theme.safe : Theme.caution)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Vorsicht bei diesem Schritt").font(.subheadline.weight(.bold)).foregroundStyle(Theme.caution)
                    Text("Verstanden, ich passe auf").font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Theme.cautionSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.caution.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Bottom

    private func bottomBar(_ step: GuideStep) -> some View {
        let last = index == steps.count - 1
        let locked = step.needsConfirmation && !confirmed.contains(step.n)
        return HStack(spacing: 10) {
            CircleIconButton(systemImage: "chevron.left", label: "Zurück") {
                guard index > 0 else { return }
                forward = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { flow.currentStep = index - 1 }
            }
            .opacity(index == 0 ? 0.35 : 1).disabled(index == 0)
            PrimaryButton(title: last ? "Fertig" : "Erledigt", systemImage: "checkmark") {
                flow.markStepDone(index)
                Haptics.success()
                if last { flow.finishRepair() } else {
                    forward = true
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { flow.currentStep = index + 1 }
                    flow.persist()
                }
            }
            .disabled(locked)
            Button { showHelp = true } label: {
                Text("Hilft nicht").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    .padding(.horizontal, 14).frame(minHeight: 56)
                    .glass(Capsule(), interactive: true)
            }
        }
        .padding(.horizontal, Theme.margin).padding(.vertical, 10)
        
    }
}

/// Overlay for one step: stitch path (textile) or highlight.
struct StepOverlay: View {
    let step: GuideStep
    let response: AnalyzeResponse
    let size: CGSize
    let aspect: CGFloat
    var darningPhase: DarningPhase = .all
    /// Precomputed plan for static rendering (PDF export); the live view computes it in `.task`.
    var staticPlan: StitchPlan? = nil

    @State private var plan: StitchPlan = .empty

    /// Same geometry for the guide and the PDF export.
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
                if let s = targetSegment {
                    SegmentLayer(segment: s, color: Theme.highlight, size: size, visible: true, pulsing: false, showLabel: false)
                        .opacity(0.35)
                }
                StitchPathView(plan: staticPlan ?? plan, phase: darningPhase)
                    .frame(width: size.width, height: size.height)
                    .id(key + "\(darningPhase)")
            } else {
                let ids = Set(step.segmentIds + (step.overlay?.segmentId.map { [$0] } ?? []))
                ForEach(response.segments.filter { ids.contains($0.id) || (ids.isEmpty && $0.isDamage) }) { s in
                    SegmentLayer(segment: s, color: segmentColor(s, in: response.segments), size: size, visible: true, pulsing: true, showLabel: s.isDamage)
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
