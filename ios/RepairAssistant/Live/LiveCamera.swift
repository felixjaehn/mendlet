import AVFoundation
import CoreImage
import UIKit

struct LiveFrame: Sendable {
    let image: CGImage
    let timestamp: TimeInterval
}

protocol LiveFrameSource: Sendable {
    func start() async throws -> AsyncThrowingStream<LiveFrame, Error>
    func capturePhoto() async throws -> UIImage
    func stop() async
}

enum LiveCameraError: LocalizedError {
    case denied, unavailable, capture, interrupted
    var errorDescription: String? {
        switch self {
        case .denied: "Bitte erlaube den Kamerazugriff in den Einstellungen."
        case .unavailable: "Die Kamera ist gerade nicht verfügbar."
        case .capture: "Das Foto konnte nicht aufgenommen werden. Bitte versuche es erneut."
        case .interrupted: "Die Kamera wurde unterbrochen. Bitte starte den Live-Scan erneut."
        }
    }
}

/// All mutable capture state is confined to queue, including delegate callbacks.
final class LiveCamera: NSObject, LiveFrameSource, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "repair.live.camera", qos: .userInitiated)
    private let photos = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var frames: AsyncThrowingStream<LiveFrame, Error>.Continuation?
    private var photoContinuation: CheckedContinuation<UIImage, Error>?
    private var observers: [NSObjectProtocol] = []

    func start() async throws -> AsyncThrowingStream<LiveFrame, Error> {
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard allowed else { throw LiveCameraError.denied }
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                do {
                    try configure()
                    let (stream, sink) = AsyncThrowingStream<LiveFrame, Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
                    frames = sink
                    for name in [AVCaptureSession.wasInterruptedNotification, AVCaptureSession.runtimeErrorNotification] {
                        observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                            guard let self else { return }
                            self.queue.async { self.frames?.finish(throwing: LiveCameraError.interrupted) }
                        })
                    }
                    session.startRunning()
                    continuation.resume(returning: stream)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw LiveCameraError.unavailable }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(video), session.canAddOutput(photos) else { throw LiveCameraError.unavailable }
        session.addInput(input); session.addOutput(video); session.addOutput(photos)
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        video.setSampleBufferDelegate(self, queue: queue)
        for output in [video as AVCaptureOutput, photos as AVCaptureOutput] {
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
        if let dimensions = device.activeFormat.supportedMaxPhotoDimensions.max(by: { Int64($0.width) * Int64($0.height) < Int64($1.width) * Int64($1.height) }) {
            photos.maxPhotoDimensions = dimensions
        }
        photos.maxPhotoQualityPrioritization = .quality
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        if device.activeFormat.videoSupportedFrameRateRanges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
            device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        }
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
    }

    func capturePhoto() async throws -> UIImage {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard session.isRunning, photoContinuation == nil else { continuation.resume(throwing: LiveCameraError.capture); return }
                    photoContinuation = continuation
                    let settings = AVCapturePhotoSettings()
                    settings.maxPhotoDimensions = photos.maxPhotoDimensions
                    settings.photoQualityPrioritization = .quality
                    photos.capturePhoto(with: settings, delegate: self)
                }
            }
        } onCancel: {
            self.queue.async { self.finishPhoto(.failure(CancellationError())) }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                frames?.finish(); frames = nil
                finishPhoto(.failure(CancellationError()))
                observers.forEach(NotificationCenter.default.removeObserver); observers = []
                if session.isRunning { session.stopRunning() }
                continuation.resume()
            }
        }
    }

    private func finishPhoto(_ result: Result<UIImage, Error>) {
        photoContinuation?.resume(with: result); photoContinuation = nil
    }
}

extension LiveCamera: AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let input = CIImage(cvPixelBuffer: pixelBuffer)
        let scale = min(1, 768 / max(input.extent.width, input.extent.height))
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let image = context.createCGImage(small, from: small.extent) else { return }
        frames?.yield(LiveFrame(image: image, timestamp: ProcessInfo.processInfo.systemUptime))
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        // AVCapturePhoto is consumed on the delegate thread; only the immutable result crosses queues.
        let result: Result<UIImage, Error>
        if let error { result = .failure(error) }
        else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data), let cg = LiveImage.upright(image) {
            result = .success(UIImage(cgImage: cg))
        } else { result = .failure(LiveCameraError.capture) }
        queue.async { self.finishPhoto(result) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error { queue.async { self.finishPhoto(.failure(error)) } }
    }
}
