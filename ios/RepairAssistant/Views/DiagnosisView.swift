import SwiftUI
import PhotosUI

/// Finding: one headline about what is wrong, with the marked photo as the hero.
struct DiagnosisView: View {
    @Environment(FlowModel.self) private var flow
    @State private var showLabelCamera = false
    @State private var showLabelGallery = false
    @State private var labelPicker: PhotosPickerItem?
    @State private var sheetShown = false

    var body: some View {
        @Bindable var flow = flow
        let r = flow.response
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Theme.surface.ignoresSafeArea()
                VStack(spacing: 0) {
                    hero(r, geo: geo).frame(maxHeight: .infinity)
                    sheet(r, maxHeight: geo.size.height * 0.58)
                        .padding(.top, -Theme.heroRadius)
                        .offset(y: sheetShown ? 0 : 24).opacity(sheetShown ? 1 : 0)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if r?.diagnosis.needsMoreInfo ?? false {
                ctaBar(r).background(.bar).overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
            }
        }
        .navigationBarBackButtonHidden()
        .navigationBarHidden(true)
        .sheet(isPresented: $flow.showFollowUp) { FollowUpSheet() }
        .fullScreenCover(isPresented: $showLabelCamera) { CameraPicker { flow.submitLabelPhoto($0) }.ignoresSafeArea() }
        .photosPicker(isPresented: $showLabelGallery, selection: $labelPicker, matching: .images)
        .onChange(of: labelPicker) { _, item in
            guard let item else { return }
            Task {
                if let d = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: d) { flow.submitLabelPhoto(img) }
                labelPicker = nil
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.45).delay(0.1)) { sheetShown = true }
            if let r, r.diagnosis.needsMoreInfo, !flow.followUpUsed, !r.diagnosis.followUpQuestions.isEmpty {
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    flow.showFollowUp = true
                }
            }
        }
    }

    // MARK: Hero

    @ViewBuilder private func hero(_ r: AnalyzeResponse?, geo: GeometryProxy) -> some View {
        ZStack(alignment: .top) {
            if let photo = flow.photo, let r {
                MarkedPhoto(image: photo, segments: r.segments, labelTopInset: 110, focus: DamageFocus.region(for: r.segments),
                            onTap: flow.refineMode ? { p in flow.refine(at: p) } : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .heroSource()
                if flow.refineBusy { ProgressView().controlSize(.large).tint(.white) }
            } else {
                Color.black
            }
            HStack {
                CircleIconButton(systemImage: "xmark", label: "Close", onPhoto: true) { flow.reset() }
                Spacer()
                if r != nil, !(r?.diagnosis.needsMoreInfo ?? false) { adjustButton }
            }
            .padding(.horizontal, Theme.margin).padding(.top, geo.safeAreaInsets.top + 8)
            .frame(maxHeight: .infinity, alignment: .top)
            if flow.refineMode {
                VStack(spacing: 8) {
                    if let e = flow.refineError { Text(e).font(.footnote.weight(.medium)).photoLabel() }
                    Text("Tap the damage").font(.footnote.weight(.medium)).foregroundStyle(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 8).glass(Capsule())
                }
                .padding(.bottom, Theme.heroRadius + 16)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .transition(.opacity)
            }
        }
        .clipped()
        .animation(Theme.spring, value: flow.refineMode)
    }

    /// SAM can miss a small hole. The next tap on the photo becomes a point prompt (`/refine`).
    private var adjustButton: some View {
        Button {
            withAnimation(Theme.spring) { flow.refineMode.toggle(); flow.refineError = nil }
            Haptics.selection()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: flow.refineMode ? "xmark" : "hand.tap").font(.system(size: 14, weight: .semibold))
                Text(flow.refineMode ? "Cancel" : "Adjust").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14).frame(height: 44)
            .glass(Capsule(), tint: Color.black.opacity(0.18), interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(flow.refineBusy)
        .accessibilityLabel(tr(flow.refineMode ? "Cancel" : "Adjust"))
        .accessibilityHint(tr("Tap the damage"))
    }

    // MARK: Sheet

    private func sheet(_ r: AnalyzeResponse?, maxHeight: CGFloat) -> some View {
        // shrinks to its content; scrolls only when the content is taller than half the screen
        ViewThatFits(in: .vertical) {
            sheetBody(r).padding(.bottom, 8)
            ScrollView { sheetBody(r) }.scrollIndicators(.hidden)
        }
        .frame(maxHeight: maxHeight)
        .background(Theme.surface, in: UnevenRoundedRectangle(topLeadingRadius: Theme.heroRadius, topTrailingRadius: Theme.heroRadius, style: .continuous))
    }

    private func sheetBody(_ r: AnalyzeResponse?) -> some View {
        Group {
            VStack(alignment: .leading, spacing: 14) {
                if let r {
                    if r.diagnosis.needsMoreInfo {
                        Text("One more detail").overline()
                        Text(flow.followUpUsed ? "We need a sharper photo." : "One question first.")
                            .font(.title.bold()).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        Text(flow.followUpUsed ? "Take a new photo and we will look again." : "A short answer lets us pick the right needle, thread and stitch.")
                            .font(.body).foregroundStyle(Theme.inkSecondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    } else {
                        let t = CopyPolish.headlineAndBody(r.diagnosis.summary, english: Lang.shared.isEnglish)
                        Text("What we found").overline()
                        Text(t.headline.trimmingCharacters(in: CharacterSet(charactersIn: "."))).font(.title.bold()).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if !t.body.isEmpty {
                            Text(t.body).font(.body).foregroundStyle(Theme.ink).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                        }
                        if let banner = flow.newInfoBanner, r.diagnosis.labelInfo != nil {
                            HStack(spacing: 8) {
                                Image(systemName: "tag").font(.footnote)
                                Text(banner).font(.subheadline)
                            }.foregroundStyle(Theme.inkSecondary)
                        }
                        if !flow.changedItemIds.isEmpty { changedLine(r) }
                        detailsList(r)
                        if flow.labelBusy { labelBusyRow } else if flow.labelOfferAvailable { labelOfferRow }
                        optionsButton
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.margin).padding(.top, 24).padding(.bottom, 24)
        }
    }

    /// Quiet inset-grouped list: cause, size (only when it can be scaled from a known part), material.
    private func detailRows(_ r: AnalyzeResponse) -> [(String, String)] {
        let english = Lang.shared.isEnglish
        var rows: [(String, String)] = []
        if let c = r.diagnosis.likelyCauses.first {
            rows.append(("Cause", CopyPolish.sentence(c, english: english).trimmingCharacters(in: CharacterSet(charactersIn: "."))))
        }
        if let img = flow.photo, let dim = DamageDimension.layout(segments: r.segments, size: img.size) {
            let cm = dim.cm.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(dim.cm)) : String(format: "%.1f", dim.cm)
            rows.append(("Size", "about \(cm) cm"))
        }
        if let m = materialText(r) { rows.append(("Material", m)) }
        return rows
    }

    @ViewBuilder private func detailsList(_ r: AnalyzeResponse) -> some View {
        let rows = detailRows(r)
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    if i > 0 { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 16) }
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(tr(row.0)).font(.subheadline).foregroundStyle(Theme.inkSecondary).frame(width: 72, alignment: .leading)
                        Text(row.1).font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 16).frame(minHeight: 46)
                }
            }
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private func materialText(_ r: AnalyzeResponse) -> String? {
        if let m = r.diagnosis.labelInfo?.materials.first, !m.isEmpty { return m }
        let t = (r.diagnosis.summary + " " + r.diagnosis.likelyCauses.joined(separator: " ")).lowercased()
        let table: [(String, String)] = [("knit", "Knit"), ("denim", "Denim"), ("jeans", "Denim"), ("leather", "Leather"), ("wool", "Wool"),
                                         ("cotton", "Cotton"), ("fleece", "Fleece"), ("canvas", "Canvas"), ("rubber", "Rubber"), ("circuit", "Circuit board")]
        return table.first { t.contains($0.0) }.map { tr($0.1) }
    }

    private func changedLine(_ r: AnalyzeResponse) -> some View {
        let names = r.shoppingList.filter { flow.changedItemIds.contains($0.id) }.map { $0.name.components(separatedBy: ",").first ?? $0.name }
        return Text(tr("Shopping list adjusted: %@", names.joined(separator: ", ")))
            .font(.subheadline).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
    }

    /// Optional, never blocks the way to the verdict.
    private var labelOfferRow: some View {
        Button {
            Haptics.tap()
            if flow.settings.demoMode { flow.applyDemoLabel() }
            else if CameraPicker.isAvailable { showLabelCamera = true } else { showLabelGallery = true }
        } label: {
            Text("Photograph the care label for a sharper plan").font(.body.weight(.medium)).foregroundStyle(Theme.thread)
                .multilineTextAlignment(.leading).frame(minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint(tr("Optional"))
    }

    private var labelBusyRow: some View {
        HStack(spacing: 12) {
            if let img = flow.labelImage {
                Image(uiImage: img).resizable().scaledToFill().frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.thumbRadius, style: .continuous))
            }
            Text("Reading the label").font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink)
            Spacer(minLength: 0)
            ProgressView()
        }
        .frame(minHeight: 44)
    }

    // MARK: CTA

    /// The sheet's own primary: the same ink capsule as everywhere else.
    private var optionsButton: some View {
        PrimaryButton(title: "See my options") { flow.go(.decision) }
            .padding(.top, 4)
    }

    @ViewBuilder private func ctaBar(_ r: AnalyzeResponse?) -> some View {
        if let r {
            VStack(spacing: 0) {
                if r.diagnosis.needsMoreInfo {
                    if flow.followUpUsed {
                        PrimaryButton(title: "Take a new photo") { flow.reset() }
                    } else {
                        PrimaryButton(title: "Answer the question") { flow.showFollowUp = true }
                    }
                } else {
                    PrimaryButton(title: "See my options") { flow.go(.decision) }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.vertical, 12)
        }
    }
}
