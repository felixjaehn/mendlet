import SwiftUI

// MARK: Home card

/// Compact savings card at the top of Home: only shown when at least one repair is finished.
struct SavingsCard: View {
    let totals: Savings.Totals
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated savings").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkSecondary)
                    Text("\(Savings.euro(totals.moneySaved)) saved")
                        .font(.system(size: 34, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                    Text("\(ImpactText.repairs(totals.repairsDone)) · \(ImpactText.kept(totals.itemsKeptInUse))")
                        .font(.subheadline).foregroundStyle(Theme.inkSecondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.inkTertiary)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("About \(Savings.euro(totals.moneySaved)) saved, \(ImpactText.repairs(totals.repairsDone)), \(ImpactText.kept(totals.itemsKeptInUse))")
        .accessibilityAddTraits(.isButton)
    }
}

enum ImpactText {
    static func repairs(_ n: Int) -> String { n == 1 ? "1 repair" : "\(n) repairs" }
    static func kept(_ n: Int) -> String { n == 1 ? "1 item kept" : "\(n) items kept" }
    static let footnote = "Estimated from typical new prices minus what the repair cost."
}

// MARK: Count-up number

/// Whole-euro number that counts up when `value` animates.
private struct CountingEuro: View, @preconcurrency Animatable {
    var value: Double
    var animatableData: Double { get { value } set { value = newValue } }
    var body: some View { Text(Savings.euro(value)) }
}

// MARK: Screen

struct ImpactView: View {
    @Environment(FlowModel.self) private var flow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Double = 0
    @State private var showExplain = false
    @State private var card: Image?

