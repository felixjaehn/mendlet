import SwiftUI
import AVFoundation

struct LiveScanView: View {
    let settings: AppSettings
    let onCapture: (UIImage, DemoScenario?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = LiveScanModel()

    var body: some View {
        ZStack {
            LiveCameraSurface(feed: model.feed)
            LiveScanOverlay(model: model)
        }
        .ignoresSafeArea()
        .safeAreaInset(edge: .top) {
            LiveCameraHeader(title: "Live-Scan", synthetic: model.feed.isSynthetic, latency: model.latencyMilliseconds) { dismiss() }
        }
        .safeAreaInset(edge: .bottom) { controls }
        .task(id: "\(model.category.id)-\(scenePhase)-\(reduceMotion)") {
            guard scenePhase == .active else { return }
            await model.run(settings: settings, reduceMotion: reduceMotion)
        }
        .onChange(of: model.state) { _, state in
            if state == .captured, let photo = model.capturedPhoto {
                onCapture(photo, settings.demoMode ? model.captureScenario : nil)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Text(status).font(.headline).multilineTextAlignment(.center)
                .accessibilityAddTraits(.updatesFrequently)
            if let error = model.feed.error ?? model.detectionError {
                Text(error).font(.footnote).multilineTextAlignment(.center).foregroundStyle(Theme.caution)
                if model.feed.error != nil {
                    Button("Einstellungen öffnen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }.font(.subheadline.weight(.semibold))
                }
            } else {
                Text("Die Aufnahme startet automatisch, sobald die Markierung ruhig bleibt.")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                ForEach(LiveCategory.allCases) { category in
                    Button { model.category = category; Haptics.selection() } label: {
                        Label(category.rawValue, systemImage: category.symbol)
                            .font(.caption.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 44)
                            .background(model.category == category ? Theme.threadSoft : Theme.card, in: Capsule())
                            .overlay(Capsule().strokeBorder(model.category == category ? Theme.thread : Theme.hairline, lineWidth: 1))
                    }
                    .accessibilityAddTraits(model.category == category ? .isSelected : [])
                }
            }
            .disabled(model.state == .stable || model.state == .captured)
        }
        .foregroundStyle(Theme.ink).padding(Theme.margin).frame(maxWidth: .infinity)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
    }

    private var status: String {
        switch model.state {
        case .searching: "Suche Schaden…"
        case .detected: model.category == .clothing ? "Riss erkannt – halt still" : "Schaden erkannt – halt still"
        case .stable: "Still halten · Foto wird aufgenommen…"
        case .captured: "Foto aufgenommen"
        }
    }
}

struct LiveCameraHeader: View {
    let title: String
    let synthetic: Bool
    var latency: Int? = nil
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title2.bold())
                HStack(spacing: 6) {
                    Text("SAM 3.1 · live")
                    if let latency { Text("\(latency) ms").monospacedDigit() }
                    if synthetic { Text("Demo").foregroundStyle(Theme.caution) }
                }
                .font(.caption.weight(.semibold)).padding(.horizontal, 10).padding(.vertical, 6)
                .background(.black.opacity(0.5), in: Capsule())
            }
            Spacer()
            Button(action: close) {
                Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                    .background(.black.opacity(0.5), in: Circle())
            }.accessibilityLabel("Schließen")
        }
        .foregroundStyle(.white).padding(Theme.margin)
    }
}

private struct LiveScanOverlay: View {
    let model: LiveScanModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let rect = LiveGeometry.aspectFill(image: model.feed.imageSize, viewport: size)
                if let first = model.polygon.first {
                    func point(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX + p.x * rect.width, y: rect.minY + p.y * rect.height) }
                    var path = Path(); path.move(to: point(first))
                    model.polygon.dropFirst().forEach { path.addLine(to: point($0)) }; path.closeSubpath()
                    context.fill(path, with: .color(Theme.thread.opacity(0.2)))
                    context.stroke(path, with: .color(Theme.thread), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                }
                let pulse = reduceMotion ? 0 : sin(timeline.date.timeIntervalSinceReferenceDate * 2) * 3
                let width = size.width * 0.76 + pulse, height = min(size.height * 0.32, width)
                let box = CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
                var brackets = Path()
                for (x, y, dx, dy) in [(box.minX, box.minY, 1.0, 1.0), (box.maxX, box.minY, -1.0, 1.0),
                                       (box.minX, box.maxY, 1.0, -1.0), (box.maxX, box.maxY, -1.0, -1.0)] {
                    brackets.move(to: CGPoint(x: x, y: y + dy * 24)); brackets.addLine(to: CGPoint(x: x, y: y))
                    brackets.addLine(to: CGPoint(x: x + dx * 24, y: y))
                }
                context.stroke(brackets, with: .color(model.state == .searching ? .white : Theme.thread), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct LiveCameraSurface: View {
    let feed: LiveCameraFeed
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let session = feed.session { LiveSessionPreview(session: session) }
                else if let image = feed.preview {
                    Image(decorative: image, scale: 1).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LiveSessionPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        }
    }
    func makeUIView(context: Context) -> Preview {
        let view = Preview(); view.preview.videoGravity = .resizeAspectFill; view.preview.session = session
        return view
    }
    func updateUIView(_ view: Preview, context: Context) {
        if view.preview.session !== session { view.preview.session = session }
    }
    static func dismantleUIView(_ view: Preview, coordinator: ()) { view.preview.session = nil }
}
