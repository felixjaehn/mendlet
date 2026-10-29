import AVFoundation
import Photos
import SwiftUI

/// AVCaptureVideoPreviewLayer in SwiftUI; a tap reports the normalised device point for focus.
struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    var onTap: (CGPoint, CGPoint) -> Void  // (device point, view point)

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        v.addGestureRecognizer(UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap(_:))))
        context.coordinator.view = v
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) { context.coordinator.onTap = onTap }
    func makeCoordinator() -> Coordinator { Coordinator(onTap) }

    final class Coordinator: NSObject {
        var onTap: (CGPoint, CGPoint) -> Void
        weak var view: PreviewView?
        init(_ onTap: @escaping (CGPoint, CGPoint) -> Void) { self.onTap = onTap }
        @objc func tap(_ g: UITapGestureRecognizer) {
            guard let view else { return }
            let p = g.location(in: view)
            onTap(view.previewLayer.captureDevicePointConverted(fromLayerPoint: p), p)
        }
    }
}

/// Recent library photos for the strip under the camera. Reads the library only when access was already granted
/// (or the user taps "Allow"); the system picker needs no permission.
@MainActor @Observable
final class RecentPhotos {
    private(set) var images: [(id: String, image: UIImage)] = []
    private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    var canRead: Bool { status == .authorized || status == .limited }

    func load() async {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard canRead else { return }
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 12
        let assets = PHAsset.fetchAssets(with: .image, options: opts)
        var out: [(String, UIImage)] = []
        let manager = PHImageManager.default()
        let ro = PHImageRequestOptions(); ro.deliveryMode = .highQualityFormat; ro.isNetworkAccessAllowed = false; ro.isSynchronous = false
        for i in 0..<assets.count {
            let asset = assets[i]
            let img: UIImage? = await withCheckedContinuation { c in
                var done = false
                manager.requestImage(for: asset, targetSize: CGSize(width: 240, height: 240), contentMode: .aspectFill, options: ro) { image, info in
                    guard !done else { return }
                    if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                    done = true; c.resume(returning: image)
                }
            }
            if let img { out.append((asset.localIdentifier, img)) }
        }
        images = out
    }

    func requestAccess() async {
        _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await load()
    }

    /// Full-resolution image of a strip tile.
    static func full(id: String) async -> UIImage? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else { return nil }
        let ro = PHImageRequestOptions(); ro.deliveryMode = .highQualityFormat; ro.isNetworkAccessAllowed = true
        return await withCheckedContinuation { c in
            var done = false
            PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: 2048, height: 2048), contentMode: .aspectFit, options: ro) { image, info in
                guard !done else { return }
                if (info?[PHImageResultIsDegradedKey] as? Bool) == true { return }
                done = true; c.resume(returning: image)
            }
        }
    }
}
