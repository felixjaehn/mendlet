import CoreGraphics
import Vision
import simd
import UIKit

/// Vision work is actor-isolated, away from MainActor. Callers consume only the newest frame.
actor LiveImageRegistrar {
    private var cachedReference: CGImage?
    private var cachedSize = CGSize.zero
    private var preparedReference: CGImage?

    func register(reference: CGImage, current: CGImage) -> LiveHomography? {
        let target = LiveImage.scaled(current, longestSide: 384)
        let size = CGSize(width: target.width, height: target.height)
        if cachedReference !== reference || cachedSize != size {
            cachedReference = reference; cachedSize = size
            preparedReference = LiveImage.resized(reference, size: size)
        }
        guard let source = preparedReference, !Task.isCancelled else { return nil }
        // The targeted (floating) image is the detection/photo; the handler's reference is live.
        let handler = VNImageRequestHandler(cgImage: target, orientation: .up)
        let request = VNHomographicImageRegistrationRequest(targetedCGImage: source, orientation: .up)
        if (try? handler.perform([request])) != nil, let observation = request.results?.first, observation.confidence > 0.1 {
            let h = LiveHomography.vision(observation.warpTransform, size: size)
            if h.isPlausible { return h }
        }
        guard !Task.isCancelled else { return nil }
        let fallback = VNTranslationalImageRegistrationRequest(targetedCGImage: source, orientation: .up)
        guard (try? handler.perform([fallback])) != nil, let result = fallback.results?.first, result.confidence > 0.1 else { return nil }
        let t = result.alignmentTransform
        let matrix = simd_float3x3(rows: [SIMD3(Float(t.a), Float(t.c), Float(t.tx)),
                                        SIMD3(Float(t.b), Float(t.d), Float(t.ty)), SIMD3(0, 0, 1)])
        let h = LiveHomography.vision(matrix, size: size)
        return h.isPlausible ? h : nil
    }
}

enum LiveImage {
    static func scaled(_ image: CGImage, longestSide: Int) -> CGImage {
        let scale = min(1, Double(longestSide) / Double(max(image.width, image.height)))
        return resized(image, size: CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)) ?? image
    }

    static func resized(_ image: CGImage, size: CGSize) -> CGImage? {
        guard let context = CGContext(data: nil, width: max(1, Int(size.width.rounded())), height: max(1, Int(size.height.rounded())),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        return context.makeImage()
    }

    static func upright(_ image: UIImage) -> CGImage? {
        if image.imageOrientation == .up, let cg = image.cgImage { return cg }
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale), format: format)
            .image { context in image.draw(in: context.format.bounds) }.cgImage
    }
}
