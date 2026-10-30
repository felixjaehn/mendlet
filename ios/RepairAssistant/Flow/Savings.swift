import Foundation

/// What the user saved by repairing instead of buying new. Always an estimate:
/// midpoint of the typical new price minus midpoint of the repair cost, never below zero.
enum Savings {
    struct Item: Identifiable, Hashable, Sendable {
        let id: String
        let newPrice: Double
        let repairCost: Double
        var saved: Double { max(newPrice - repairCost, 0) }
        let finishedAt: Date
    }

    struct Totals: Hashable, Sendable {
        var items: [Item] = []
        var moneySaved: Double { items.reduce(0) { $0 + $1.saved } }
        var repairsDone: Int { items.count }
        var itemsKeptInUse: Int { items.count }
        var isEmpty: Bool { items.isEmpty }
    }

    static func midpoint(_ range: [Double]) -> Double? {
        let v = range.filter { $0.isFinite }
        guard let lo = v.min(), let hi = v.max() else { return nil }
        return (lo + hi) / 2
    }

    /// One finished project's estimate, or nil when it does not count (not finished, replace verdict, no new price).
    static func item(for c: SavedCase) -> Item? {
        guard c.finished, let d = c.response.decision,
              d.recommendation == .repairSelf || d.recommendation == .repairPro,
              let new = midpoint(d.newPriceEur), new > 0 else { return nil }
        return Item(id: c.id, newPrice: new, repairCost: midpoint(d.costEur) ?? 0, finishedAt: c.finishedAt ?? c.createdAt)
    }

    static func totals(for cases: [SavedCase]) -> Totals {
        Totals(items: cases.compactMap(item(for:)).sorted { $0.finishedAt > $1.finishedAt })
    }

    /// "€65" for whole euros, rounded; the caller adds "about" where it is an estimate.
    static func euro(_ v: Double) -> String { "€\(Int(v.rounded()))" }

    struct Milestone: Hashable, Sendable { let title: String; let detail: String; let reached: Bool }

    static func milestones(_ t: Totals) -> [Milestone] {
        [Milestone(title: "First repair", detail: "1 repair", reached: t.repairsDone >= 1),
         Milestone(title: "Three repairs", detail: "3 repairs", reached: t.repairsDone >= 3),
         Milestone(title: "€100 saved", detail: "about €100", reached: t.moneySaved >= 100)]
    }
}
