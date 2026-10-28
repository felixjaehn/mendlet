import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class LiveCameraFeed {
    private(set) var session: AVCaptureSession?
    private(set) var preview: CGImage?
    private(set) var imageSize = CGSize(width: 3, height: 4)
    private(set) var error: String?
    private(set) var isSynthetic = false
    @ObservationIgnored private var source: (any LiveFrameSource)?
    @ObservationIgnored private var generation = UUID()

    static func usesSyntheticFrames(demoMode: Bool) -> Bool {
        #if targetEnvironment(simulator)
        true
        #else
        demoMode
        #endif
    }

    func run(demoMode: Bool, demoPhoto: CGImage, reduceMotion: Bool,
             consume: @escaping @MainActor (LiveFrame) async -> Void) async {
        let token = UUID(); generation = token
        error = nil; preview = nil
        isSynthetic = Self.usesSyntheticFrames(demoMode: demoMode)
        let camera: any LiveFrameSource
        if isSynthetic {
            camera = LiveDemoCamera(image: demoPhoto, reduceMotion: reduceMotion)
            session = nil
        } else {
            let live = LiveCamera(); camera = live; session = live.session
        }
        source = camera
        do {
            let frames = try await camera.start()
            try Task.checkCancellation()
            for try await frame in frames {
                guard !Task.isCancelled, generation == token else { break }
                imageSize = CGSize(width: frame.image.width, height: frame.image.height)
                if isSynthetic { preview = frame.image }
                await consume(frame)
            }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled, generation == token { self.error = error.localizedDescription }
        }
        await camera.stop()
        if generation == token { source = nil; session = nil }
    }

    func capturePhoto() async throws -> UIImage {
        guard let source else { throw LiveCameraError.capture }
        return try await source.capturePhoto()
    }
}
