import XCTest
@testable import RepairAssistant

final class VoiceLayoutTests: XCTestCase {
    func testVoiceNeverIntersectsWorkArea() {
        let c = CGSize(width: 402, height: 874)
        let barTop: CGFloat = c.height - 100
        let sizes: [CGSize] = [CGSize(width: 70, height: 70), CGSize(width: 150, height: 160), CGSize(width: 300, height: 300)]
        let ys: [CGFloat] = [0.25, 0.5, 0.75].map { $0 * c.height }
        for s in sizes { for cy in ys { for vh in [CGFloat(76), 260] {
            let work = CGRect(x: (c.width - s.width) / 2, y: cy - s.height / 2, width: s.width, height: s.height)
            let p = VoiceLayout.place(container: c, work: work, topReserved: 130, barTop: barTop, voiceHeight: vh)
            XCTAssertFalse(p.voice.intersects(p.work), "size \(s) cy \(cy) vh \(vh): \(p)")
        } } }
    }
}
