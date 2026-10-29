import UIKit

private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Procedural placeholder photos (Core Graphics). The damage polygon is read from the scenario's
/// fixture so overlays line up exactly with what is drawn.
enum DemoImageFactory {
    static let size = CGSize(width: 1500, height: 1200)
    nonisolated(unsafe) private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func imageAsync(for scenario: DemoScenario) async -> UIImage {
        await Task.detached(priority: .userInitiated) { image(for: scenario) }.value
    }

    static func image(for scenario: DemoScenario) -> UIImage {
        lock.lock(); let hit = cache[scenario.rawValue]; lock.unlock()
        if let hit { return hit }
        let disk = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("demo-\(scenario.rawValue)-v4.jpg")
        if let d = try? Data(contentsOf: disk), let img = UIImage(data: d) {
            lock.lock(); cache[scenario.rawValue] = img; lock.unlock()
            return img
        }
        let resp = try? Fixtures.response(scenario, labelProvided: true)
        let damage = resp?.segments.first(where: { $0.isDamage })?.polygon ?? []
        let img = UIGraphicsImageRenderer(size: size, format: fmt()).image { ctx in
            let c = ctx.cgContext
            switch scenario {
            case .textileTear: drawDenim(c, tear: damage)
            case .textileHole, .realSweater, .wornShirt: drawKnit(c, hole: damage)
            case .shoeSole, .realSole: drawShoe(c, gap: damage)
            case .batteryJacket: drawJacket(c)
            case .helmet: drawHelmet(c)
            case .platine: drawJacket(c)
            }
        }
        lock.lock(); cache[scenario.rawValue] = img; lock.unlock()
        try? img.jpegData(compressionQuality: 0.92)?.write(to: disk, options: .atomic)
        return img
    }

    static func labelImage() -> UIImage {
        let s = CGSize(width: 1200, height: 900)
        return UIGraphicsImageRenderer(size: s, format: fmt()).image { ctx in drawLabel(ctx.cgContext, s) }
    }

    private static func fmt() -> UIGraphicsImageRendererFormat {
        let f = UIGraphicsImageRendererFormat(); f.scale = 1; f.opaque = true; return f
    }

