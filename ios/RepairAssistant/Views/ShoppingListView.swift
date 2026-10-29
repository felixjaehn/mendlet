import SwiftUI

struct ShoppingListView: View {
    @Environment(FlowModel.self) private var flow
    @State private var expanded: Set<String> = []
    @State private var copied: String?

    var body: some View {
        let items = flow.shoppingItems
        let toBuy = ShoppingGate.toBuy(items: items, statuses: flow.statuses)
        let open = ShoppingGate.requiredOpen(items: items, statuses: flow.statuses)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                summary(toBuy.count, flow.response?.decision)
                ForEach([ItemKind.material, .tool], id: \.self) { kind in
                    let group = items.filter { $0.kind == kind }
                    if !group.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            SectionLabel(text: kind == .material ? "Material" : "Werkzeug")
                            VStack(spacing: 0) {
                                ForEach(Array(group.enumerated()), id: \.element.id) { i, item in
                                    row(item)
                                    if i < group.count - 1 { Divider().overlay(Theme.hairline) }
                                }
                            }
                            .card(padding: 0)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle("Einkaufsliste")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: ShoppingGate.shareText(title: flow.response?.diagnosis.summary.components(separatedBy: ".").first ?? tr("Reparatur"), items: items, statuses: flow.statuses)) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("Liste teilen")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                if !open.isEmpty {
                    Text(tr(open.count == 1 ? "Noch %lld Pflichtteil offen" : "Noch %lld Pflichtteile offen", open.count))
                        .font(.footnote.weight(.medium)).foregroundStyle(Theme.inkSecondary)
                }
                PrimaryButton(title: "Reparatur starten", systemImage: "play.fill") { flow.startRepair() }
                    .disabled(!flow.canStartRepair)
            }
            .padding(.horizontal, Theme.margin).padding(.vertical, 12).background(.regularMaterial)
        }
    }

    private func summary(_ buyCount: Int, _ decision: Decision?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "cart.fill").foregroundStyle(Theme.thread)
                .frame(width: 44, height: 44).background(Theme.threadSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(buyCount == 0 ? tr("Noch nichts zu kaufen") : tr(buyCount == 1 ? "%lld Ding kaufen" : "%lld Dinge kaufen", buyCount))
                    .font(.headline).foregroundStyle(Theme.ink)
                if let d = decision, !d.costEur.isEmpty {
                    Text("Gesamtkosten laut Schätzung \(Fmt.euro(d.costEur))").font(.footnote).foregroundStyle(Theme.inkSecondary)
                }
            }
            Spacer()
        }
        .card()
    }

    private func row(_ item: ShoppingItem) -> some View {
        let status = flow.statuses[item.id]
        let isOpen = expanded.contains(item.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(Theme.spring) { if isOpen { expanded.remove(item.id) } else { expanded.insert(item.id) } }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.name).font(.body.weight(.semibold)).foregroundStyle(status == .have ? Theme.inkSecondary : Theme.ink)
                            .strikethrough(status == .have, color: Theme.inkSecondary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Badge(text: item.required ? "Pflicht" : "optional", tint: item.required ? Theme.thread : Theme.inkSecondary)
                    }
                    HStack(spacing: 6) {
                        if !item.quantity.isEmpty { Text(item.quantity).font(.footnote).foregroundStyle(Theme.inkSecondary) }
                        if let alt = item.householdAlternative, !alt.isEmpty {
                            if !item.quantity.isEmpty { Text("·").foregroundStyle(Theme.inkSecondary) }
                            Text("oder: \(alt)").font(.footnote).foregroundStyle(Theme.inkSecondary).lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                statusButton("Habe ich", icon: "checkmark", tint: Theme.safe, active: status == .have) { flow.setStatus(item, .have) }
                statusButton("Kaufen", icon: "cart", tint: Theme.thread, active: status == .buy) { flow.setStatus(item, .buy) }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
                    .frame(width: 32, height: 32)
            }

            if isOpen {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.inkSecondary)
                    Text(item.searchTerm.isEmpty ? item.name : item.searchTerm).font(.subheadline).foregroundStyle(Theme.ink)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = item.searchTerm.isEmpty ? item.name : item.searchTerm
                        copied = item.id; Haptics.selection()
                        Task { try? await Task.sleep(for: .seconds(1.5)); if copied == item.id { copied = nil } }
                    } label: {
                        Label(copied == item.id ? tr("Kopiert") : tr("Kopieren"), systemImage: copied == item.id ? "checkmark" : "doc.on.doc")
                            .font(.footnote.weight(.semibold)).foregroundStyle(Theme.thread)
                    }
                }
                .padding(12).background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(flow.changedItemIds.contains(item.id) ? Theme.threadSoft : .clear)
        .overlay(alignment: .topTrailing) {
            if flow.changedItemIds.contains(item.id) {
                Label("durch Etikett angepasst", systemImage: "sparkles").font(.caption2.weight(.bold)).foregroundStyle(Theme.thread)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Theme.card, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.thread.opacity(0.4), lineWidth: 1)).padding(8)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func statusButton(_ title: String, icon: String, tint: Color, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.weight(.bold))
                Text(tr(title)).font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 14).frame(minHeight: 40)
            .foregroundStyle(active ? .white : Theme.inkSecondary)
            .background(active ? tint : Theme.paper, in: Capsule())
            .overlay(Capsule().strokeBorder(active ? .clear : Theme.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .animation(Theme.spring, value: active)
    }
}
