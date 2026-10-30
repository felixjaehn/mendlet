import SwiftUI

/// Project detail: how far you are, what you still need, the steps, and one button to continue.
struct ProjectView: View {
    @Environment(FlowModel.self) private var flow
    let caseId: String
    @State private var showViewer = false
    @State private var confirmDelete = false
    @State private var haveOpen = false

    private var saved: SavedCase? { flow.store.savedCase(caseId) }
    private var r: AnalyzeResponse? { flow.response }
    private var finished: Bool { saved?.finished == true }
    private var parked: Bool { saved?.parked == true }
    private var steps: [GuideStep] { r?.guide.steps ?? [] }
    private var doneCount: Int { finished ? steps.count : max(flow.completedSteps.count, 0) }
    private var started: Bool { flow.currentStep > 0 || !flow.completedSteps.isEmpty }
    private var items: [ShoppingItem] { r?.shoppingList ?? [] }
    private var needed: [ShoppingItem] { items.filter { flow.statuses[$0.id] != .have } }
    private var have: [ShoppingItem] { items.filter { flow.statuses[$0.id] == .have } }
    private var requiredMissing: Bool { items.contains { $0.required && flow.statuses[$0.id] != .have } }

    var body: some View {
        ScrollView {
            if let r, let c = saved {
                VStack(alignment: .leading, spacing: 20) {
                    hero(r)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ProjectInfo.title(c)).font(.serif(.title)).foregroundStyle(Theme.ink)
                        Text(ProjectInfo.subtitle(c)).font(.subheadline).foregroundStyle(Theme.inkSecondary)
                    }
                    if parked {
                        Text("A pro will take this one. Come back after the repair to log it.").font(.body).foregroundStyle(Theme.inkSecondary).lineSpacing(4)
                    } else {
                        progress(c)
                        if !finished { needSection }
                        if !finished && !steps.isEmpty { stepsSection }
                    }
                }
                .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 40)
            }
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { confirmDelete = true } label: { Label("Delete project", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                .accessibilityLabel(tr("More"))
            }
        }
        .confirmationDialog("Delete this project? Your photo and progress will be removed.", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete project", role: .destructive) { flow.store.delete(caseId); flow.reset() }
            Button("Cancel", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showViewer) { if let p = flow.photo { PhotoViewer(image: p) } }
        .floatingBar { bar }
        .onAppear { if finished { flow.loadAfterPreview() } }
    }

    // MARK: Hero

    @ViewBuilder private func hero(_ r: AnalyzeResponse) -> some View {
        if let photo = flow.photo {
            Group {
                if finished, flow.afterState == .ready, let after = flow.afterImage {
                    BeforeAfterSlider(before: photo, after: after, aspect: 2.4, cornerRadius: Theme.heroRadius)
                } else {
                    Button { showViewer = true } label: {
                        Color(uiColor: .secondarySystemFill).aspectRatio(2.4, contentMode: .fit)
                            .overlay { MarkedPhoto(image: photo, segments: r.segments, mode: .thumb, showLabels: false, zoomable: false) }
                            .clipShape(RoundedRectangle(cornerRadius: Theme.heroRadius, style: .continuous))
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel(tr("Open photo"))
                }
            }
        }
    }

    // MARK: Progress

    @ViewBuilder private func progress(_ c: SavedCase) -> some View {
        if finished {
            VStack(alignment: .leading, spacing: 4) {
                Text("Repaired").font(.system(size: 34, weight: .semibold)).foregroundStyle(Theme.ink)
                Text((c.finishedAt ?? c.createdAt).formatted(.dateTime.day().month(.wide).year().locale(Lang.shared.locale))).font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
        } else {
            let cur = min(max(flow.currentStep, 0), max(steps.count - 1, 0))
            VStack(alignment: .leading, spacing: 12) {
                if let s = steps[safe: cur] {
                    Text("Step \(cur + 1) of \(steps.count) · \(s.title)").font(.headline).foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                SegmentBar(count: steps.count, done: doneCount, current: cur)
                if let next = steps[safe: cur + 1] {
                    HStack(spacing: 8) {
                        Text("Next").font(.subheadline.weight(.medium)).foregroundStyle(Theme.inkSecondary)
                        Text(next.title).font(.subheadline).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Needs

    private var needSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What you still need" + (needed.isEmpty ? "" : " · \(needed.count)")).sectionHeader()
            if needed.isEmpty {
                Text("You have everything you need.").font(.subheadline).foregroundStyle(Theme.inkSecondary).padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(needed.enumerated()), id: \.element.id) { i, it in
                        Button {
                            withAnimation(Theme.spring) { flow.setStatus(it, .have) }
                        } label: {
                            HStack(spacing: 12) {
                                Text(it.name).font(.body).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
                                Spacer(minLength: 8)
                                Text(it.required ? "Needed" : "Optional").font(.footnote).foregroundStyle(Theme.inkSecondary)
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
                            }
                            .padding(.vertical, 4).frame(minHeight: 48).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if i < needed.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 0.5) }
                    }
                }
            }
            if !have.isEmpty {
                DisclosureGroup(isExpanded: $haveOpen) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(have) { it in Text(it.name).font(.subheadline).foregroundStyle(Theme.inkSecondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                } label: {
                    Text("Already have \(have.count) item\(have.count == 1 ? "" : "s")").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                }
                .tint(Theme.inkSecondary)
                .padding(.top, 4)
            }
        }
    }

    // MARK: Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Steps").sectionHeader()
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    let isDone = flow.completedSteps.contains(i) || i < flow.currentStep
                    let isCurrent = i == flow.currentStep && !isDone
                    Button {
                        guard i <= flow.currentStep || isDone else { return }
                        flow.currentStep = i; flow.startRepair()
                    } label: {
                        HStack(alignment: .center, spacing: 16) {
                            StepNode(done: isDone, current: isCurrent)
                                .background(alignment: .center) {
                                    if i < steps.count - 1 { Rectangle().fill(Theme.hairline).frame(width: 1).offset(y: 22) }
                                }
                            Text(s.title).font(.body.weight(isCurrent ? .semibold : .regular))
                                .foregroundStyle(isDone ? Theme.inkSecondary : Theme.ink).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isCurrent ? .isSelected : [])
                }
            }
        }
    }

    // MARK: Bar

    @ViewBuilder private var bar: some View {
        VStack(spacing: 0) {
            if parked {
                PrimaryButton(title: "Mark as done") { flow.persist(finished: true); flow.reset() }
            } else if finished {
                PrimaryButton(title: "View before and after") { flow.go(.completion) }
            } else if !started && requiredMissing {
                PrimaryButton(title: "Gather what's missing") { flow.go(.shopping) }
            } else if started {
                PrimaryButton(title: "Continue with step \(min(flow.currentStep + 1, max(steps.count, 1)))") { flow.startRepair() }
            } else {
                PrimaryButton(title: "Start step 1") { flow.startRepair() }
            }
        }
        .padding(.horizontal, Theme.margin).padding(.vertical, 12)
    }
}

/// 12 pt timeline node: done = ink with a white check, current = accent ring with a centre, upcoming = empty ring.
private struct StepNode: View {
    var done: Bool
    var current: Bool
    var body: some View {
        ZStack {
            if done {
                Circle().fill(Theme.ink)
                Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(Color(uiColor: .systemBackground))
            } else if current {
                Circle().strokeBorder(Theme.thread, lineWidth: 2)
                Circle().fill(Theme.thread).frame(width: 4, height: 4)
            } else {
                Circle().strokeBorder(Theme.inkTertiary, lineWidth: 1.5)
            }
        }
        .frame(width: 12, height: 12)
        .frame(width: 24)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: done)
    }
}

/// Full-screen viewer for the saved photo.
struct PhotoViewer: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            CircleIconButton(systemImage: "xmark", label: "Close", onPhoto: true) { dismiss() }.padding(Theme.margin)
        }
        .onTapGesture { dismiss() }
    }
}
