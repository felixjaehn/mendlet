import ActivityKit
import Foundation

/// Live Activity for timed guide steps: glue cure / press time and the solder hold.
struct CureActivityAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable, Sendable {
        case cure, solder
        var symbol: String { self == .cure ? "timer" : "thermometer.medium" }
    }

    struct ContentState: Codable, Hashable, Sendable {
        var startedAt: Date
        var endsAt: Date

        var range: ClosedRange<Date> { startedAt...max(startedAt, endsAt) }
        var total: TimeInterval { max(0, endsAt.timeIntervalSince(startedAt)) }
        func remaining(at now: Date) -> TimeInterval { min(total, max(0, endsAt.timeIntervalSince(now))) }
        func progress(at now: Date) -> Double { total > 0 ? 1 - remaining(at: now) / total : 1 }
    }

    var itemName: String
    var stepTitle: String
    var kind: Kind
}
