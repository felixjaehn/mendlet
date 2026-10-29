import SwiftUI
import PhotosUI

struct DiagnosisView: View {
    @Environment(FlowModel.self) private var flow
    @State private var hidden: Set<String> = []
    @State private var pulsing: Set<String> = []
    @State private var selectedCause: Int?
    @State private var appeared = false
    @State private var changedShown = false
    @State private var showLabelCamera = false
    @State private var showLabelGallery = false
    @State private var labelPicker: PhotosPickerItem?

    var body: some View {
        @Bindable var flow = flow
        let r = flow.response
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let photo = flow.photo, let r {
                    PhotoStage(image: photo, minAspect: 1.15) { size in
                        SegmentOverlayView(segments: r.segments, size: size, hidden: hidden, pulsingIDs: pulsing, appeared: appeared)
                    }
                    chipBar(r)
                }
                if let r {
                    if let banner = flow.newInfoBanner, r.diagnosis.labelInfo != nil { infoBanner(banner) }
                    if !flow.changedItemIds.isEmpty { changedCard(r) }
                    if flow.labelBusy { labelBusyCard } else if flow.labelOfferAvailable { labelOfferCard }
                    summaryCard(r)
                    if r.diagnosis.needsMoreInfo { needsInfoCard(r) }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .floatingBar { ctaBar(r) }
        .navigationBarBackButtonHidden()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { flow.reset() } label: { Image(systemName: "xmark") }.tint(.primary).accessibilityLabel("Schließen")
            }
        }
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
            withAnimation(.easeInOut(duration: 0.5).delay(0.15)) { appeared = true }
            if let r, r.diagnosis.needsMoreInfo, !flow.followUpUsed, !r.diagnosis.followUpQuestions.isEmpty {
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    flow.showFollowUp = true
                }
            }
        }
    }

    private func chipGroups(_ segments: [Segment]) -> [(label: String, ids: [String], first: Segment)] {
        var order: [String] = [], groups: [String: [Segment]] = [:]
        for s in segments {
            if groups[s.label] == nil { order.append(s.label) }
            groups[s.label, default: []].append(s)
        }
        return order.map { (label: $0, ids: groups[$0]!.map(\.id), first: groups[$0]![0]) }
    }

    private func chipBar(_ r: AnalyzeResponse) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(Theme.spring) { hidden = hidden.isEmpty ? Set(r.segments.map(\.id)) : [] }
                    Haptics.selection()
                } label: { Chip(title: "Alle", systemImage: "square.stack.3d.up", tint: Theme.ink, isOn: hidden.isEmpty, filled: hidden.isEmpty) }
                // One chip per label ("Loch ×3"), matching the grouped label pins on the photo.
                ForEach(chipGroups(r.segments), id: \.label) { g in
                    let off = g.ids.allSatisfy(hidden.contains)
                    Button {
                        withAnimation(Theme.spring) { if off { hidden.subtract(g.ids) } else { hidden.formUnion(g.ids) } }
                        Haptics.selection()
                    } label: {
                        Chip(title: g.ids.count > 1 ? "\(tr(g.label)) ×\(g.ids.count)" : g.label, systemImage: off ? "eye.slash" : "eye",
                             tint: g.first.isDamage ? Theme.thread : Theme.inkSecondary, isOn: !off)
                    }
                    .accessibilityLabel(tr(off ? "%@ einblenden" : "%@ ausblenden", tr(g.label)))
                }
            }
            .padding(.horizontal, Theme.margin)
        }
        .padding(.horizontal, -Theme.margin)
    }

    private func infoBanner(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "tag.fill").foregroundStyle(Theme.safe)
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                if flow.response?.diagnosis.labelInfo?.materials.contains(where: { $0.lowercased().contains("elasthan") || $0.lowercased().contains("elastane") || $0.lowercased().contains("spandex") }) == true {
                    Text("Elasthan erkannt, also ein dehnbarer Stich").font(.footnote).foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.safeSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private func summaryCard(_ r: AnalyzeResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(r.diagnosis.summary).font(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            ConfidenceMeter(confidence: r.diagnosis.confidence)
            if !r.diagnosis.likelyCauses.isEmpty {
                Divider().overlay(Theme.hairline)
                SectionLabel(text: "Wahrscheinliche Ursachen")
                VStack(spacing: 8) {
                    ForEach(Array(r.diagnosis.likelyCauses.enumerated()), id: \.offset) { i, cause in
                        Button { pulse(cause: i, r) } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)").font(.rounded(.footnote)).monospacedDigit()
                                    .foregroundStyle(selectedCause == i ? .white : Theme.thread)
                                    .frame(width: 24, height: 24)
                                    .background(selectedCause == i ? Theme.thread : Theme.threadSoft, in: Circle())
                                Text(cause).font(.subheadline).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if !r.diagnosis.evidenceSegmentIds.isEmpty {
                                    Image(systemName: "scope").font(.footnote).foregroundStyle(Theme.inkSecondary)
                                }
                            }
                            .padding(10)
                            .background(selectedCause == i ? Theme.threadSoft : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, -10)
            }
        }
        .card()
    }

    /// Optional, never blocks the way to the decision.
    private var labelOfferCard: some View {
        Button {
            Haptics.tap()
            if flow.settings.demoMode { flow.applyDemoLabel() }
            else if CameraPicker.isAvailable { showLabelCamera = true } else { showLabelGallery = true }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "tag.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Theme.thread, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    (Text("Etikett fotografieren für genauere Empfehlung ").foregroundStyle(Theme.ink) + Text("(optional)").foregroundStyle(Theme.inkSecondary))
                        .font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text("Material und Pflege passen Nadel, Garn und Flicken an.").font(.footnote).foregroundStyle(Theme.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary.opacity(0.6))
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHint("Optional, du kannst auch direkt weitermachen")
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
    }

    private var labelBusyCard: some View {
        HStack(spacing: 14) {
            if let img = flow.labelImage {
                Image(uiImage: img).resizable().scaledToFill().frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Muse Spark liest das Etikett").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text("Material und Pflege fließen in die Empfehlung ein.").font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 0)
            ProgressView().tint(Theme.thread)
        }
        .padding(14)
        .background(Theme.threadSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shimmer()
        .transition(.opacity)
    }

    /// What the label changed: shopping items that were swapped or adjusted.
    private func changedCard(_ r: AnalyzeResponse) -> some View {
        let items = r.shoppingList.filter { flow.changedItemIds.contains($0.id) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").foregroundStyle(Theme.thread)
                Text("Einkaufsliste angepasst").font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill").font(.footnote).foregroundStyle(Theme.thread).padding(.top, 2)
                        Text(it.name).font(.subheadline).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    .opacity(changedShown ? 1 : 0).offset(x: changedShown ? 0 : -10)
                    .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(0.25 + 0.12 * Double(i)), value: changedShown)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .transition(.scale(scale: 0.96).combined(with: .opacity))
        .onAppear { changedShown = true }
    }

    private func needsInfoCard(_ r: AnalyzeResponse) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "questionmark.bubble.fill").foregroundStyle(Theme.caution).font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text(flow.followUpUsed ? tr("Es fehlen weiter Angaben") : tr("Mir fehlt noch eine Angabe")).font(.headline)
                Text(flow.followUpUsed ? tr("Mach ein neues, schärferes Foto, dann versuche ich es noch einmal.") : tr("Mit einer kurzen Antwort kann ich Nadel, Faden und Stich genau wählen."))
                    .font(.subheadline).foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cautionSoft, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func ctaBar(_ r: AnalyzeResponse?) -> some View {
        if let r {
            VStack(spacing: 0) {
                if r.diagnosis.needsMoreInfo {
                    if flow.followUpUsed {
                        PrimaryButton(title: "Neues Foto aufnehmen", systemImage: "camera.fill") { flow.reset() }
                    } else {
                        PrimaryButton(title: "Frage beantworten", systemImage: "text.bubble.fill") { flow.showFollowUp = true }
                    }
                } else {
                    PrimaryButton(title: "Weiter zur Entscheidung", systemImage: "arrow.right") { flow.go(.decision) }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.vertical, 12)
            
        }
    }

    private func pulse(cause i: Int, _ r: AnalyzeResponse) {
        Haptics.selection()
        let ev = r.diagnosis.evidenceSegmentIds
        guard !ev.isEmpty else { return }
        selectedCause = i
        let id = ev[i % ev.count]
        hidden.remove(id)
        pulsing = [id]
        Task {
            try? await Task.sleep(for: .milliseconds(2600))
            if pulsing == [id] { pulsing = []; selectedCause = nil }
        }
    }
}