    var body: some View {
        let totals = Savings.totals(for: flow.doneProjects)
        ScrollView {
            VStack(spacing: 28) {
                if totals.isEmpty { empty } else {
                    hero(totals)
                    receipt(totals)
                    milestones(totals)
                    VStack(spacing: 12) {
                        Button("How is this calculated?") { showExplain = true }
                            .font(.subheadline).foregroundStyle(Theme.thread).frame(minHeight: 44)
                        if let card {
                            ShareLink(item: card, preview: SharePreview("My repair impact", image: card)) { Text("Share") }
                                .buttonStyle(PrimaryButtonStyle(kind: .primary))
                        }
                        Text(ImpactText.footnote).font(.footnote).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Your impact").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showExplain) { ImpactExplainSheet() }
        .onAppear {
            let target = totals.moneySaved
            if reduceMotion { shown = target } else { withAnimation(.easeOut(duration: 1.1).delay(0.15)) { shown = target } }
            render(totals)
        }
    }

    private func hero(_ t: Savings.Totals) -> some View {
        VStack(spacing: 6) {
            Text("About").font(.subheadline.weight(.medium)).foregroundStyle(Theme.inkSecondary)
            CountingEuro(value: shown)
                .font(.system(size: 76, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                .minimumScaleFactor(0.6).lineLimit(1)
                .accessibilityLabel("About \(Savings.euro(t.moneySaved))")
            Text("saved by repairing instead of buying new").font(.body).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
            HStack(spacing: 0) {
                stat(ImpactText.repairs(t.repairsDone))
                Rectangle().fill(Theme.hairline).frame(width: 0.5, height: 16)
                stat(ImpactText.kept(t.itemsKeptInUse))
            }
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity).padding(.top, 20)
    }

    private func stat(_ s: String) -> some View {
        Text(s).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink).padding(.horizontal, 16)
    }

    private func receipt(_ t: Savings.Totals) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repairs").sectionHeader().padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(t.items.enumerated()), id: \.element.id) { i, item in
                    if let c = flow.store.savedCase(item.id) { row(c, item) }
                    Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 76)
                }
                HStack {
                    Text("Estimated savings").font(.body.weight(.semibold))
                    Spacer()
                    Text(Savings.euro(t.moneySaved)).font(.body.weight(.semibold)).monospacedDigit()
                }
                .foregroundStyle(Theme.ink).padding(16)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private func row(_ c: SavedCase, _ item: Savings.Item) -> some View {
        HStack(spacing: 12) {
            MarkedThumb(caseId: c.id, response: c.response, store: flow.store)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Theme.thumbRadius, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(ProjectInfo.title(c)).font(.body.weight(.semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text("New ~\(Savings.euro(item.newPrice)) · Repair \(Savings.euro(item.repairCost))")
                    .font(.footnote).foregroundStyle(Theme.inkSecondary).lineLimit(1).minimumScaleFactor(0.85)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Savings.euro(item.saved)).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                Text("saved").font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private func milestones(_ t: Savings.Totals) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Milestones").sectionHeader().padding(.horizontal, 4)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Savings.milestones(t), id: \.title) { m in
                    VStack(spacing: 8) {
                        ZStack {
                            Circle().fill(m.reached ? Theme.ink : Color.clear)
                            Circle().strokeBorder(m.reached ? Color.clear : Theme.inkTertiary, lineWidth: 1)
                            if m.reached { Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color(uiColor: .systemBackground)) }
                        }
                        .frame(width: 36, height: 36)
                        Text(m.title).font(.footnote.weight(.semibold)).foregroundStyle(m.reached ? Theme.ink : Theme.inkSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .combine)
                    .accessibilityValue(m.reached ? "Reached" : "Not yet")
                }
            }
            .padding(.vertical, 16).padding(.horizontal, 8)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("Nothing saved yet.").font(.title2.bold()).foregroundStyle(Theme.ink)
            Text("Finish a repair and its savings show up here.").font(.body).foregroundStyle(Theme.inkSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 120)
    }

    @MainActor private func render(_ t: Savings.Totals) {
        guard !t.isEmpty else { return }
        let r = ImageRenderer(content: ImpactShareCard(totals: t).environment(\.colorScheme, .light))
        r.scale = 3
        if let ui = r.uiImage { card = Image(uiImage: ui) }
    }
}

// MARK: Explanation

struct ImpactExplainSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 0) {
                    line("Typical price of a new one", "€55")
                    line("What your repair cost", "− €5")
                    Rectangle().fill(Theme.hairline).frame(height: 0.5)
                    line("Saved", "€50", bold: true)
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                Text("We use the middle of each price range. The numbers are estimates, not receipts. A repair that costs more than a new one counts as zero, and only finished repairs count.")
                    .font(.body).foregroundStyle(Theme.inkSecondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(Theme.margin)
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("How is this calculated?").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }

    private func line(_ l: String, _ v: String, bold: Bool = false) -> some View {
        HStack { Text(l); Spacer(); Text(v).monospacedDigit() }
            .font(.body.weight(bold ? .semibold : .regular)).foregroundStyle(Theme.ink).padding(16)
    }
}

// MARK: Share card

/// The image that leaves the app: calm, light, one number.
struct ImpactShareCard: View {
    let totals: Savings.Totals
    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            Text("About").font(.system(size: 20, weight: .medium)).foregroundStyle(Color(white: 0.45))
            Text(Savings.euro(totals.moneySaved)).font(.system(size: 120, weight: .semibold)).monospacedDigit().foregroundStyle(Color(white: 0.08))
            Text("saved by repairing instead of buying new").font(.system(size: 20)).foregroundStyle(Color(white: 0.45))
            Rectangle().fill(Color(white: 0, opacity: 0.12)).frame(width: 40, height: 1).padding(.vertical, 36)
            Text("\(ImpactText.repairs(totals.repairsDone)) · \(ImpactText.kept(totals.itemsKeptInUse))")
                .font(.system(size: 22, weight: .semibold)).foregroundStyle(Color(white: 0.08))
            Spacer(minLength: 0)
            Text("Estimated from typical new prices minus what the repair cost.").font(.system(size: 13)).foregroundStyle(Color(white: 0.5))
                .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.bottom, 12)
            Text("Mendlet").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color(white: 0.08)).padding(.bottom, 32)
        }
        .frame(width: 400, height: 500)
        .background(Color(red: 0.96, green: 0.96, blue: 0.97))
    }
}
