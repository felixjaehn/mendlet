import ActivityKit
import Foundation

/// Starts and ends the Live Activity for a timed guide step. All calls are safe when Live Activities are unavailable.
@MainActor
final class CureActivityController {
    static let shared = CureActivityController()
    private var activity: Activity<CureActivityAttributes>?
    private var endTask: Task<Void, Never>?

    nonisolated static func state(seconds: TimeInterval, from start: Date = .now) -> CureActivityAttributes.ContentState {
        .init(startedAt: start, endsAt: start.addingTimeInterval(max(1, seconds)))
    }

    func start(itemName: String, stepTitle: String, kind: CureActivityAttributes.Kind, seconds: TimeInterval) {
        end()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let st = Self.state(seconds: seconds)
        do {
            activity = try Activity.request(attributes: .init(itemName: itemName, stepTitle: stepTitle, kind: kind),
                                            content: .init(state: st, staleDate: st.endsAt), pushType: nil)
        } catch { activity = nil }
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds + 1))
            if !Task.isCancelled { self?.end() }
        }
    }

    func end() {
        endTask?.cancel(); endTask = nil
        guard activity != nil else { return }
        activity = nil
        Task.detached { for a in Activity<CureActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) } }
    }
}
