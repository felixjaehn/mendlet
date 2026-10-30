import SwiftUI

/// "Before you start": what to gather. Two states per item (have / not yet), never blocks the first step.
struct ShoppingListView: View {
    @Environment(FlowModel.self) private var flow

    var body: some View {
        let items = flow.shoppingItems
        let ready = flow.shoppingProgress.ready
        let missing = flow.shoppingProgress.missing
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(items, ready: ready)
                ForEach([ItemKind.material, .tool], id: \.self) { kind in
                    let group = items.filter { $0.kind == kind }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(kind == .material ? "Materials" : "Tools").sectionHeader().padding(.leading, 4)
                            VStack(spacing: 0) {
                                ForEach(Array(group.enumerated()), id: \.element.id) { i, item in
                                    row(item)
                                    if i < group.count - 1 { Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 96) }
                                }
                            }
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: ShoppingGate.shareText(title: ProjectTitle.title(summary: flow.response?.diagnosis.summary ?? ""), items: items, statuses: flow.statuses)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(tr("Share list"))
            }
        }
        .floatingBar {
            VStack(spacing: 4) {
                Text(missing == 0 ? "Everything is ready" : (missing == 1 ? "1 thing still to get" : "\(missing) things still to get"))
                    .font(.footnote).foregroundStyle(Theme.inkSecondary).padding(.top, 8)
                PrimaryButton(title: continuing ? "Continue repair" : "Start repair") { flow.startRepair() }
                PrimaryButton(title: "I'll gather them later", kind: .secondary) { flow.reset() }
            }
            .padding(.horizontal, Theme.margin).padding(.bottom, 4)
        }
    }

    private var continuing: Bool { flow.currentStep > 0 || !flow.completedSteps.isEmpty }

    private func header(_ items: [ShoppingItem], ready: Int) -> some View {
        HStack(alignment: .top, spacing: 14) {
            if let photo = flow.photo, let r = flow.response {
                Color(uiColor: .secondarySystemFill).frame(width: 64, height: 64)
                    .overlay { MarkedPhoto(image: photo, segments: r.segments, mode: .thumb, showLabels: false, zoomable: false) }
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityHidden(true)
            }
            headerText(items, ready: ready)
        }
        .animation(Theme.spring, value: ready)
    }

    private func headerText(_ items: [ShoppingItem], ready: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(ready == items.count ? "All set" : "Gather these first")
                .font(.largeTitle.bold()).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Text("\(ready) of \(items.count) ready").font(.subheadline).foregroundStyle(Theme.inkSecondary)
                .monospacedDigit().contentTransition(.numericText())
            ProgressLine(value: items.isEmpty ? 0 : Double(ready) / Double(items.count))
            if let hi = flow.response?.decision?.costEur.last, hi > 0, let lo = flow.response?.decision?.costEur.first {
                Text("About \(Fmt.euro([lo, hi])) if you buy everything").font(.footnote).foregroundStyle(Theme.inkTertiary)
            }
        }
        .animation(Theme.spring, value: ready)
    }

    private func row(_ item: ShoppingItem) -> some View {
        let have = flow.statuses[item.id] == .have
        return HStack(alignment: .top, spacing: 14) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { flow.setStatus(item, .have) }
            } label: {
                HStack(alignment: .top, spacing: 14) {
                    CheckCircle(on: have).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.body).foregroundStyle(have ? Theme.inkSecondary : Theme.ink)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        if !item.quantity.isEmpty { Text(item.quantity).font(.subheadline).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.leading) }
                        if let alt = item.householdAlternative, !alt.isEmpty, !have {
                            Text("Or: \(alt)").font(.footnote).foregroundStyle(Theme.inkTertiary).multilineTextAlignment(.leading)
                        }
                        if flow.changedItemIds.contains(item.id) { Text("Updated from the label").font(.footnote).foregroundStyle(Theme.thread) }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(have ? .isSelected : [])
            if !item.required {
                Text("Optional").font(.footnote).foregroundStyle(Theme.inkTertiary).padding(.top, 3)
            } else if !have, let url = Self.shopURL(item) {
                Link("Find", destination: url).font(.subheadline.weight(.medium)).padding(.top, 2)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(minHeight: 56)
    }

    static func shopURL(_ item: ShoppingItem) -> URL? {
        let q = (item.searchTerm.isEmpty ? item.name : item.searchTerm).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/search?tbm=shop&q=\(q)")
    }
}
