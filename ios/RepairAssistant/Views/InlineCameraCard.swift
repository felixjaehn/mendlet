import AVFoundation
import Photos
import SwiftUI

/// AVCaptureVideoPreviewLayer in SwiftUI; a tap reports the normalised device point for focus.
private struct CameraPreviewLayer: UIViewRepresentable {
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

/// Inline live camera on the home screen: preview, shutter, gallery and live-scan buttons.
/// Without a camera (simulator) it shows the demo photo and the shutter takes that photo, so the demo flow stays intact.
struct InlineCameraCard: View {
    var active: Bool
    var demoPhoto: UIImage?
    var lastThumb: UIImage?
    var onCapture: (UIImage) -> Void
    var onLiveScan: () -> Void
    var onGallery: () -> Void

    private enum Phase { case starting, running, denied, unavailable }
    @State private var camera = InlineCameraSession()
    @State private var phase = InlineCameraSession.hasCamera ? Phase.starting : Phase.unavailable
    @State private var flash = false
    @State private var capturing = false
    @State private var focusPoint: CGPoint?
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    private var simulated: Bool { !InlineCameraSession.hasCamera }

    @State private var hintVisible = true

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Color.clear.overlay { preview }.clipped().ignoresSafeArea()
            LinearGradient(colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea().allowsHitTesting(false)
            if let focusPoint {
                RoundedRectangle(cornerRadius: 10).strokeBorder(.yellow, lineWidth: 1.5).frame(width: 68, height: 68)
                    .position(focusPoint).transition(.scale(scale: 1.4).combined(with: .opacity)).allowsHitTesting(false)
            }
            Color.white.opacity(flash ? 0.85 : 0).ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 14) {
                Spacer()
                if hintVisible && phase != .denied {
                    Text("Point at the damage").font(.footnote.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.black.opacity(0.45), in: Capsule())
                        .transition(.opacity)
                }
                controls
            }
            .padding(.horizontal, 28).padding(.bottom, 18)
        }
        .task(id: active && scenePhase == .active) { await run(active && scenePhase == .active) }
        .task { try? await Task.sleep(for: .seconds(4)); withAnimation(.easeOut(duration: 0.6)) { hintVisible = false } }
        .onDisappear { camera.stop() }
    }

    @ViewBuilder private var preview: some View {
        switch phase {
        case .running:
            CameraPreviewLayer(session: camera.session) { device, view in
                camera.focus(at: device)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { focusPoint = view }
                Task { try? await Task.sleep(for: .seconds(1)); withAnimation { focusPoint = nil } }
            }
            .transition(.opacity)
        case .unavailable:
            if let demoPhoto { Image(uiImage: demoPhoto).resizable().scaledToFill().transition(.opacity) }
        case .denied:
            VStack(spacing: 12) {
                Image(systemName: "camera.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.7))
                Text("Camera access is off").font(.headline).foregroundStyle(.white)
                Text("Allow it in Settings, or pick a photo from your library.").font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
                Button("Open Settings") { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            }.padding(32)
        case .starting:
            ProgressView().tint(.white)
        }
    }

    private var controls: some View {
        HStack {
            Button(action: onGallery) {
                Group {
                    if let lastThumb {
                        Image(uiImage: lastThumb).resizable().scaledToFill()
                    } else {
                        Image(systemName: "photo.on.rectangle").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 48, height: 48).background(.black.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1.5))
            }
            .accessibilityLabel(tr("Fotos"))
            Spacer()
            Button(action: shutter) {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 76, height: 76)
                    Circle().fill(.white).frame(width: 62, height: 62).scaleEffect(capturing ? 0.86 : 1)
                }
            }
            .buttonStyle(.plain)
            .disabled(phase == .denied || phase == .starting)
            .opacity(phase == .denied ? 0.4 : 1)
            .accessibilityLabel(tr("Foto aufnehmen"))
            Spacer()
            Button(action: onLiveScan) {
                VStack(spacing: 3) {
                    Image(systemName: "dot.viewfinder").font(.system(size: 20, weight: .semibold))
                    Text("Live").font(.caption2.weight(.bold))
                }
                .foregroundStyle(.white).frame(width: 48, height: 48)
                .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(.white.opacity(0.3), lineWidth: 1))
            }
            .accessibilityLabel(tr("Schaden scannen"))
        }
    }

    private func shutter() {
        guard !capturing else { return }
        capturing = true
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.09)) { flash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.easeIn(duration: 0.25)) { flash = false }
            switch phase {
            case .running:
                if let img = try? await camera.capture() { Haptics.success(); onCapture(img) }
            case .unavailable:
                if let demoPhoto { Haptics.success(); onCapture(demoPhoto) }
            default: break
            }
            capturing = false
        }
    }

    private func run(_ on: Bool) async {
        guard on else { camera.stop(); return }
        if simulated { withAnimation { phase = .unavailable }; return }
        if InlineCameraSession.access == .notDetermined { _ = await InlineCameraSession.requestAccess() }
        guard InlineCameraSession.access == .authorized else { phase = .denied; return }
        do { try await camera.start(); withAnimation(.easeOut(duration: 0.3)) { phase = .running } }
        catch { phase = .unavailable }
    }
}
