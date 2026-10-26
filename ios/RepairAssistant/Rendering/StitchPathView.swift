import SwiftUI

enum DarningPhase: Sendable { case all, first, second }

/// Animated stitch path: thread draws progressively, numbered dots pop in, needle follows. Loops with a pause.
struct StitchPathView: View {
    let plan: StitchPlan
    var phase: DarningPhase = .all
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private struct Marker { var pointIndex: Int; var number: Int; var filled: Bool }

    var body: some View {
        if plan.kind == .none {
            Color.clear
        } else if reduceMotion {
            Canvas { ctx, size in draw(&ctx, size, progress: 1, alpha: 1, time: 100) }
                .accessibilityHidden(true)
        } else {
            TimelineView(.animation) { tl in
                Canvas { ctx, size in
                    let (p, a, t) = timing(tl.date.timeIntervalSince(start))
                    draw(&ctx, size, progress: p, alpha: a, time: t)
                }
            }
            .accessibilityHidden(true)
            .onAppear { start = Date() }
        }
    }

    // MARK: Timing

    private var drawDuration: Double {
        switch plan.kind {
        case .stitches: 1.2 + 0.32 * Double(plan.stitches.count)
        case .darning: 1.5 + 0.22 * Double(animatedLines.count)
        case .none: 1
        }
    }
    private let pause = 1.8

    private func timing(_ elapsed: Double) -> (progress: Double, alpha: Double, time: Double) {
        let cycle = drawDuration + pause
        let t = elapsed.truncatingRemainder(dividingBy: cycle)
        let p = min(1, t / drawDuration)
        let fadeStart = drawDuration + pause - 0.35
        let alpha = t > fadeStart ? max(0, 1 - (t - fadeStart) / 0.35) : 1
        return (p, alpha, t)
    }

    // MARK: Geometry

    private var firstSet: [[CGPoint]] { Array(plan.gridLines.prefix(plan.firstDirectionCount)) }
    private var secondSet: [[CGPoint]] { Array(plan.gridLines.dropFirst(plan.firstDirectionCount)) }
    private var animatedLines: [[CGPoint]] {
        switch phase {
        case .all: plan.gridLines
        case .first: firstSet
        case .second: secondSet
        }
    }

    private func polyline(_ size: CGSize) -> (pts: [CGPoint], markers: [Marker]) {
        func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
        switch plan.kind {
        case .stitches:
            let pts = plan.stitches.map { px($0.position) }
            let m = plan.stitches.enumerated().map { Marker(pointIndex: $0.offset, number: $0.element.index, filled: $0.offset % 2 == 0) }
            return (pts, m)
        case .darning:
            var pts: [CGPoint] = [], markers: [Marker] = []
            for (i, line) in animatedLines.enumerated() {
                guard line.count >= 2 else { continue }
                markers.append(Marker(pointIndex: pts.count, number: i + 1, filled: i % 2 == 0))
                pts.append(contentsOf: line.map(px))
            }
            return (pts, markers)
        case .none:
            return ([], [])
        }
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize, progress: Double, alpha: Double, time: Double) {
        let (pts, markers) = polyline(size)
        guard pts.count >= 2 else { return }
        let thread = Theme.thread
        ctx.opacity = alpha

        // Context: faint centerline (stitches) or already-placed first set (darning, second phase)
        if plan.kind == .stitches, plan.centerline.count >= 2 {
            var c = Path()
            c.move(to: CGPoint(x: plan.centerline[0].x * size.width, y: plan.centerline[0].y * size.height))
            for q in plan.centerline.dropFirst() { c.addLine(to: CGPoint(x: q.x * size.width, y: q.y * size.height)) }
            ctx.stroke(c, with: .color(.white.opacity(0.55)), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [2, 7]))
        }
        if plan.kind == .darning, phase == .second {
            for line in firstSet where line.count >= 2 {
                var p = Path()
                p.move(to: CGPoint(x: line[0].x * size.width, y: line[0].y * size.height))
                for q in line.dropFirst() { p.addLine(to: CGPoint(x: q.x * size.width, y: q.y * size.height)) }
                ctx.stroke(p, with: .color(thread.opacity(0.75)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
        }

        // cumulative length
        var cum: [CGFloat] = [0]
        for i in 1..<pts.count { cum.append(cum[i - 1] + hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)) }
        let total = max(cum.last ?? 1, 1)
        let drawn = total * CGFloat(progress)

        // partial polyline
        var path = Path()
        path.move(to: pts[0])
        var head = pts[0], headAngle: CGFloat = 0
        for i in 1..<pts.count {
            if cum[i] <= drawn {
                path.addLine(to: pts[i]); head = pts[i]
                headAngle = atan2(pts[i].y - pts[i - 1].y, pts[i].x - pts[i - 1].x)
            } else {
                let f = (drawn - cum[i - 1]) / max(cum[i] - cum[i - 1], 1e-6)
                if f > 0 {
                    head = CGPoint(x: pts[i - 1].x + (pts[i].x - pts[i - 1].x) * f, y: pts[i - 1].y + (pts[i].y - pts[i - 1].y) * f)
                    path.addLine(to: head)
                    headAngle = atan2(pts[i].y - pts[i - 1].y, pts[i].x - pts[i - 1].x)
                }
                break
            }
        }
        ctx.stroke(path, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
        ctx.stroke(path, with: .color(thread), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))

        // markers
        for m in markers {
            let at = cum[m.pointIndex]
            let reachedAt = at
            guard drawn + 0.5 >= reachedAt else { continue }
            let sinceFrac = Double((drawn - reachedAt) / total)
            let sinceSec = progress >= 1 ? 1.0 : sinceFrac * drawDuration
            let s = pop(min(1, max(0, sinceSec / 0.35)))
            let small = plan.kind == .darning
            let r: CGFloat = (small ? 6 : 11) * CGFloat(s)
            let center = pts[m.pointIndex]
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.fill(Path(ellipseIn: rect.insetBy(dx: -2, dy: -2)), with: .color(.black.opacity(0.28)))
            ctx.fill(Path(ellipseIn: rect), with: .color(m.filled ? thread : .white))
            ctx.stroke(Path(ellipseIn: rect), with: .color(m.filled ? .white : thread), lineWidth: 2.5)
            if s > 0.6 && !small {
                let label = Text("\(m.number)").font(.system(size: 11, weight: .bold, design: .rounded)).foregroundColor(m.filled ? .white : thread)
                ctx.draw(label, at: center)
            }
        }

        // needle
        if progress > 0 && progress < 1 {
            var n = ctx
            n.translateBy(x: head.x, y: head.y)
            n.rotate(by: .radians(Double(headAngle)))
            let needle = Path(roundedRect: CGRect(x: -20, y: -1.6, width: 34, height: 3.2), cornerRadius: 1.6)
            n.fill(Path(ellipseIn: CGRect(x: -9, y: -9, width: 18, height: 18)), with: .color(thread.opacity(0.25)))
            n.fill(needle, with: .linearGradient(Gradient(colors: [.white, Color(white: 0.7)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: 3)))
            n.stroke(needle, with: .color(.black.opacity(0.4)), lineWidth: 0.6)
            n.stroke(Path(ellipseIn: CGRect(x: -17, y: -1.2, width: 6, height: 2.4)), with: .color(.black.opacity(0.55)), lineWidth: 0.9)
        }
    }

    private func pop(_ x: Double) -> Double {
        // easeOutBack
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }
}
