import SwiftUI
import PhotosUI

/// Finding: one headline about what is wrong, with the marked photo as the hero.
struct DiagnosisView: View {
    @Environment(FlowModel.self) private var flow
    @State private var causesOpen = false
    @State private var showLabelCamera = false
    @State private var showLabelGallery = false
    @State private var labelPicker: PhotosPickerItem?
    @State private var sheetShown = false

    var body: some View {
        @Bindable var flow = flow
        let r = flow.response
        GeometryReader { geo in
            let photoHeight = geo.size.height * 0.56
            ZStack(alignment: .top) {
                Theme.surface.ignoresSafeArea()
                VStack(spacing: 0) {
                    hero(r, geo: geo).frame(height: photoHeight)
                    sheet(r)
                        .padding(.top, -Theme.heroRadius)
                        .offset(y: sheetShown ? 0 : 24).opacity(sheetShown ? 1 : 0)
                }
            }
            .ignoresSafeArea(edges: .top)
        }
        .floatingBar { ctaBar(r) }
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
                MarkedPhoto(image: photo, segments: r.segments, focus: DamageFocus.region(for: r.segments),
                            onTap: flow.refineMode ? { p in flow.refine(at: p) } : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    if let e = flow.refineError { Text(e).font(.footnote.weight(.medium)).foregroundStyle(.white).shadow(color: .black.opacity(0.4), radius: 2) }
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

    private func sheet(_ r: AnalyzeResponse?) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let r {
                    if r.diagnosis.needsMoreInfo {
                        Text("One more detail").overline()
                        Text(flow.followUpUsed ? "We need a sharper photo." : "One question first.")
                            .font(.serif(.title)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                        Text(flow.followUpUsed ? "Take a new photo and we will look again." : "A short answer lets us pick the right needle, thread and stitch.")
                            .font(.body).foregroundStyle(Theme.inkSecondary).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    } else {
                        let t = CopyPolish.headlineAndBody(r.diagnosis.summary, english: Lang.shared.isEnglish)
                        Text("What we found").overline()
                        Text(t.headline).font(.serif(.title)).foregroundStyle(Theme.ink)
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
                        if !r.diagnosis.likelyCauses.isEmpty { causeRow(r.diagnosis.likelyCauses) }
                        if flow.labelBusy { labelBusyRow } else if flow.labelOfferAvailable { labelOfferRow }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.margin).padding(.top, 24).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .background(Theme.surface, in: UnevenRoundedRectangle(topLeadingRadius: Theme.heroRadius, topTrailingRadius: Theme.heroRadius, style: .continuous))
    }

    /// One line collapsed; more causes on tap (Warby Parker expandable row).
    private func causeRow(_ causes: [String]) -> some View {
        let shown = Array(causes.prefix(3))
        return VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
            Button {
                guard shown.count > 1 else { return }
                withAnimation(Theme.spring) { causesOpen.toggle() }
                Haptics.selection()
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Cause").font(.subheadline).foregroundStyle(Theme.inkSecondary).frame(width: 64, alignment: .leading)
                    Text(CopyPolish.sentence(shown[0], english: Lang.shared.isEnglish).trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                        .font(.subheadline.weight(.medium)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    if shown.count > 1 {
                        Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
                            .rotationEffect(.degrees(causesOpen ? 180 : 0))
                    }
                }
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if causesOpen {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(shown.dropFirst().enumerated()), id: \.offset) { _, c in
                        Text(CopyPolish.sentence(c, english: Lang.shared.isEnglish).trimmingCharacters(in: CharacterSet(charactersIn: ".")))
                            .font(.subheadline).foregroundStyle(Theme.ink)
                    }
                }
                .padding(.leading, 76).padding(.bottom, 12)
                .transition(.opacity)
            }
            Rectangle().fill(Theme.hairline).frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
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
