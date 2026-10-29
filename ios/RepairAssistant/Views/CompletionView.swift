import SwiftUI
import PhotosUI

struct CompletionView: View {
    @Environment(FlowModel.self) private var flow
    @State private var check: CGFloat = 0
    @State private var ring: CGFloat = 0
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var gallery = false

    var body: some View {
        let est = flow.impact()
        let isShoe = flow.response?.category == .shoe
        ScrollView {
            VStack(spacing: 22) {
                checkmark.padding(.top, 8)
                VStack(spacing: 6) {
                    Text("Repariert!").font(.largeTitle.bold()).foregroundStyle(Theme.ink)
                    Text("Gut gemacht. Das Teil bleibt im Einsatz.").font(.body).foregroundStyle(Theme.inkSecondary)
                }
                BeforeAfterCard()
                impactCard(est, isShoe: isShoe)
                stats
                resultPhotoCard
            }
            .padding(.horizontal, Theme.margin).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText(est)) { Image(systemName: "square.and.arrow.up") }
                    .tint(.primary).accessibilityLabel(tr("Teilen"))
            }
        }
        .floatingBar {
            PrimaryButton(title: "Fertig", systemImage: "checkmark") { flow.reset() }
                .padding(.horizontal, Theme.margin).padding(.vertical, 10)
        }
        .fullScreenCover(isPresented: $showCamera) { CameraPicker { flow.resultPhoto = ImageResizer.resized($0) }.ignoresSafeArea() }
        .photosPicker(isPresented: $gallery, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { if let d = try? await item.loadTransferable(type: Data.self), let i = UIImage(data: d) { flow.resultPhoto = ImageResizer.resized(i) }; pickerItem = nil }
        }
        .onAppear {
            flow.loadAfterPreview()
            Haptics.success()
            withAnimation(.easeOut(duration: 0.7)) { ring = 1 }
            withAnimation(.easeOut(duration: 0.5).delay(0.55)) { check = 1 }
        }
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 76, weight: .regular))
            .symbolRenderingMode(.palette).foregroundStyle(.white, Theme.safe)
            .scaleEffect(0.6 + 0.4 * check).opacity(Double(check))
            .symbolEffect(.bounce, value: check)
            .accessibilityHidden(true)
    }

    private func impactCard(_ est: ImpactEstimator.Estimate, isShoe: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "leaf.fill").foregroundStyle(Theme.safe)
                Text("Dein Beitrag").font(.headline).foregroundStyle(Theme.inkSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("≈ \(ImpactEstimator.format(kg: est.kilograms)) kg")
                    .font(.system(size: 52, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            Text(isShoe ? tr("Schuhe vor Deponie oder Verbrennung bewahrt") : tr("Textil vor Deponie oder Verbrennung bewahrt"))
                .font(.headline).foregroundStyle(Theme.ink)
            Text(tr("Grobe Schätzung nach Durchschnittsgewicht (%@, ca.).", tr(est.garment))).font(.footnote).foregroundStyle(Theme.inkSecondary)
            Divider().overlay(Theme.hairline)
            fact(ImpactFacts.headline)
            fact(ImpactFacts.lifetime)
            fact(ImpactFacts.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 20)
    }

    private func fact(_ f: ImpactFacts.Fact) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(f.text).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Text(tr("Quelle: %@", f.source)).font(.caption2).foregroundStyle(Theme.inkSecondary)
        }
    }

    private var stats: some View {
        HStack(spacing: 10) {
            MetricTile(icon: "clock", title: "Zeit", value: elapsedText)
            MetricTile(icon: "eurosign.circle", title: "Kosten ca.", value: Fmt.euro(flow.response?.decision?.costEur ?? []))
            MetricTile(icon: "checkmark.seal", title: "gerettet", value: flow.response?.category == .shoe ? tr("1 Paar") : tr("1 Teil"))
        }
    }

    private var elapsedText: String {
        guard let s = flow.guideStartedAt else { return "–" }
        let m = max(1, Int(Date().timeIntervalSince(s) / 60))
        return tr("%lld Min.", m)
    }

    private var resultPhotoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Ergebnisfoto")
            if let after = flow.resultPhoto {
                HStack(spacing: 10) {
                    if let before = flow.photo { compare(before, tr("Vorher")) }
                    compare(after, tr("Nachher"))
                }
            } else {
                HStack(spacing: 10) {
                    if CameraPicker.isAvailable {
                        PrimaryButton(title: "Ergebnisfoto aufnehmen", systemImage: "camera.fill", kind: .secondary) { showCamera = true }
                    } else {
                        PrimaryButton(title: "Ergebnisfoto wählen", systemImage: "photo.on.rectangle", kind: .secondary) { gallery = true }
                    }
                }
            }
        }
    }

    private func compare(_ img: UIImage, _ label: String) -> some View {
        Image(uiImage: img).resizable().scaledToFill().frame(height: 150).frame(maxWidth: .infinity).clipped()
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text(label).font(.caption.weight(.bold)).foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.black.opacity(0.55), in: Capsule()).padding(8)
            }
    }

    private func shareText(_ est: ImpactEstimator.Estimate) -> String {
        tr("Ich habe gerade etwas repariert statt weggeworfen: ca. %@ kg vor Deponie oder Verbrennung bewahrt (Schätzung). #Reparieren", ImpactEstimator.format(kg: est.kilograms))
    }
}

struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX + r.width * 0.05, y: r.midY + r.height * 0.02))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY - r.height * 0.12))
        p.addLine(to: CGPoint(x: r.maxX - r.width * 0.02, y: r.minY + r.height * 0.1))
        return p
    }
}