    private static func px(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }
    private static func path(_ poly: [CGPoint]) -> CGPath {
        let p = CGMutablePath()
        guard let f = poly.first else { return p }
        p.move(to: px(f)); for q in poly.dropFirst() { p.addLine(to: px(q)) }
        p.closeSubpath(); return p
    }
    private static func col(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
        CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: a)
    }
    private static func gradient(_ c: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
        c.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }
    private static func radial(_ c: CGContext, center: CGPoint, radius: CGFloat, inner: CGColor, outer: CGColor) {
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [inner, outer] as CFArray, locations: nil)!
        c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
    }
    private static func vignette(_ c: CGContext, strength: CGFloat = 0.45) {
        radial(c, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: size.height * 0.75,
               inner: col(0, 0, 0, 0), outer: col(0, 0, 0, strength))
    }

    // MARK: Denim

    private static func drawDenim(_ c: CGContext, tear: [CGPoint]) {
        var rng = SeededRNG(state: 42)
        let W = size.width, H = size.height
        gradient(c, [col(52, 80, 124), col(36, 60, 100), col(44, 70, 112)], from: .zero, to: CGPoint(x: W, y: H))
        // twill: diagonal strokes
        c.setLineCap(.round)
        for _ in 0..<9000 {
            let x = CGFloat.random(in: -20...W, using: &rng), y = CGFloat.random(in: -20...H, using: &rng)
            let len = CGFloat.random(in: 7...15, using: &rng)
            let light = Bool.random(using: &rng)
            c.setStrokeColor(light ? col(190, 210, 240, CGFloat.random(in: 0.03...0.08, using: &rng)) : col(8, 18, 40, CGFloat.random(in: 0.04...0.09, using: &rng)))
            c.setLineWidth(CGFloat.random(in: 1.2...2.4, using: &rng))
            c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + len * 0.8, y: y + len)); c.strokePath()
        }
        // weft lines
        c.setLineWidth(1)
        for y in stride(from: CGFloat(0), to: H, by: 3) {
            c.setStrokeColor(col(255, 255, 255, y.truncatingRemainder(dividingBy: 6) == 0 ? 0.025 : 0.0))
            c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: W, y: y)); c.strokePath()
        }
        // grain
        for _ in 0..<9000 {
            c.setFillColor(Bool.random(using: &rng) ? col(255, 255, 255, 0.05) : col(0, 0, 0, 0.07))
            c.fill(CGRect(x: CGFloat.random(in: 0...W, using: &rng), y: CGFloat.random(in: 0...H, using: &rng), width: 2, height: 2))
        }
        // worn patch
        radial(c, center: CGPoint(x: W * 0.5, y: H * 0.5), radius: W * 0.55, inner: col(150, 180, 220, 0.30), outer: col(150, 180, 220, 0))
        // wrinkles
        for i in 0..<7 {
            let y = H * (0.18 + 0.12 * CGFloat(i)) + CGFloat.random(in: -20...20, using: &rng)
            let p = CGMutablePath()
            p.move(to: CGPoint(x: -20, y: y))
            p.addCurve(to: CGPoint(x: W + 20, y: y + CGFloat.random(in: -60...60, using: &rng)),
                       control1: CGPoint(x: W * 0.3, y: y - 70), control2: CGPoint(x: W * 0.7, y: y + 70))
            c.addPath(p); c.setStrokeColor(col(10, 20, 45, 0.09)); c.setLineWidth(46); c.strokePath()
            c.addPath(p); c.setStrokeColor(col(210, 225, 250, 0.07)); c.setLineWidth(14); c.strokePath()
        }
        // side seam with topstitching
        let sx = W * 0.105
        gradient(c, [col(0, 0, 0, 0), col(10, 20, 40, 0.5), col(0, 0, 0, 0)], from: CGPoint(x: sx - 40, y: 0), to: CGPoint(x: sx + 40, y: 0))
        c.setFillColor(col(0, 0, 0, 0)); 
        for dx in [-16.0, 16.0] {
            c.setStrokeColor(col(0, 0, 0, 0.35)); c.setLineWidth(8); c.setLineDash(phase: 0, lengths: [30, 12])
            c.move(to: CGPoint(x: sx + dx + 2, y: 0)); c.addLine(to: CGPoint(x: sx + dx + 2, y: H)); c.strokePath()
            c.setStrokeColor(col(214, 168, 76)); c.setLineWidth(6); c.setLineDash(phase: 0, lengths: [30, 12])
            c.move(to: CGPoint(x: sx + dx, y: 0)); c.addLine(to: CGPoint(x: sx + dx, y: H)); c.strokePath()
        }
        c.setLineDash(phase: 0, lengths: [])

        // tear
        if tear.count >= 3 {
            let tp = path(tear)
            // soft shadow around
            c.saveGState()
            c.setShadow(offset: .zero, blur: 28, color: col(0, 0, 10, 0.75))
            c.addPath(tp); c.setFillColor(col(8, 12, 22)); c.fillPath()
            c.restoreGState()
            c.saveGState()
            c.addPath(tp); c.clip()
            gradient(c, [col(16, 22, 36), col(30, 40, 60), col(12, 16, 28)], from: CGPoint(x: 0, y: H * 0.35), to: CGPoint(x: 0, y: H * 0.6))
            // exposed warp threads inside the tear
            let bb = tp.boundingBox
            for x in stride(from: bb.minX, to: bb.maxX, by: 5) {
                c.setStrokeColor(col(226, 232, 242, CGFloat.random(in: 0.45...0.9, using: &rng)))
                c.setLineWidth(CGFloat.random(in: 1.2...2.6, using: &rng))
                let y0 = bb.minY + CGFloat.random(in: 0...12, using: &rng)
                c.move(to: CGPoint(x: x, y: y0)); c.addLine(to: CGPoint(x: x + CGFloat.random(in: -2...2, using: &rng), y: bb.maxY - CGFloat.random(in: 0...12, using: &rng))); c.strokePath()
            }
            c.restoreGState()
            // frayed edge
            for i in 0..<tear.count {
                let a = px(tear[i]), b = px(tear[(i + 1) % tear.count])
                let steps = max(2, Int(hypot(a.x - b.x, a.y - b.y) / 7))
                for s in 0..<steps {
                    let t = CGFloat(s) / CGFloat(steps)
                    let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
                    let ang = CGFloat.random(in: 0...(2 * .pi), using: &rng), l = CGFloat.random(in: 6...22, using: &rng)
                    c.setStrokeColor(col(222, 226, 235, CGFloat.random(in: 0.5...0.95, using: &rng)))
                    c.setLineWidth(CGFloat.random(in: 1...2.2, using: &rng))
                    c.move(to: p); c.addQuadCurve(to: CGPoint(x: p.x + cos(ang) * l, y: p.y + sin(ang) * l),
                                                  control: CGPoint(x: p.x + cos(ang + 0.7) * l * 0.7, y: p.y + sin(ang + 0.7) * l * 0.7)); c.strokePath()
                }
            }
            c.addPath(tp); c.setStrokeColor(col(190, 205, 230, 0.35)); c.setLineWidth(2); c.strokePath()
        }
        vignette(c, strength: 0.4)
    }

    // MARK: Knit

    private static func drawKnit(_ c: CGContext, hole: [CGPoint]) {
        var rng = SeededRNG(state: 7)
        let W = size.width, H = size.height
        gradient(c, [col(150, 140, 124), col(128, 118, 104)], from: .zero, to: CGPoint(x: 0, y: H))
        c.setLineCap(.round)
        let dx: CGFloat = 20, dy: CGFloat = 22
        var row = 0
        for y in stride(from: CGFloat(-10), to: H + 20, by: dy) {
            for x in stride(from: CGFloat(-10) + (row % 2 == 0 ? 0 : dx / 2), to: W + 20, by: dx) {
                let j = CGFloat.random(in: -1.2...1.2, using: &rng)
                // V-stitch: shadow then highlight
                c.setLineWidth(7)
                c.setStrokeColor(col(60, 52, 44, 0.45))
                c.move(to: CGPoint(x: x - 7 + j, y: y - 7)); c.addLine(to: CGPoint(x: x + j, y: y + 8)); c.addLine(to: CGPoint(x: x + 7 + j, y: y - 7)); c.strokePath()
                c.setLineWidth(5)
                c.setStrokeColor(col(206, 196, 178, CGFloat.random(in: 0.7...1, using: &rng)))
                c.move(to: CGPoint(x: x - 7 + j, y: y - 8)); c.addLine(to: CGPoint(x: x + j, y: y + 6)); c.addLine(to: CGPoint(x: x + 7 + j, y: y - 8)); c.strokePath()
                c.setLineWidth(1.5)
                c.setStrokeColor(col(255, 250, 235, 0.35))
                c.move(to: CGPoint(x: x - 6 + j, y: y - 8)); c.addLine(to: CGPoint(x: x + j, y: y + 4)); c.strokePath()
            }
            row += 1
        }
        // soft folds
        for i in 0..<5 {
            let y = H * (0.15 + 0.17 * CGFloat(i))
            let p = CGMutablePath(); p.move(to: CGPoint(x: -20, y: y))
            p.addCurve(to: CGPoint(x: W + 20, y: y + 30), control1: CGPoint(x: W * 0.3, y: y - 90), control2: CGPoint(x: W * 0.7, y: y + 90))
            c.addPath(p); c.setStrokeColor(col(40, 30, 20, 0.14)); c.setLineWidth(60); c.strokePath()
        }
        if hole.count >= 3 {
            let hp = path(hole)
            c.saveGState()
            c.setShadow(offset: .zero, blur: 30, color: col(20, 14, 8, 0.85))
            c.addPath(hp); c.setFillColor(col(24, 20, 16)); c.fillPath()
            c.restoreGState()
            c.saveGState(); c.addPath(hp); c.clip()
            radial(c, center: CGPoint(x: W * 0.5, y: H * 0.52), radius: 160, inner: col(70, 60, 52), outer: col(16, 12, 10))
            c.restoreGState()
            // loose loops
            for i in 0..<hole.count {
                let a = px(hole[i])
                for _ in 0..<2 {
                    let ang = CGFloat.random(in: 0...(2 * .pi), using: &rng), l = CGFloat.random(in: 12...34, using: &rng)
                    c.setStrokeColor(col(214, 204, 186, 0.9)); c.setLineWidth(CGFloat.random(in: 2.5...4.5, using: &rng))
                    c.move(to: a)
                    c.addCurve(to: CGPoint(x: a.x + cos(ang) * l, y: a.y + sin(ang) * l),
                               control1: CGPoint(x: a.x + cos(ang + 1) * l, y: a.y + sin(ang + 1) * l),
                               control2: CGPoint(x: a.x + cos(ang - 1) * l * 1.2, y: a.y + sin(ang - 1) * l * 1.2)); c.strokePath()
                }
            }
        }
        vignette(c, strength: 0.4)
    }

    // MARK: Shoe

    private static func drawShoe(_ c: CGContext, gap: [CGPoint]) {
        var rng = SeededRNG(state: 11)
        let W = size.width, H = size.height
        gradient(c, [col(226, 220, 210), col(196, 188, 176)], from: .zero, to: CGPoint(x: 0, y: H))
        // floor shadow
        c.saveGState(); c.setShadow(offset: .zero, blur: 50, color: col(0, 0, 0, 0.5))
        c.setFillColor(col(0, 0, 0, 0.25)); c.fillEllipse(in: CGRect(x: W * 0.1, y: H * 0.71, width: W * 0.82, height: 50)); c.restoreGState()
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * W, y: y * H) }
        // upper
        let up = CGMutablePath()
        up.move(to: P(0.075, 0.62))
        up.addCurve(to: P(0.14, 0.50), control1: P(0.07, 0.55), control2: P(0.09, 0.51))
        up.addCurve(to: P(0.42, 0.43), control1: P(0.24, 0.48), control2: P(0.33, 0.47))
        up.addCurve(to: P(0.56, 0.31), control1: P(0.48, 0.41), control2: P(0.51, 0.34))
        up.addCurve(to: P(0.74, 0.27), control1: P(0.62, 0.28), control2: P(0.69, 0.25))
        up.addCurve(to: P(0.91, 0.42), control1: P(0.83, 0.28), control2: P(0.90, 0.34))
        up.addLine(to: P(0.93, 0.62)); up.closeSubpath()
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: 10), blur: 20, color: col(0, 0, 0, 0.35))
        c.addPath(up); c.setFillColor(col(32, 92, 96)); c.fillPath(); c.restoreGState()
        c.saveGState(); c.addPath(up); c.clip()
        gradient(c, [col(70, 140, 142), col(26, 78, 84), col(18, 52, 58)], from: P(0.5, 0.25), to: P(0.5, 0.64))
        // canvas weave
        c.setLineWidth(1)
        for y in stride(from: H * 0.25, to: H * 0.65, by: 4) {
            c.setStrokeColor(col(255, 255, 255, 0.04)); c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: W, y: y)); c.strokePath()
        }
        // toe cap
        c.setFillColor(col(240, 236, 226, 0.92))
        let toe = CGMutablePath(); toe.move(to: P(0.07, 0.62)); toe.addCurve(to: P(0.14, 0.50), control1: P(0.07, 0.55), control2: P(0.09, 0.51))
        toe.addCurve(to: P(0.25, 0.60), control1: P(0.20, 0.50), control2: P(0.24, 0.55)); toe.addLine(to: P(0.25, 0.62)); toe.closeSubpath()
        c.addPath(toe); c.fillPath()
        c.restoreGState()
        // laces
        for i in 0..<6 {
            let t = CGFloat(i) / 5
            let a = P(0.36 + 0.2 * t, 0.43 - 0.11 * t), b = P(0.43 + 0.2 * t, 0.46 - 0.14 * t)
            c.setStrokeColor(col(246, 244, 238)); c.setLineWidth(18); c.setLineCap(.round)
            c.move(to: a); c.addLine(to: b); c.strokePath()
            c.setStrokeColor(col(0, 0, 0, 0.18)); c.setLineWidth(3); c.move(to: CGPoint(x: a.x, y: a.y + 12)); c.addLine(to: CGPoint(x: b.x, y: b.y + 12)); c.strokePath()
        }
        // stitch line on upper
        c.setStrokeColor(col(240, 232, 214, 0.8)); c.setLineWidth(3); c.setLineDash(phase: 0, lengths: [14, 9])
        c.move(to: P(0.30, 0.60)); c.addCurve(to: P(0.86, 0.58), control1: P(0.46, 0.57), control2: P(0.70, 0.55)); c.strokePath(); c.setLineDash(phase: 0, lengths: [])
        // sole
        let sole = CGPath(roundedRect: CGRect(x: W * 0.07, y: H * 0.62, width: W * 0.86, height: H * 0.11), cornerWidth: 38, cornerHeight: 38, transform: nil)
        c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: 8), blur: 14, color: col(0, 0, 0, 0.3))
        c.addPath(sole); c.setFillColor(col(244, 240, 232)); c.fillPath(); c.restoreGState()
        c.saveGState(); c.addPath(sole); c.clip()
        gradient(c, [col(255, 252, 245), col(214, 206, 192)], from: P(0, 0.62), to: P(0, 0.73))
        c.setStrokeColor(col(0, 0, 0, 0.12)); c.setLineWidth(3)
        c.move(to: P(0, 0.685)); c.addLine(to: P(1, 0.685)); c.strokePath()
        for x in stride(from: W * 0.1, to: W * 0.92, by: 34) {
            c.setStrokeColor(col(0, 0, 0, 0.10)); c.setLineWidth(5)
            c.move(to: CGPoint(x: x, y: H * 0.70)); c.addLine(to: CGPoint(x: x + 12, y: H * 0.73)); c.strokePath()
        }
        for _ in 0..<2500 {
            c.setFillColor(col(120, 110, 90, 0.10))
            c.fill(CGRect(x: CGFloat.random(in: 0...W, using: &rng), y: CGFloat.random(in: H * 0.62...H * 0.73, using: &rng), width: 2, height: 2))
        }
        c.restoreGState()
        // detached gap
        if gap.count >= 3 {
            let gp = path(gap)
            c.saveGState()
            c.addPath(gp); c.clip()
            gradient(c, [col(10, 8, 6), col(70, 56, 40), col(24, 18, 12)], from: P(0.07, 0.585), to: P(0.40, 0.65))
            // dried glue strands
            for _ in 0..<26 {
                let x = CGFloat.random(in: W * 0.1...W * 0.38, using: &rng)
                c.setStrokeColor(col(214, 184, 110, 0.85)); c.setLineWidth(CGFloat.random(in: 1.5...3, using: &rng))
                c.move(to: CGPoint(x: x, y: H * 0.6)); c.addLine(to: CGPoint(x: x + CGFloat.random(in: -4...4, using: &rng), y: H * 0.655)); c.strokePath()
            }
            c.restoreGState()
            c.addPath(gp); c.setStrokeColor(col(0, 0, 0, 0.45)); c.setLineWidth(2); c.strokePath()
        }
        vignette(c, strength: 0.3)
    }

    // MARK: Jacket

    private static func drawJacket(_ c: CGContext) {
        let H = size.height, W = H
        gradient(c, [col(226, 222, 214), col(196, 190, 180)], from: .zero, to: CGPoint(x: 0, y: H))
        c.translateBy(x: (size.width - H) / 2, y: 0)
        func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * W, y: y * H) }
        let body = CGMutablePath()
        body.move(to: P(0.30, 0.10))
        body.addCurve(to: P(0.70, 0.10), control1: P(0.42, 0.06), control2: P(0.58, 0.06))
        body.addLine(to: P(0.92, 0.22)); body.addLine(to: P(0.98, 0.62)); body.addLine(to: P(0.84, 0.64))
        body.addLine(to: P(0.80, 0.40)); body.addLine(to: P(0.78, 0.86))
        body.addCurve(to: P(0.22, 0.86), control1: P(0.60, 0.89), control2: P(0.40, 0.89))
        body.addLine(to: P(0.20, 0.40)); body.addLine(to: P(0.16, 0.64)); body.addLine(to: P(0.02, 0.62)); body.addLine(to: P(0.08, 0.22)); body.closeSubpath()
        c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: 14), blur: 30, color: col(0, 0, 0, 0.35))
        c.addPath(body); c.setFillColor(col(46, 52, 62)); c.fillPath(); c.restoreGState()
        c.saveGState(); c.addPath(body); c.clip()
        gradient(c, [col(88, 98, 112), col(34, 38, 46)], from: P(0.3, 0.1), to: P(0.7, 0.9))
        for i in 0..<9 {
            let y = H * (0.18 + 0.075 * CGFloat(i))
            let p = CGMutablePath(); p.move(to: CGPoint(x: 0, y: y)); p.addQuadCurve(to: CGPoint(x: W, y: y), control: CGPoint(x: W / 2, y: y + 30))
            c.addPath(p); c.setStrokeColor(col(0, 0, 0, 0.4)); c.setLineWidth(5); c.strokePath()
            c.addPath(p); c.setStrokeColor(col(255, 255, 255, 0.08)); c.setLineWidth(3); c.strokePath()
        }
        c.setStrokeColor(col(190, 190, 190)); c.setLineWidth(6); c.setLineDash(phase: 0, lengths: [6, 4])
        c.move(to: P(0.5, 0.09)); c.addLine(to: P(0.5, 0.87)); c.strokePath(); c.setLineDash(phase: 0, lengths: [])
        c.restoreGState()
        // battery pocket
        let bp = CGRect(x: W * 0.55, y: H * 0.62, width: W * 0.2, height: H * 0.13)
        let rp = CGPath(roundedRect: bp, cornerWidth: 16, cornerHeight: 16, transform: nil)
        c.addPath(rp); c.setFillColor(col(24, 26, 30)); c.fillPath()
        c.addPath(rp); c.setStrokeColor(col(70, 76, 86)); c.setLineWidth(4); c.stroke(bp)
        c.setFillColor(col(255, 190, 40)); c.fill(CGRect(x: bp.minX + 22, y: bp.minY + 24, width: bp.width - 44, height: 20))
        c.setFillColor(col(255, 190, 40)); c.fill(CGRect(x: bp.minX + 22, y: bp.minY + 60, width: (bp.width - 44) * 0.6, height: 20))
        c.setStrokeColor(col(24, 26, 30)); c.setLineWidth(8)
        c.move(to: CGPoint(x: bp.minX, y: bp.midY)); c.addCurve(to: P(0.4, 0.5), control1: P(0.5, 0.7), control2: P(0.45, 0.55)); c.strokePath()
        vignette(c, strength: 0.25)
    }

    // MARK: Helmet

    private static func drawHelmet(_ c: CGContext) {
        let H = size.height, W = H
        gradient(c, [col(230, 228, 222), col(200, 198, 190)], from: .zero, to: CGPoint(x: 0, y: H))
        c.translateBy(x: (size.width - H) / 2, y: 0)
        let dome = CGRect(x: W * 0.12, y: H * 0.2, width: W * 0.76, height: H * 0.5)
        let shell = CGMutablePath()
        shell.move(to: CGPoint(x: dome.minX, y: dome.maxY))
        shell.addCurve(to: CGPoint(x: dome.maxX, y: dome.maxY), control1: CGPoint(x: dome.minX, y: dome.minY - 120), control2: CGPoint(x: dome.maxX, y: dome.minY - 120))
        shell.addLine(to: CGPoint(x: dome.maxX - 30, y: dome.maxY + 24)); shell.addLine(to: CGPoint(x: dome.minX + 30, y: dome.maxY + 24)); shell.closeSubpath()
        c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: 16), blur: 30, color: col(0, 0, 0, 0.35))
        c.addPath(shell); c.setFillColor(col(200, 40, 40)); c.fillPath(); c.restoreGState()
        c.saveGState(); c.addPath(shell); c.clip()
        gradient(c, [col(236, 90, 80), col(150, 24, 28)], from: CGPoint(x: W * 0.3, y: dome.minY), to: CGPoint(x: W * 0.7, y: dome.maxY))
        for i in 0..<4 {
            let x = dome.minX + dome.width * (0.22 + 0.18 * CGFloat(i))
            c.setFillColor(col(30, 20, 20, 0.85))
            c.fill(CGRect(x: x, y: dome.minY + 60, width: 54, height: dome.height * 0.62))
        }
        c.setStrokeColor(col(30, 20, 20, 0.9)); c.setLineWidth(5); c.setLineCap(.round)
        c.move(to: CGPoint(x: dome.midX - 60, y: dome.minY + 40)); c.addLine(to: CGPoint(x: dome.midX + 10, y: dome.minY + 140)); c.addLine(to: CGPoint(x: dome.midX - 20, y: dome.minY + 210)); c.strokePath()
        c.restoreGState()
        c.setStrokeColor(col(40, 40, 44)); c.setLineWidth(24)
        c.move(to: CGPoint(x: dome.minX + 120, y: dome.maxY + 20)); c.addCurve(to: CGPoint(x: dome.maxX - 120, y: dome.maxY + 20), control1: CGPoint(x: dome.minX + 160, y: dome.maxY + 340), control2: CGPoint(x: dome.maxX - 160, y: dome.maxY + 340)); c.strokePath()
        vignette(c, strength: 0.25)
    }

    // MARK: Label

    private static func drawLabel(_ c: CGContext, _ s: CGSize) {
        var rng = SeededRNG(state: 5)
        gradient(c, [col(44, 70, 112), col(32, 54, 92)], from: .zero, to: CGPoint(x: s.width, y: s.height))
        c.setLineCap(.round)
        for _ in 0..<7000 {
            let x = CGFloat.random(in: 0...s.width, using: &rng), y = CGFloat.random(in: 0...s.height, using: &rng)
            c.setStrokeColor(col(190, 210, 240, 0.06)); c.setLineWidth(1.5)
            c.move(to: CGPoint(x: x, y: y)); c.addLine(to: CGPoint(x: x + 6, y: y + 14)); c.strokePath()
        }
        c.saveGState()
        c.translateBy(x: s.width / 2, y: s.height / 2); c.rotate(by: -0.04)
        let r = CGRect(x: -400, y: -270, width: 800, height: 540)
        c.setShadow(offset: CGSize(width: 0, height: 8), blur: 18, color: col(0, 0, 0, 0.45))
        c.addPath(CGPath(roundedRect: r, cornerWidth: 10, cornerHeight: 10, transform: nil)); c.setFillColor(col(240, 236, 224)); c.fillPath()
        c.setShadow(offset: .zero, blur: 0, color: nil)
        // stitched edge
        c.setStrokeColor(col(150, 140, 120)); c.setLineWidth(2); c.setLineDash(phase: 0, lengths: [8, 6])
        c.stroke(r.insetBy(dx: 12, dy: 12)); c.setLineDash(phase: 0, lengths: [])
        let para = NSMutableParagraphStyle(); para.alignment = .left
        func text(_ t: String, _ y: CGFloat, _ size: CGFloat, _ weight: UIFont.Weight, _ alpha: CGFloat = 1) {
            UIGraphicsPushContext(c)
            (t as NSString).draw(in: CGRect(x: r.minX + 48, y: r.minY + y, width: 520, height: size * 1.4),
                                 withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: UIColor(white: 0.12, alpha: alpha), .paragraphStyle: para])
            UIGraphicsPopContext()
        }
        text("98 % COTTON / BAUMWOLLE", 50, 34, .heavy)
        text("2 % ELASTANE / ELASTHAN", 100, 34, .heavy)
        text("Size 32/32 · W32 L32", 170, 26, .medium, 0.8)
        text("Made in Portugal", 215, 26, .medium, 0.8)
        text("30° · nicht bleichen · nicht trocknen", 280, 24, .regular, 0.7)
        // wash symbol
        let wx = r.maxX - 190, wy = r.minY + 60
        c.setStrokeColor(col(30, 30, 30)); c.setLineWidth(5)
        let tub = CGMutablePath(); tub.move(to: CGPoint(x: wx, y: wy)); tub.addLine(to: CGPoint(x: wx + 22, y: wy + 96)); tub.addLine(to: CGPoint(x: wx + 110, y: wy + 96)); tub.addLine(to: CGPoint(x: wx + 132, y: wy)); tub.closeSubpath()
        c.addPath(tub); c.strokePath()
        UIGraphicsPushContext(c)
        ("30" as NSString).draw(at: CGPoint(x: wx + 40, y: wy + 40), withAttributes: [.font: UIFont.systemFont(ofSize: 30, weight: .bold)])
        UIGraphicsPopContext()
        c.setLineWidth(5)
        c.strokeEllipse(in: CGRect(x: wx + 14, y: wy + 130, width: 100, height: 100))
        c.move(to: CGPoint(x: wx + 4, y: wy + 240)); c.addLine(to: CGPoint(x: wx + 124, y: wy + 124)); c.strokePath()
        c.restoreGState()
        vignette(c, strength: 0.3)
    }
}
