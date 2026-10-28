import XCTest
@testable import RepairAssistant

@MainActor
final class LivePipelineTests: XCTestCase {
    func testDemoPipelineCapturesFullResolutionPhoto() async throws {
        let name = "LivePipelineTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = AppSettings(defaults: defaults)
        settings.demoMode = true
        let model = LiveScanModel()
        let run = Task { await model.run(settings: settings, reduceMotion: false) }
        defer { run.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(12))
        while model.state != .captured && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(model.state, .captured, model.feed.error ?? model.detectionError ?? "Demo registration never stabilized")
        let image = try XCTUnwrap(model.capturedPhoto)
        XCTAssertEqual(image.cgImage?.width, 1500)
        XCTAssertEqual(image.cgImage?.height, 1200)
        XCTAssertNotNil(model.latencyMilliseconds)
    }

    func testVisionRegistersKnownTranslationInCorrectDirection() async throws {
        let image = try XCTUnwrap(DemoImageFactory.image(for: .textileTear).cgImage)
        let source = LiveImage.scaled(image, longestSide: 384)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        let size = CGSize(width: source.width, height: source.height)
        let shifted = try XCTUnwrap(UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: source).draw(in: CGRect(x: 12, y: 8, width: size.width, height: size.height))
        }.cgImage)
        let registrar = LiveImageRegistrar()
        let transform = await registrar.register(reference: source, current: shifted)
        let point = try XCTUnwrap(transform?.apply(CGPoint(x: 0.5, y: 0.5)))
        XCTAssertEqual(point.x, 0.5 + 12 / size.width, accuracy: 0.025)
        XCTAssertEqual(point.y, 0.5 + 8 / size.height, accuracy: 0.025)
    }
}
