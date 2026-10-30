import SwiftUI
import Observation

/// Builds the same planner output as the photo overlay once, before opening the camera.
struct LiveStitchButton: View {
    let image: UIImage
    let step: GuideStep
    let response: AnalyzeResponse
    let phase: DarningPhase
    let demoMode: Bool
    /// Small text button (inside the guide panel) instead of the full-width secondary button.
    var compact = false
    @State private var presentation: LiveStitchPresentation?
    @State private var preparing = false

    private var segment: Segment? {
        if let id = step.overlay?.segmentId, let segment = response.segment(id), segment.isDamage { return segment }
        if let segment = step.segmentIds.compactMap(response.segment).first(where: \.isDamage) { return segment }
        return response.segments.first(where: \.isDamage)
    }

    private func start() {
        guard let segment, let reference = LiveImage.upright(image) else { return }
        preparing = true
        let type = step.overlay?.stitchType ?? .runningStitch
        let aspect = CGFloat(reference.width) / CGFloat(reference.height)
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                StitchPathPlanner.plan(for: segment, stitchType: type, aspect: aspect)
            }.value
            presentation = LiveStitchPresentation(reference: reference, plan: plan)
            preparing = false
        }
    }

    var body: some View {
        Group {
            if compact {
                Button(action: start) {
                    Label(preparing ? "Stichpfad vorbereiten…" : "Live auf dem Stoff", systemImage: "viewfinder")
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.thread).frame(minHeight: 36)
                }
            } else {
                PrimaryButton(title: preparing ? "Stichpfad vorbereiten…" : "Live auf dem Stoff", systemImage: "viewfinder", kind: .secondary, action: start)
            }
        }
        .disabled(preparing || segment == nil)
        .fullScreenCover(item: $presentation) { item in
            LiveStitchView(reference: item.reference, plan: item.plan, phase: phase, demoMode: demoMode)
        }
    }
}

private struct LiveStitchPresentation: Identifiable {
    let id = UUID()
    let reference: CGImage
    let plan: StitchPlan
}

@MainActor
@Observable
final class LiveStitchModel {
    let feed = LiveCameraFeed()
    private(set) var plan = StitchPlan.empty
    private(set) var registered = false
    @ObservationIgnored private let registrar = LiveImageRegistrar()

    func run(reference: CGImage, plan sourcePlan: StitchPlan, demoMode: Bool, reduceMotion: Bool) async {
        registered = false; plan = .empty
        await feed.run(demoMode: demoMode, demoPhoto: reference, reduceMotion: reduceMotion) { [weak self] frame in
            guard let self else { return }
            let transform = await self.registrar.register(reference: reference, current: frame.image)
            guard !Task.isCancelled else { return }
            if let transform, let warped = transform.warp(sourcePlan), sourcePlan.kind != .none,
               (warped.stitches.map(\.position) + warped.gridLines.flatMap { $0 }).contains(where: { (0...1).contains($0.x) && (0...1).contains($0.y) }) {
                self.plan = warped; self.registered = true
            } else { self.plan = .empty; self.registered = false }
        }
        registered = false; plan = .empty
    }
}

struct LiveStitchView: View {
    let reference: CGImage
    let plan: StitchPlan
    let phase: DarningPhase
    let demoMode: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = LiveStitchModel()

    var body: some View {
        ZStack {
            LiveCameraSurface(feed: model.feed)
            LiveStitchOverlay(model: model, phase: phase)
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .top) {
            LiveCameraHeader(title: tr("Live auf dem Stoff"), synthetic: model.feed.isSynthetic) { dismiss() }
        }
        .safeAreaInset(edge: .bottom) {
            Text(model.feed.error ?? (model.registered ? tr("Folge den nummerierten Stichpunkten") : tr("Kamera auf die markierte Stelle richten")))
                .font(.headline).multilineTextAlignment(.center).foregroundStyle(Theme.ink)
                .padding(Theme.margin).frame(maxWidth: .infinity).background(.regularMaterial)
        }
        .task(id: "\(scenePhase)-\(reduceMotion)") {
            guard scenePhase == .active else { return }
            await model.run(reference: reference, plan: plan, demoMode: demoMode, reduceMotion: reduceMotion)
        }
    }
}

private struct LiveStitchOverlay: View {
    let model: LiveStitchModel
    let phase: DarningPhase
    var body: some View {
        GeometryReader { geometry in
            let rect = LiveGeometry.aspectFill(image: model.feed.imageSize, viewport: geometry.size)
            // Keeping the renderer mounted preserves its thread/needle animation across frames.
            StitchPathView(plan: model.plan, phase: phase)
                .frame(width: rect.width, height: rect.height).position(x: rect.midX, y: rect.midY)
        }
        .clipped().allowsHitTesting(false).accessibilityHidden(true)
    }
}
