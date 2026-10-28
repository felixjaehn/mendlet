import SwiftUI
import PhotosUI

struct HomeView: View {
    @Environment(FlowModel.self) private var flow
    @State private var showLiveScan = false
    @State private var liveCapture: (UIImage, DemoScenario?)?
    @State private var showCamera = false
    @State private var showGallery = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        @Bindable var flow = flow
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                topBar
                headline
                ThreadHero().frame(height: 132)
                VStack(spacing: 12) {
                    PrimaryButton(title: "Live-Scan", systemImage: "viewfinder") { showLiveScan = true }
                    PrimaryButton(title: "Foto aufnehmen", systemImage: "camera.fill") {
                        if CameraPicker.isAvailable { showCamera = true } else { showGallery = true }
                    }
                    PrimaryButton(title: "Aus Galerie", systemImage: "photo.on.rectangle", kind: .secondary) { showGallery = true }
                }
                HStack(spacing: 8) {
                    Chip(title: "Kleidung", systemImage: "tshirt", tint: Theme.inkSecondary, isOn: true)
                    Chip(title: "Schuhe", systemImage: "shoe", tint: Theme.inkSecondary, isOn: true)
                    Spacer()
                }
                if flow.store.rescuedCount >= 1 { balanceRow }
                if flow.settings.demoMode { demoSection }
                if !flow.store.cases.isEmpty { historySection }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarHidden(true)
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { flow.choose($0) }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showLiveScan, onDismiss: {
            if let (photo, scenario) = liveCapture {
                liveCapture = nil
                flow.choose(photo, scenarioHint: scenario)
            }
        }) {
            LiveScanView(settings: flow.settings) { photo, scenario in
                liveCapture = (photo, scenario)
                showLiveScan = false
            }
        }
        .photosPicker(isPresented: $showGallery, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { flow.choose(img) }
                pickerItem = nil
            }
        }
        .sheet(isPresented: $flow.showReview) { ReviewSheet() }
    }

    private var topBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .font(.system(size: 17, weight: .bold)).foregroundStyle(Theme.thread)
                Text("Reparatur-Assistent").font(.headline).foregroundStyle(Theme.ink)
            }
            .onLongPressGesture(minimumDuration: 0.8) { Haptics.success(); flow.showSettings = true }
            Spacer()
            if flow.settings.demoMode {
                Badge(text: "Demo", tint: Theme.caution)
            }
            Button { flow.showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 18, weight: .medium)).foregroundStyle(Theme.inkSecondary)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Einstellungen")
        }
        .padding(.top, 4)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Was ist kaputt?\nZeig's mir.")
                .font(.largeTitle.bold()).foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Foto machen, Schaden markieren lassen und Schritt für Schritt reparieren.")
                .font(.body).foregroundStyle(Theme.inkSecondary)
        }
    }

    private var balanceRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "leaf.fill").foregroundStyle(Theme.safe)
            VStack(alignment: .leading, spacing: 1) {
                Text("Deine Bilanz").font(.caption).foregroundStyle(Theme.inkSecondary)
                Text("\(flow.store.rescuedCount) \(flow.store.rescuedCount == 1 ? "Teil" : "Teile") gerettet · ≈ \(ImpactEstimator.format(kg: flow.store.rescuedKilograms)) kg")
                    .font(.rounded(.subheadline, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.safeSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var demoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Demo-Szenarien")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(DemoScenario.allCases) { s in ScenarioCard(scenario: s) }
                }
                .padding(.horizontal, Theme.margin)
            }
            .padding(.horizontal, -Theme.margin)
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Zuletzt analysiert")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(flow.store.cases.prefix(8)) { c in HistoryCard(item: c) }
                }
                .padding(.horizontal, Theme.margin)
            }
            .padding(.horizontal, -Theme.margin)
        }
    }
}

private struct ScenarioCard: View {
    @Environment(FlowModel.self) private var flow
    let scenario: DemoScenario
    @State private var image: UIImage?

