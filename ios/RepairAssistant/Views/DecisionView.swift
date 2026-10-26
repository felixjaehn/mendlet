import SwiftUI

enum Fmt {
    static func number(_ v: Double) -> String {
        v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
    }
    static func range(_ a: [Double], unit: String) -> String {
        switch a.count {
        case 0: return "–"
        case 1: return "\(number(a[0])) \(unit)"
        default: return "\(number(a[0]))–\(number(a[1])) \(unit)"
        }
    }
    static func minutes(_ a: [Int]) -> String { range(a.map(Double.init), unit: "Min.") }
    static func euro(_ a: [Double]) -> String { range(a, unit: "€") }
}

extension Recommendation {
    var title: String {
        switch self {
        case .repairSelf: "Selbst reparieren"
        case .repairPro: "Zum Profi"
        case .replace: "Ersetzen"
        }
    }
    var icon: String {
        switch self {
        case .repairSelf: "scissors"
        case .repairPro: "wrench.and.screwdriver.fill"
        case .replace: "arrow.triangle.2.circlepath"
        }
    }
    var tint: Color {
        switch self {
        case .repairSelf: Theme.safe
        case .repairPro: Theme.caution
        case .replace: Theme.inkSecondary
        }
    }
    var tagline: String {
        switch self {
        case .repairSelf: "Günstig, lehrreich, nachhaltig"
        case .repairPro: "Sicher, kostet mehr"
        case .replace: "Schnell, aber mehr Abfall"
        }
    }
}

struct DecisionView: View {
    @Environment(FlowModel.self) private var flow

    var body: some View {
        ScrollView {
            if let d = flow.response?.decision {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 14) {
                            Image(systemName: d.recommendation.icon).font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                                .frame(width: 52, height: 52).background(d.recommendation.tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Meine Empfehlung").font(.footnote).foregroundStyle(Theme.inkSecondary)
                                Text(d.recommendation.title).font(.title.bold()).foregroundStyle(Theme.ink)
                            }
                        }
                        Text(d.reasoning).font(.body).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(padding: 18)

                    HStack(spacing: 10) {
                        MetricTile(icon: "gauge.with.dots.needle.33percent", title: "Aufwand", value: effortText(d.effort), detail: nil)
                        MetricTile(icon: "clock", title: "Zeit", value: Fmt.minutes(d.timeMinutes))
                        MetricTile(icon: "eurosign.circle", title: "Kosten", value: Fmt.euro(d.costEur))
                    }
                    EstimatePill(text: d.estimateNote)

                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Die Optionen im Vergleich")
                        ForEach([Recommendation.repairSelf, .repairPro, .replace], id: \.self) { o in
                            optionRow(o, selected: o == d.recommendation)
                        }
                    }
                }
                .padding(.horizontal, Theme.margin).padding(.top, 8).padding(.bottom, 24)
            }
        }
        .scrollIndicators(.hidden)
        .screenBackground()
        .navigationTitle("Entscheidung")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Group {
                if FlowGate.canNavigate(to: .shopping, response: flow.response) {
                    PrimaryButton(title: "Einkaufsliste ansehen", systemImage: "cart") { flow.go(.shopping) }
                } else {
                    PrimaryButton(title: "Neues Foto aufnehmen", systemImage: "camera.fill") { flow.reset() }
                }
            }
            .padding(.horizontal, Theme.margin).padding(.vertical, 12).background(.regularMaterial)
        }
    }

    private func effortText(_ e: Effort) -> String {
        switch e { case .low: "Gering"; case .medium: "Mittel"; case .high: "Hoch" }
    }

    private func optionRow(_ o: Recommendation, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: o.icon).foregroundStyle(selected ? o.tint : Theme.inkSecondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(o.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                Text(o.tagline).font(.footnote).foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(o.tint) }
        }
        .padding(14)
        .background(selected ? o.tint.opacity(0.10) : Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(selected ? o.tint.opacity(0.5) : Theme.hairline, lineWidth: selected ? 1.5 : 1))
        .opacity(selected ? 1 : 0.7)
    }
}
