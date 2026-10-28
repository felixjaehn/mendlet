import XCTest
import simd
@testable import RepairAssistant

final class LiveGeometryTests: XCTestCase {
    func testKnownPerspectiveHomographyWarpsPolygon() throws {
        let h = LiveHomography(matrix: simd_double3x3(rows: [SIMD3(1, 0, 0.1), SIMD3(0, 1, 0.2), SIMD3(0.5, 0, 1)]))
        let result = try XCTUnwrap(h.warp([.zero, CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1)]))
        XCTAssertEqual(result[0].x, 0.1, accuracy: 1e-6)
        XCTAssertEqual(result[0].y, 0.2, accuracy: 1e-6)
        XCTAssertEqual(result[1].x, 1.1 / 1.5, accuracy: 1e-6)
        XCTAssertEqual(result[2].y, 1.2 / 1.5, accuracy: 1e-6)
    }

    func testVisionPixelTranslationFlipsYAxisAndNormalizes() throws {
        let pixels = simd_float3x3(rows: [SIMD3(1, 0, 40), SIMD3(0, 1, 20), SIMD3(0, 0, 1)])
        let h = LiveHomography.vision(pixels, size: CGSize(width: 400, height: 200))
        let point = try XCTUnwrap(h.apply(CGPoint(x: 0.4, y: 0.5)))
        XCTAssertEqual(point.x, 0.5, accuracy: 1e-6)
        XCTAssertEqual(point.y, 0.4, accuracy: 1e-6)
    }

    func testSingularProjectionIsRejected() {
        let h = LiveHomography(matrix: simd_double3x3(rows: [SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 0)]))
        XCTAssertNil(h.warp([.zero, CGPoint(x: 1, y: 1)]))
        XCTAssertFalse(h.isPlausible)
    }

    func testWarpPreservesStitchOrderAndDarningMetadata() throws {
        let plan = StitchPlan(kind: .darning, centerline: [CGPoint(x: 0.5, y: 0.5)],
                              stitches: [StitchPoint(position: CGPoint(x: 0.2, y: 0.3), side: -1, index: 7)],
                              gridLines: [[CGPoint(x: 0.1, y: 0.1), CGPoint(x: 0.6, y: 0.6)]], firstDirectionCount: 1)
        let h = LiveHomography(matrix: simd_double3x3(rows: [SIMD3(1, 0, 0.1), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]))
        let result = try XCTUnwrap(h.warp(plan))
        XCTAssertEqual(result.firstDirectionCount, 1)
        XCTAssertEqual(result.stitches.first?.index, 7)
        XCTAssertEqual(result.stitches.first?.side, -1)
        XCTAssertEqual(result.gridLines[0][1].x, 0.7, accuracy: 1e-6)
    }

    func testAspectFillUsesSameCropAsPreview() {
        let rect = LiveGeometry.aspectFill(image: CGSize(width: 400, height: 300), viewport: CGSize(width: 300, height: 600))
        XCTAssertEqual(rect, CGRect(x: -250, y: 0, width: 800, height: 600))
    }
}

final class LiveScanStateTests: XCTestCase {
    private let mask = [CGPoint(x: 0.3, y: 0.45), CGPoint(x: 0.7, y: 0.45), CGPoint(x: 0.7, y: 0.55), CGPoint(x: 0.3, y: 0.55)]

    func testSearchingDetectedStableCaptured() {
        var machine = LiveScanStateMachine()
        XCTAssertEqual(machine.state, .searching)
        machine.observe(polygon: mask, at: 0, trackingValid: true)
        XCTAssertEqual(machine.state, .detected)
        for i in 1...35 { machine.observe(polygon: mask, at: Double(i) / 30, trackingValid: true) }
        XCTAssertEqual(machine.state, .detected)
        machine.captureSucceeded()
        XCTAssertEqual(machine.state, .detected, "Cannot capture before a stable hold")
        machine.observe(polygon: mask, at: 1.21, trackingValid: true)
        XCTAssertEqual(machine.state, .stable)
        machine.captureSucceeded()
        XCTAssertEqual(machine.state, .captured)
        machine.observe(polygon: [], at: 1.3, trackingValid: false)
        XCTAssertEqual(machine.state, .captured, "Capture is delivered once")
    }

