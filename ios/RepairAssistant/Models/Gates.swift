import Foundation

/// Pure safety gating. No guide or shopping UI is reachable unless this says so (PRD §7, §8).
enum FlowGate {
    enum Destination: Equatable, Sendable { case block, diagnosis }
    enum Route: Equatable, Sendable { case diagnosis, decision, shopping, guide, block, completion }

    static func isBlocked(_ r: AnalyzeResponse) -> Bool {
        r.riskLevel != .allowed || r.category == .unsupported || r.safety.blocked
    }

    static func guideAllowed(_ r: AnalyzeResponse) -> Bool {
        !isBlocked(r) && !r.diagnosis.needsMoreInfo
    }

    static func destination(for r: AnalyzeResponse) -> Destination {
        isBlocked(r) ? .block : .diagnosis
    }

    /// Whether a route may be opened for this response.
    static func canNavigate(to route: Route, response r: AnalyzeResponse?) -> Bool {
        guard let r else { return false }
        switch route {
        case .block: return isBlocked(r)
        case .diagnosis: return !isBlocked(r)
        case .decision: return guideAllowed(r) && r.decision != nil
        case .shopping: return guideAllowed(r) && r.decision?.recommendation == .repairSelf && !r.shoppingList.isEmpty
        case .guide, .completion: return guideAllowed(r) && !r.guide.steps.isEmpty
        }
    }

    /// Defensive: strips shopping list and guide whenever they must not exist.
    static func sanitized(_ r: AnalyzeResponse) -> AnalyzeResponse {
        var out = r
        if !guideAllowed(r) {
            out.shoppingList = []
            out.guide = .empty
        }
        if isBlocked(r) { out.safety.blocked = true }
        return out
    }
}

enum ItemStatus: String, Codable, Sendable {
    case have, buy
}

enum ShoppingGate {
    static func requiredOpen(items: [ShoppingItem], statuses: [String: ItemStatus]) -> [ShoppingItem] {
        items.filter { $0.required && statuses[$0.id] != .have }
    }
    static func canStart(items: [ShoppingItem], statuses: [String: ItemStatus]) -> Bool {
        !items.isEmpty && requiredOpen(items: items, statuses: statuses).isEmpty
    }
    static func toBuy(items: [ShoppingItem], statuses: [String: ItemStatus]) -> [ShoppingItem] {
        items.filter { statuses[$0.id] == .buy }
    }
    static func shareText(title: String, items: [ShoppingItem], statuses: [String: ItemStatus]) -> String {
        var lines = [tr("%@ – Einkaufsliste", title), ""]
        for kind in [ItemKind.material, .tool] {
            let group = items.filter { $0.kind == kind }
            guard !group.isEmpty else { continue }
            lines.append(kind == .material ? tr("Material") : tr("Werkzeug"))
            for i in group {
                let mark = statuses[i.id] == .have ? "[x]" : "[ ]"
                var l = "\(mark) \(i.name)"
                if !i.quantity.isEmpty { l += " (\(i.quantity))" }
                if !i.required { l += " – " + tr("optional") }
                if statuses[i.id] == .buy, !i.searchTerm.isEmpty { l += " – " + tr("Suche: %@", i.searchTerm) }
                lines.append(l)
            }
            lines.append("")
        }
        lines.append("Mendlet")
        return lines.joined(separator: "\n")
    }
}

/// Estimated landfill/incineration avoided, from a local weight table. Always an estimate ("ca.").
enum ImpactEstimator {
    struct Estimate: Sendable, Equatable {
        var garment: String
        var kilograms: Double
    }

    private static let table: [(keys: [String], name: String, kg: Double)] = [
        (["sneaker", "schuh", "turnschuh", "stiefel", "sohle", "shoe", "boot", "sole", "trainer"], "Sneaker (Paar)", 0.8),
        (["t-shirt", "tshirt", "shirt-", "tee"], "T-Shirt", 0.2),
        (["jeans", "denim", "jeanshose"], "Jeans", 0.6),
        (["pullover", "strick", "sweater", "hoodie", "wolle", "jumper", "knit", "wool"], "Pullover", 0.5),
        (["jacke", "mantel", "parka", "weste", "jacket", "coat", "vest"], "Jacke", 1.0),
        (["kleid", "rock", "dress", "skirt"], "Kleid", 0.35),
        (["hemd", "bluse", "blouse", "dress shirt"], "Hemd/Bluse", 0.25),
    ]

    static func estimate(summary: String, segmentLabels: [String], category: Category = .textile) -> Estimate {
        let hay = ([summary] + segmentLabels).joined(separator: " ").lowercased()
        if category == .shoe { return Estimate(garment: "Sneaker (Paar)", kilograms: 0.8) }
        for row in table where row.keys.contains(where: { hay.contains($0) }) {
            return Estimate(garment: row.name, kilograms: row.kg)
        }
        return Estimate(garment: "Kleidung", kilograms: 0.4)
    }

    static func format(kg: Double) -> String {
        let f = NumberFormatter()
        f.locale = Lang.shared.locale
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: kg)) ?? String(format: "%.1f", kg)
    }
}

enum ImpactFacts {
    struct Fact: Sendable { let text: String; let source: String }
    static var headline: Fact { Fact(text: tr("Jede Sekunde landet weltweit eine Lkw-Ladung Kleidung auf der Deponie oder in der Verbrennung."), source: "Ellen MacArthur Foundation") }
    static var secondary: Fact { Fact(text: tr("In der EU fallen pro Kopf 16 kg Textilabfall im Jahr an – nur 4,6 kg davon werden getrennt gesammelt."), source: "EEA, 2022") }
    static var lifetime: Fact { Fact(text: tr("9 Monate länger tragen senkt den CO₂-, Wasser- und Abfall-Fußabdruck um bis zu 20 %."), source: "WRAP") }
}