    var body: some View {
        Button {
            Task {
                let img = await DemoImageFactory.imageAsync(for: scenario)
                flow.choose(img, scenarioHint: scenario, note: scenario.userNote)
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    if let image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else {
                        Theme.hairline.overlay(Image(systemName: scenario.systemImage).foregroundStyle(Theme.inkSecondary))
                    }
                }
                .frame(width: 132, height: 120).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(scenario.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(scenario.subtitle).font(.caption).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                }
            }
            .frame(width: 132)
        }
        .buttonStyle(.plain)
        .task {
            image = await DemoImageFactory.imageAsync(for: scenario)
        }
    }
}

private struct HistoryCard: View {
    @Environment(FlowModel.self) private var flow
    let item: SavedCase
    var body: some View {
        Button { flow.open(item) } label: {
            VStack(alignment: .leading, spacing: 8) {
                Group {
                    if let img = flow.store.image(for: item.id) {
                        Image(uiImage: img).resizable().scaledToFill()
                    } else { Theme.hairline }
                }
                .frame(width: 132, height: 96).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(item.response.diagnosis.summary.isEmpty ? "Analyse" : item.response.diagnosis.summary)
                    .font(.caption.weight(.medium)).foregroundStyle(Theme.ink).lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: 132)
        }
        .buttonStyle(.plain)
    }
}

/// Self-made hero: a tear that closes with thread, looping.
private struct ThreadHero: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { tl in
            let t = reduceMotion ? 3.0 : tl.date.timeIntervalSince(start)
            Canvas { ctx, size in
                let cycle = 5.5
                let local = t.truncatingRemainder(dividingBy: cycle)
                let p = min(1, local / 3.6)
                let alpha = local > cycle - 0.4 ? max(0, (cycle - local) / 0.4) : 1
                let mid = size.height / 2
                let x0 = 28.0, x1 = size.width - 28
                // slit
                var slit = Path()
                let n = 40
                for i in 0...n {
                    let u = Double(i) / Double(n), x = x0 + (x1 - x0) * u
                    let w = 9 * pow(sin(.pi * u), 0.7) + 1.5
                    let y = mid + 6 * sin(u * 6)
                    if i == 0 { slit.move(to: CGPoint(x: x, y: y - w)) } else { slit.addLine(to: CGPoint(x: x, y: y - w)) }
                }
                for i in stride(from: n, through: 0, by: -1) {
                    let u = Double(i) / Double(n), x = x0 + (x1 - x0) * u
                    let w = 9 * pow(sin(.pi * u), 0.7) + 1.5
                    slit.addLine(to: CGPoint(x: x, y: mid + 6 * sin(u * 6) + w))
                }
                slit.closeSubpath()
                ctx.fill(slit, with: .color(Theme.ink.opacity(0.78)))
                // stitches
                let count = 9
                ctx.opacity = alpha
                var thread = Path()
                var head = CGPoint(x: x0, y: mid)
                for i in 0..<count {
                    let u = (Double(i) + 0.5) / Double(count)
                    let x = x0 + (x1 - x0) * u
                    let y = mid + 6 * sin(u * 6) + (i % 2 == 0 ? -20 : 20)
                    let pt = CGPoint(x: x, y: y)
                    let frac = Double(i) / Double(count)
                    guard p >= frac else { break }
                    if i == 0 { thread.move(to: pt) } else { thread.addLine(to: pt) }
                    head = pt
                    let s = min(1, (p - frac) * Double(count) * 2)
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 5 * s, y: y - 5 * s, width: 10 * s, height: 10 * s)), with: .color(i % 2 == 0 ? Theme.thread : Theme.card))
                    ctx.stroke(Path(ellipseIn: CGRect(x: x - 5 * s, y: y - 5 * s, width: 10 * s, height: 10 * s)), with: .color(Theme.thread), lineWidth: 2)
                }
                ctx.stroke(thread, with: .color(Theme.thread), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                _ = head
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.threadSoft, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .onAppear { start = Date() }
        .accessibilityHidden(true)
    }
}