    func testTrackingLossAndFrameGapsResetHold() {
        var machine = LiveScanStateMachine()
        for i in 0...30 { machine.observe(polygon: mask, at: Double(i) / 30, trackingValid: true) }
        machine.observe(polygon: mask, at: 1.03, trackingValid: false)
        XCTAssertEqual(machine.state, .searching)
        machine.observe(polygon: mask, at: 1.1, trackingValid: true)
        machine.observe(polygon: mask, at: 3, trackingValid: true)
        XCTAssertEqual(machine.state, .detected)
    }

    func testSlowCumulativeMovementDoesNotCountAsStable() {
        var machine = LiveScanStateMachine()
        for i in 0...90 {
            let moved = mask.map { CGPoint(x: $0.x + Double(i) * 0.001, y: $0.y) }
            machine.observe(polygon: moved, at: Double(i) / 30, trackingValid: true)
            XCTAssertEqual(machine.state, .detected)
        }
    }

    func testInvalidAndOffscreenMasksCannotCapture() {
        var machine = LiveScanStateMachine()
        machine.observe(polygon: [CGPoint(x: CGFloat.nan, y: 0), .zero, CGPoint(x: 1, y: 1)], at: 0, trackingValid: true)
        XCTAssertEqual(machine.state, .searching)
        machine.observe(polygon: mask.map { CGPoint(x: $0.x + 1, y: $0.y) }, at: 1, trackingValid: true)
        XCTAssertEqual(machine.state, .searching)
    }

    func testCategoryConcepts() {
        XCTAssertEqual(LiveCategory.clothing.concepts, ["tear", "hole"])
        XCTAssertEqual(LiveCategory.shoe.concepts, ["detached sole"])
        XCTAssertEqual(LiveCategory.electronics.concepts, ["wire"])
    }
}

private actor SuspendedLiveDetector: LiveDetector {
    private var waiting: CheckedContinuation<Void, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var started = false
    private(set) var active = 0
    private(set) var peak = 0
    private(set) var calls = 0

    func detect(frame: CGImage, concept: String) async throws -> [Segment] {
        active += 1; calls += 1; peak = max(peak, active); started = true
        startWaiter?.resume(); startWaiter = nil
        await withCheckedContinuation { waiting = $0 }
        active -= 1
        return []
    }
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func release() { started = false; waiting?.resume(); waiting = nil }
}

@MainActor
final class LiveThrottleTests: XCTestCase {
    func testNoConcurrentRequestsEvenWhenCancelledAndCategoryChanges() async throws {
        let image = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage())
        let detector = SuspendedLiveDetector()
        let throttle = LiveDetectionThrottle(detector: detector)
        let first = Task { try await throttle.detect(frame: image, concept: "tear", now: 10) }
        await detector.waitForStart()
        first.cancel()
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<30 { group.addTask { (try? await throttle.detect(frame: image, concept: "hole", now: 20)) == nil } }
            for await skipped in group { XCTAssertTrue(skipped) }
        }
        let peak = await detector.peak
        let calls = await detector.calls
        XCTAssertEqual(peak, 1); XCTAssertEqual(calls, 1)
        await detector.release()
        do { _ = try await first.value; XCTFail("Cancelled request must not publish a detection") } catch is CancellationError {} catch { XCTFail("\(error)") }
        let tooEarly = try await throttle.detect(frame: image, concept: "hole", now: 10.9)
        XCTAssertNil(tooEarly)
        let second = Task { try await throttle.detect(frame: image, concept: "hole", now: 11) }
        await detector.waitForStart()
        await detector.release()
        let secondResult = try await second.value
        XCTAssertNotNil(secondResult)
        let total = await detector.calls
        XCTAssertEqual(total, 2)
    }
}
