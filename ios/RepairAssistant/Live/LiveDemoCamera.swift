import UIKit

/// Uses the real demo photo pixels, so Vision registration is exercised in the simulator too.
actor LiveDemoCamera: LiveFrameSource {
    let image: CGImage
    let reduceMotion: Bool
    private var task: Task<Void, Never>?
    private var continuation: AsyncThrowingStream<LiveFrame, Error>.Continuation?
    private var elapsed: TimeInterval = 0

    init(image: CGImage, reduceMotion: Bool) { self.image = image; self.reduceMotion = reduceMotion }

    func start() -> AsyncThrowingStream<LiveFrame, Error> {
        let (stream, sink) = AsyncThrowingStream<LiveFrame, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = sink
        task = Task { [weak self] in
            let start = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                await self.emit(at: now, elapsed: now - start)
                do { try await Task.sleep(for: .milliseconds(33)) } catch { return }
            }
        }
        return stream
    }

    private func emit(at time: TimeInterval, elapsed: TimeInterval) {
        self.elapsed = elapsed
        if let frame = render(longestSide: 768) { continuation?.yield(LiveFrame(image: frame, timestamp: time)) }
    }

    func capturePhoto() throws -> UIImage {
        guard let frame = render(longestSide: max(image.width, image.height)) else { throw LiveCameraError.capture }
        return UIImage(cgImage: frame)
    }

    func stop() {
        task?.cancel(); task = nil
        continuation?.finish(); continuation = nil
    }

    private func render(longestSide: Int) -> CGImage? {
        let scale = Double(longestSide) / Double(max(image.width, image.height))
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let zoom = reduceMotion ? 1 : 1.035 + 0.008 * sin(elapsed * 0.3)
        let x = (1 - zoom) / 2 + (reduceMotion ? 0 : 0.006 * sin(elapsed * 0.45))
        let y = (1 - zoom) / 2 + (reduceMotion ? 0 : 0.004 * cos(elapsed * 0.4))
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: x * Double(width), y: (1 - zoom - y) * Double(height), width: Double(width) * zoom, height: Double(height) * zoom))
        return context.makeImage()
    }
}
