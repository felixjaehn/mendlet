import SwiftUI
import PhotosUI

/// Quiet payoff: the user's own before/after, one sentence, done.
struct CompletionView: View {
    @Environment(FlowModel.self) private var flow
    @State private var showCamera = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var gallery = false

    var body: some View {
        let est = flow.impact()
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    CircleIconButton(systemImage: "xmark", label: "Close") { flow.reset() }
                    Spacer()
                }
                slider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Mended.").font(.serif(.largeTitle)).foregroundStyle(Theme.ink)
                    Text(usedAgain).font(.body).foregroundStyle(Theme.inkSecondary)
                }
                VStack(spacing: 0) {
                    ShareLink(item: shareText(est)) {
                        Text("Share before and after").font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Button { if CameraPicker.isAvailable { showCamera = true } else { gallery = true } } label: {
                        Text(flow.resultPhoto == nil ? "Add a photo of the result" : "Replace the result photo")
                            .font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 16)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarBackButtonHidden()
        .navigationBarHidden(true)
        .floatingBar {
            PrimaryButton(title: "Done") { flow.reset() }
                .padding(.horizontal, Theme.margin).padding(.vertical, 12)
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
        }
    }

    @ViewBuilder private var slider: some View {
        if let before = flow.photo {
            let after = flow.resultPhoto ?? (flow.afterState == .ready ? flow.afterImage : nil)
            if let after {
                BeforeAfterSlider(before: before, after: after, aspect: 1.05, cornerRadius: Theme.heroRadius)
                    .id(after.hashValue)
            } else {
                Image(uiImage: before).resizable().scaledToFill()
                    .aspectRatio(1.05, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
            }
        }
    }

    /// Concrete line from the item's own title: "Your sweater is back in use."
    private var usedAgain: String {
        let summary = flow.response?.diagnosis.summary ?? ""
        let title = ProjectTitle.title(summary: summary, english: Lang.shared.isEnglish)
        let noun = title.split(separator: " ").last.map { String($0).lowercased() } ?? ""
        if noun.isEmpty { return "It's back in use." }
        let plural = noun.hasSuffix("s") && !noun.hasSuffix("ss")
        return "Your \(noun) \(plural ? "are" : "is") back in use."
    }

    private func shareText(_ est: ImpactEstimator.Estimate) -> String {
        tr("Ich habe gerade etwas repariert statt weggeworfen: ca. %@ kg vor Deponie oder Verbrennung bewahrt (Schätzung). #Reparieren", ImpactEstimator.format(kg: est.kilograms)) + " – Mendlet"
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
