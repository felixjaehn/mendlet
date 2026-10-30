import SwiftUI

/// Small damage is hard to see on a whole-photo view: zoom so the damage fills about a third of the stage.
enum DamageFocus {
    /// Damage whose bounds cover less than this share of the photo counts as small.
    static let smallArea: CGFloat = 0.04

    static func region(for segments: [Segment]) -> CGRect? {
        let boxes = segments.filter(\.isDamage).compactMap(\.normalizedBounds).filter { $0.width > 0 && $0.height > 0 }
        guard let first = boxes.first else { return nil }
        let u = boxes.dropFirst().reduce(first) { $0.union($1) }
        guard u.width * u.height < smallArea else { return nil }
        let side = max(0.28, max(u.width, u.height) * 3)
        return CGRect(x: u.midX - side / 2, y: u.midY - side / 2, width: side, height: side)
    }
}
