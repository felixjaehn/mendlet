import AVFoundation
import Observation
import UIKit

/// Lightweight capture session for the inline camera on the home screen (preview + still photo, no frame analysis).
/// All AVFoundation work runs on `queue`; delegate callbacks come back on it as well.
final class InlineCameraSession: NSObject, @unchecked Sendable, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "repair.inline.camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private var configured = false
    private var pending: CheckedContinuation<UIImage, Error>?

    enum Access { case authorized, notDetermined, denied }
    static var access: Access {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: .authorized
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
    /// A real back camera exists (false in the simulator).
    static var hasCamera: Bool { AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil }

    static func requestAccess() async -> Bool { await AVCaptureDevice.requestAccess(for: .video) }

    func start() async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            queue.async { [self] in
                do {
                    if !configured { try configure(); configured = true }
                    if !session.isRunning { session.startRunning() }
                    c.resume()
                } catch { c.resume(throwing: error) }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            if session.isRunning { session.stopRunning() }
            pending?.resume(throwing: CancellationError()); pending = nil
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else { throw LiveCameraError.unavailable }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw LiveCameraError.unavailable }
        session.addInput(input); session.addOutput(output)
        output.maxPhotoQualityPrioritization = .quality
        if let c = output.connection(with: .video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        try device.lockForConfiguration()
        if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
        device.unlockForConfiguration()
    }

    /// Tap-to-focus at a normalised preview point (device coordinates).
    func focus(at point: CGPoint) {
        queue.async { [self] in
            guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device,
                  (try? device.lockForConfiguration()) != nil else { return }
            if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = point; device.focusMode = .autoFocus }
            if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = point; device.exposureMode = .autoExpose }
            device.unlockForConfiguration()
        }
    }

    func capture() async throws -> UIImage {
        try await withCheckedThrowingContinuation { c in
            queue.async { [self] in
                guard session.isRunning, pending == nil else { c.resume(throwing: LiveCameraError.capture); return }
                pending = c
                output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let result: Result<UIImage, Error>
        if let error { result = .failure(error) }
        else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data), let cg = LiveImage.upright(image) {
            result = .success(UIImage(cgImage: cg))
        } else { result = .failure(LiveCameraError.capture) }
        queue.async { [self] in pending?.resume(with: result); pending = nil }
    }
}
