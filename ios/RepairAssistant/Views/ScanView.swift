import AVFoundation
import PhotosUI
import SwiftUI

/// Scan: camera first. Four arc corners, a hint, a Photo | Live pill, gallery - shutter - note (BitePal / Cal AI / Greg).
/// Without a camera (simulator) the preview is a demo photo and the gallery is a plain photo grid.
struct ScanView: View {
    var demoPhoto: UIImage?
    var onClose: () -> Void
    var onCapture: (UIImage, DemoScenario?) -> Void
    var onPick: (UIImage) -> Void

    private enum Phase { case starting, running, notDetermined, denied, unavailable }
    @Environment(FlowModel.self) private var flow
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera = InlineCameraSession()
    @State private var phase: Phase = InlineCameraSession.hasCamera ? .starting : .unavailable
    @State private var recents = RecentPhotos()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showGallery = false
    @State private var showGrid = false
    @State private var showNote = false
    @State private var torch = false
    @State private var flash = false
    @State private var frozen: UIImage?
    @State private var capturing = false
    @State private var breathe = false
    @State private var focusPoint: CGPoint?
    @State private var showLive = false
    @State private var liveCapture: (UIImage, DemoScenario?)?

    private var simulated: Bool { !InlineCameraSession.hasCamera }

    var body: some View {
        GeometryReader { geo in
            let frame = min(288, geo.size.width - 72)
            ZStack {
                Color.black.ignoresSafeArea()
                preview.frame(maxWidth: .infinity, maxHeight: .infinity).clipped().ignoresSafeArea()
                if let frozen { Image(uiImage: frozen).resizable().scaledToFill().frame(maxWidth: .infinity, maxHeight: .infinity).clipped().ignoresSafeArea().transition(.opacity) }
                LinearGradient(colors: [.black.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom).frame(height: 140).frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea().allowsHitTesting(false)
                LinearGradient(colors: [.clear, .black.opacity(0.4)], startPoint: .top, endPoint: .bottom).frame(height: 220).frame(maxHeight: .infinity, alignment: .bottom).ignoresSafeArea().allowsHitTesting(false)

                if phase == .running || phase == .unavailable || phase == .starting {
                    // viewfinder corners and hint
                    let size = capturing ? CGSize(width: geo.size.width + 40, height: geo.size.height + 80) : CGSize(width: frame, height: frame)
                    ViewfinderCorners(radius: capturing ? 0 : 28, arm: capturing ? 0 : 36)
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .shadow(color: .black.opacity(0.25), radius: 2)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(breathe ? 1.015 : 1)
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.44)
                        .allowsHitTesting(false)
                    Text("Fill the frame with the damage").font(.footnote.weight(.medium)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule()).background(Color.black.opacity(0.35), in: Capsule())
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.44 + frame / 2 + 30)
                        .opacity(capturing ? 0 : 1)
                }
                if let focusPoint {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(.white, lineWidth: 1.5).frame(width: 68, height: 68)
                        .position(focusPoint).transition(.scale(scale: 1.3).combined(with: .opacity)).allowsHitTesting(false)
                }
                Color.white.opacity(flash ? 0.35 : 0).ignoresSafeArea().allowsHitTesting(false)

                if phase == .notDetermined || phase == .denied { permission }
                chrome(geo: geo).opacity(capturing ? 0 : 1)
            }
        }
        .statusBarHidden(false)
        .preferredColorScheme(.dark)
        .task(id: scenePhase == .active && !showGrid) { await run(scenePhase == .active && !showGrid) }
        .task { await recents.load() }
        .onAppear { if !reduceMotion { withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { breathe = true } } }
        .onDisappear { camera.stop() }
        .photosPicker(isPresented: $showGallery, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { onPick(img) }
                pickerItem = nil
            }
        }
        .fullScreenCover(isPresented: $showLive, onDismiss: {
            if let (photo, scenario) = liveCapture { liveCapture = nil; onCapture(photo, scenario) }
        }) {
            LiveScanView(settings: flow.settings) { photo, scenario in liveCapture = (photo, scenario); showLive = false }
        }
        .sheet(isPresented: $showGrid) { PhotoGridSheet { showGrid = false } }
        .sheet(isPresented: $showNote) { NoteSheet().presentationDetents([.medium]).presentationDragIndicator(.visible) }
    }

    // MARK: Preview

    @ViewBuilder private var preview: some View {
        switch phase {
        case .running:
            CameraPreviewLayer(session: camera.session) { device, view in
                camera.focus(at: device)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { focusPoint = view }
                Task { try? await Task.sleep(for: .seconds(1)); withAnimation { focusPoint = nil } }
            }
        case .unavailable:
            if let demoPhoto { Image(uiImage: demoPhoto).resizable().scaledToFill() } else { Color.black }
        default:
            Color.black
        }
    }

    // MARK: Controls

    private func chrome(geo: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            HStack {
                CircleIconButton(systemImage: "xmark", label: "Close", onPhoto: true) { onClose() }
                Spacer()
                CircleIconButton(systemImage: torch ? "bolt.fill" : "bolt.slash", label: torch ? "Turn the light off" : "Turn the light on", onPhoto: true) {
                    torch.toggle(); camera.setTorch(torch)
                }
            }
            .padding(.horizontal, Theme.margin).padding(.top, 8)
            Spacer()
            ModePill(onLive: { showLive = true }).padding(.bottom, 16)
            HStack {
                Button { if simulated { showGrid = true } else { showGallery = true } } label: {
                    Group {
                        if let t = recents.images.first?.image ?? demoPhoto { Image(uiImage: t).resizable().scaledToFill() }
                        else { Image(systemName: "photo.on.rectangle").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white) }
                    }
                    .frame(width: 52, height: 52).background(Color.white.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.thumbRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Theme.thumbRadius, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Choose a photo"))
                Spacer()
                Button(action: shutter) {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 3).frame(width: 88, height: 88)
                        Circle().fill(.white).frame(width: 76, height: 76)
                    }
                    .contentShape(Circle())
                }
                .buttonStyle(ShutterStyle())
                .disabled(phase == .denied || phase == .notDetermined || phase == .starting)
                .accessibilityLabel(tr("Take photo"))
                Spacer()
                Button { showNote = true } label: {
                    Image(systemName: "text.bubble").font(.system(size: 20, weight: .medium)).foregroundStyle(.white)
                        .frame(width: 52, height: 52).glass(Circle(), interactive: true)
                        .overlay(alignment: .topTrailing) { if !flow.note.isEmpty { Circle().fill(.white).frame(width: 10, height: 10).offset(x: -2, y: 2) } }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tr("Add a note"))
            }
            .padding(.horizontal, 28).padding(.bottom, 20)
        }
    }

    private var permission: some View {
        VStack(spacing: 12) {
            Text(phase == .denied ? "Camera access is off" : "Mendlet needs the camera").font(.title3.weight(.semibold)).foregroundStyle(.white)
            Text(phase == .denied ? "Turn it on in Settings, or pick a photo instead." : "To photograph what you want to repair.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center)
            Button {
                if phase == .denied { if let u = URL(string: UIApplication.openSettingsURLString) { openURL(u) } }
                else { Task { _ = await InlineCameraSession.requestAccess(); await run(true) } }
            } label: {
                Text(phase == .denied ? "Open Settings" : "Continue").font(.headline).foregroundStyle(.black)
                    .padding(.horizontal, 28).frame(height: 50).background(.white, in: Capsule())
            }
            .padding(.top, 8)
            if phase == .denied { Button("Choose a photo") { showGallery = true }.font(.body.weight(.medium)).foregroundStyle(.white).frame(minHeight: 44) }
        }
        .padding(32)
    }

    // MARK: Actions

    private func shutter() {
        guard !capturing else { return }
        capturing = true
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.06)) { flash = true }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            withAnimation(.easeIn(duration: 0.2)) { flash = false }
            var image: UIImage?
            switch phase {
            case .running: image = try? await camera.capture()
            case .unavailable: image = demoPhoto
            default: break
            }
            guard let image else { capturing = false; return }
            withAnimation(.easeInOut(duration: 0.35)) { frozen = image }
            Haptics.success()
            try? await Task.sleep(for: .milliseconds(420))
            onCapture(image, nil)
            try? await Task.sleep(for: .milliseconds(600))
            frozen = nil; capturing = false
        }
    }

    private func run(_ on: Bool) async {
        guard on else { camera.stop(); return }
        if simulated { phase = .unavailable; return }
        switch InlineCameraSession.access {
        case .notDetermined: phase = .notDetermined; return
        case .denied: phase = .denied; return
        case .authorized: break
        }
        do { try await camera.start(); withAnimation(.easeOut(duration: 0.3)) { phase = .running } }
        catch { phase = .unavailable }
    }
}

private struct ShutterStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1).animation(Theme.press, value: configuration.isPressed)
    }
}

/// "Photo | Live": two-segment glass pill, the selected segment white (Cal AI).
private struct ModePill: View {
    var onLive: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            Text("Photo").font(.subheadline.weight(.semibold)).foregroundStyle(.black)
                .padding(.horizontal, 18).frame(height: 36).background(Color.white.opacity(0.92), in: Capsule())
            Button(action: onLive) {
                Text("Live").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 36).contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(2)
        .glass(Capsule(), tint: Color.black.opacity(0.2))
    }
}

struct NoteSheet: View {
    @Environment(FlowModel.self) private var flow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var flow = flow
        VStack(alignment: .leading, spacing: 16) {
            Text("What's wrong?").font(.serif(.title2)).foregroundStyle(Theme.ink).padding(.top, 28)
            VoiceTextField(placeholder: "Optional, e.g. the sole came off yesterday", text: $flow.note)
            Spacer(minLength: 0)
            PrimaryButton(title: "Save note") { dismiss() }
        }
        .padding(.horizontal, Theme.margin).padding(.bottom, 12)
        .screenBackground()
    }
}
