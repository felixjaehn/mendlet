import Observation
import UIKit

@MainActor
@Observable
final class LiveScanModel {
    let feed = LiveCameraFeed()
    var category: LiveCategory = .clothing
    private(set) var polygon: [CGPoint] = []
    private(set) var latencyMilliseconds: Int?
    private(set) var detectionError: String?
    private(set) var capturedPhoto: UIImage?
    private(set) var captureScenario: DemoScenario = .textileTear
    private(set) var machine = LiveScanStateMachine()
    var state: LiveScanStateMachine.State { machine.state }
    @ObservationIgnored private let registrar = LiveImageRegistrar()
    @ObservationIgnored private let throttle = LiveDetectionThrottle(detector: MockLiveDetector())
    @ObservationIgnored private var detectionTask: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var anchor: (frame: LiveFrame, points: [CGPoint], id: UUID)?
    @ObservationIgnored private var shownAnchor: UUID?
    @ObservationIgnored private var correction: [CGPoint] = []
    @ObservationIgnored private var morphStart: TimeInterval = 0
    @ObservationIgnored private var lastDetection: TimeInterval = 0
    @ObservationIgnored private var lastAttempt: TimeInterval = -.infinity
    @ObservationIgnored private var conceptIndex = 0

    func run(settings: AppSettings, reduceMotion: Bool) async {
        let token = UUID(); generation = token
        detectionTask?.cancel(); detectionTask = nil
        anchor = nil; polygon = []; shownAnchor = nil; machine.reset()
        capturedPhoto = nil; detectionError = nil; latencyMilliseconds = nil; conceptIndex = 0
        let scenario: DemoScenario = category == .clothing && settings.scenario == .textileHole ? .textileHole : category.scenario
        captureScenario = scenario
        let demo = await DemoImageFactory.imageAsync(for: scenario)
        guard let reference = LiveImage.upright(demo), !Task.isCancelled else { return }
        let detector: any LiveDetector
        if LiveCameraFeed.usesSyntheticFrames(demoMode: settings.demoMode) {
            detector = MockLiveDetector(reference: reference, segment: (try? Fixtures.response(scenario))?.segments.first(where: \.isDamage))
        } else if let url = settings.baseURL {
            detector = ProxyLiveDetector(baseURL: url)
        } else { detectionError = APIError.invalidURL.localizedDescription; return }
        await throttle.use(detector)
        guard generation == token, !Task.isCancelled else { return }
        await feed.run(demoMode: settings.demoMode, demoPhoto: reference, reduceMotion: reduceMotion) { [weak self] frame in
            guard let self, self.generation == token, self.state != .captured else { return }
            await self.process(frame, token: token, reduceMotion: reduceMotion)
        }
        if generation == token { detectionTask?.cancel(); detectionTask = nil }
    }

    private func process(_ frame: LiveFrame, token: UUID, reduceMotion: Bool) async {
        detectIfNeeded(frame, token: token)
        guard let anchor, frame.timestamp - lastDetection < 2.5 else {
            polygon = []; machine.reset(); return
        }
        let transform = await registrar.register(reference: anchor.frame.image, current: frame.image)
        guard !Task.isCancelled, generation == token, self.anchor?.id == anchor.id else { return }
        guard let transform, let target = transform.warp(anchor.points), LiveGeometry.usable(target) else {
            polygon = []; machine.reset(); return
        }
        let oldState = state
        machine.observe(polygon: target, at: frame.timestamp, trackingValid: true)
        if oldState == .searching && state == .detected { Haptics.success() }
        if shownAnchor != anchor.id {
            let previous = LiveGeometry.aligned(polygon, to: target)
            correction = previous.count == target.count ? zip(previous, target).map { CGPoint(x: $0.x - $1.x, y: $0.y - $1.y) } : []
            morphStart = frame.timestamp; shownAnchor = anchor.id
        }
        let remaining = reduceMotion ? 0 : max(0, 1 - (frame.timestamp - morphStart) / 0.22)
        polygon = target.enumerated().map { i, p in
            guard correction.count == target.count else { return p }
            return CGPoint(x: p.x + correction[i].x * remaining, y: p.y + correction[i].y * remaining)
        }
        if state == .stable {
            detectionTask?.cancel()
            do {
                let photo = try await feed.capturePhoto()
                guard generation == token, !Task.isCancelled else { return }
                capturedPhoto = photo; machine.captureSucceeded()
            } catch is CancellationError {
            } catch {
                guard generation == token, !Task.isCancelled else { return }
                detectionError = error.localizedDescription; machine.reset()
            }
        }
    }

    private func detectIfNeeded(_ frame: LiveFrame, token: UUID) {
        guard detectionTask == nil, frame.timestamp - lastAttempt >= 1 else { return }
        lastAttempt = frame.timestamp
        let concept = category.concepts[conceptIndex]
        detectionTask = Task { [weak self, throttle] in
            guard let self else { return }
            defer { if self.generation == token { self.detectionTask = nil } }
            do {
                guard let result = try await throttle.detect(frame: frame.image, concept: concept), !Task.isCancelled, self.generation == token else { return }
                self.latencyMilliseconds = result.latencyMilliseconds
                self.detectionError = nil
                guard let segment = result.segments.filter({ $0.isDamage && $0.score >= 0.5 && LiveGeometry.usable($0.polygon) }).max(by: { $0.score < $1.score }) else {
                    self.anchor = nil; self.polygon = []; self.machine.reset()
                    self.conceptIndex = (self.conceptIndex + 1) % self.category.concepts.count
                    return
                }
                self.anchor = (frame, LiveGeometry.resample(segment.polygon), UUID())
                self.lastDetection = ProcessInfo.processInfo.systemUptime
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.detectionError = error.localizedDescription
                self.anchor = nil; self.polygon = []; self.machine.reset()
            }
        }
    }
}
