import Foundation
import CoreGraphics

enum LiveCategory: String, CaseIterable, Identifiable, Sendable {
    case clothing = "Kleidung", shoe = "Schuh", electronics = "Elektronik"
    var id: String { rawValue }
    var title: String { tr(rawValue) }
    var concepts: [String] {
        switch self { case .clothing: ["tear", "hole"]; case .shoe: ["detached sole"]; case .electronics: ["wire"] }
    }
    var symbol: String {
        switch self { case .clothing: "tshirt"; case .shoe: "shoe"; case .electronics: "cable.connector" }
    }
    var scenario: DemoScenario {
        switch self { case .clothing: .textileTear; case .shoe: .shoeSole; case .electronics: .batteryJacket }
    }
}

struct LiveScanStateMachine {
    enum State: Equatable { case searching, detected, stable, captured }
    private(set) var state: State = .searching
    private var heldBounds: CGRect?
    private var stableSince: TimeInterval?
    private var lastFrame: TimeInterval?
    var holdDuration: TimeInterval = 1.2

    mutating func observe(polygon: [CGPoint], at time: TimeInterval, trackingValid: Bool) {
        guard state != .captured else { return }
        guard trackingValid, LiveGeometry.usable(polygon) else { reset(); return }
        let box = LiveGeometry.bounds(polygon)
        let gap = lastFrame.map { time - $0 > 0.25 } ?? false
        lastFrame = time
        let moved = heldBounds.map {
            hypot(box.midX - $0.midX, box.midY - $0.midY) > 0.018 ||
            abs(box.width - $0.width) > 0.025 || abs(box.height - $0.height) > 0.025
        } ?? true
        if moved || gap {
            heldBounds = box; stableSince = time; state = .detected
        } else if let stableSince, time - stableSince >= holdDuration {
            state = .stable
        }
    }

    mutating func captureSucceeded() {
        guard state == .stable else { return }
        state = .captured
    }

    mutating func reset() { self = Self(holdDuration: holdDuration) }
}
