import UIKit

enum ImageResizer {
    static let maxEdge: CGFloat = 1536

    /// Returns the image scaled so its longest edge is at most `maxEdge` (orientation normalized).
    static func resized(_ image: UIImage, maxEdge: CGFloat = ImageResizer.maxEdge) -> UIImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    static func jpegData(_ image: UIImage, maxEdge: CGFloat = ImageResizer.maxEdge, quality: CGFloat = 0.8) -> Data? {
        resized(image, maxEdge: maxEdge).jpegData(compressionQuality: quality)
    }

    static func base64(_ image: UIImage) -> String {
        (jpegData(image) ?? Data()).base64EncodedString()
    }
}
