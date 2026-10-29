import SwiftUI

/// Greedy label placement: chips sit outside their mask, never overlap each other, and keep a leader line to a dot on the mask.
enum LabelPlacer {
    static let chipHeight: CGFloat = 24

    struct Item: Identifiable {
        let id: String
        let text: String, score: String?, badge: String?
        var polarity: String? = nil  // solder pads: coloured +/− disc in front of the text
        let anchor: CGPoint          // pin dot on the mask (px)
        let bounds: CGRect           // mask bounds (px), chips avoid it
        let width: CGFloat
        let large: Bool              // mask fills much of the photo: chip goes inside a corner
        var corners: [CGPoint] = []  // for large masks: candidate dot positions on the contour
        var dots: [CGPoint] = []     // grouped instances: one leader line (fan-out) and dot per instance
    }
    struct Placed: Identifiable { let item: Item; let dot: CGPoint; let rect: CGRect; var id: String { item.id } }

    static func width(text: String, score: String?, badge: String?, polarity: String? = nil) -> CGFloat {
        func w(_ s: String, _ size: CGFloat, _ weight: UIFont.Weight) -> CGFloat {
            ceil((s as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: size, weight: weight)]).width)
        }
        var x = 18 + w(text, 11.5, .semibold) + (polarity != nil ? 20 : 0)
        if let score { x += 5 + w(score, 11, .medium) }
        if let badge { x += 5 + w(badge, 8.5, .bold) + 9 }
        return x
    }

    static func place(_ items: [Item], in size: CGSize, obstacles: [CGRect] = []) -> [Placed] {
        var taken = obstacles
        var out: [Placed] = []
        let h = chipHeight, bounds = CGRect(origin: .zero, size: size).insetBy(dx: 4, dy: 4)
        for it in items {
            let w = it.width
            func rect(_ c: CGPoint) -> CGRect {
                var r = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
                r.origin.x = min(max(r.origin.x, bounds.minX), max(bounds.minX, bounds.maxX - w))
                r.origin.y = min(max(r.origin.y, bounds.minY), max(bounds.minY, bounds.maxY - h))
                return r
            }
            var cands: [(CGPoint, CGRect)] = []
            let a = it.anchor, b = it.bounds
            if it.large {
                for (i, c) in it.corners.enumerated() {
                    let sx: CGFloat = i % 2 == 0 ? 1 : -1, sy: CGFloat = i < 2 ? 1 : -1
                    cands.append((c, rect(CGPoint(x: c.x + sx * (14 + w / 2), y: c.y + sy * (16 + h / 2)))))
                }
            } else {
                for gap in [20.0, 40.0] as [CGFloat] {
                    cands += [
                        (a, rect(CGPoint(x: a.x, y: b.minY - gap - h / 2))),
                        (a, rect(CGPoint(x: a.x, y: b.maxY + gap + h / 2))),
                        (a, rect(CGPoint(x: b.maxX + gap + w / 2, y: a.y))),
                        (a, rect(CGPoint(x: b.minX - gap - w / 2, y: a.y))),
                        (a, rect(CGPoint(x: b.maxX + gap + w / 2, y: b.minY - gap))),
                        (a, rect(CGPoint(x: b.minX - gap - w / 2, y: b.maxY + gap))),
                    ]
                }
            }
            func cost(_ r: CGRect) -> CGFloat {
                var c: CGFloat = 0
                for t in taken { let i = r.insetBy(dx: -4, dy: -3).intersection(t); if !i.isNull { c += i.width * i.height + 1 } }
                if !it.large { let i = r.intersection(b.insetBy(dx: -4, dy: -4)); if !i.isNull { c += i.width * i.height + 1 } }
                return c
            }
            let best = cands.first { cost($0.1) == 0 } ?? cands.min { cost($0.1) < cost($1.1) }
            guard let best else { continue }
            taken.append(best.1)
            out.append(Placed(item: it, dot: best.0, rect: best.1))
        }
        return out
    }
}

struct LabelPinsLayer: View {
    let segments: [Segment]
    let all: [Segment]
    let size: CGSize
    var reveal: Double? = nil
    var extraObstacles: [CGRect] = []

    var body: some View {
        let placed = LabelPlacer.place(items(), in: size, obstacles: extraObstacles)
        ZStack(alignment: .topLeading) {
            ForEach(placed) { p in
                let seg = segments.first { $0.id == p.id }
                PinView(placed: p, color: seg.map { SolderStyle.padColor($0.polarity) ?? segmentColor($0, in: all) } ?? Theme.thread, emphasized: seg?.isDamage == true)
                    .opacity(reveal.map { min(1, max(0, ($0 - p.dot.y / max(size.height, 1)) * 10)) } ?? 1)
                    .transition(.opacity)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    static func plural(_ label: String, _ n: Int) -> String {
        switch label {
        case "Loch", "Hole": return tr("%lld Löcher", n)
        case "Riss", "Tear": return tr("%lld Risse", n)
        case "Fleck", "Stain": return tr("%lld Flecken", n)
        default: return "\(n)× \(tr(label))"
        }
    }

    static func stripPolarity(_ label: String) -> String {
        var t = label.trimmingCharacters(in: .whitespaces)
        if let last = t.last, "+-−–".contains(last) { t.removeLast() }
        t = t.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? label : t
    }

    private func info(_ s: Segment) -> (anchor: CGPoint, bounds: CGRect, pts: [CGPoint])? {
        guard let nb = s.normalizedBounds else { return nil }
        let b = CGRect(x: nb.minX * size.width, y: nb.minY * size.height, width: nb.width * size.width, height: nb.height * size.height)
        let pts = s.ringPolygons.filter { !$0.hole }.flatMap(\.points).map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        func nearest(_ t: CGPoint) -> CGPoint { pts.min { hypot($0.x - t.x, $0.y - t.y) < hypot($1.x - t.x, $1.y - t.y) } ?? t }
        let centroid = pts.isEmpty ? CGPoint(x: b.midX, y: b.midY) : CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count), y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count))
        return (pts.isEmpty ? CGPoint(x: b.midX, y: b.minY) : nearest(centroid), b, pts)
    }

    func items() -> [LabelPlacer.Item] {
        let labelled = segments.filter { !$0.label.isEmpty }
        // damage instances with the same label collapse into one chip ("3 Löcher · 78 %")
        let damage = labelled.filter(\.isDamage)
        var groups: [[Segment]] = []
        for s in damage {
            if let i = groups.firstIndex(where: { $0[0].label == s.label }) { groups[i].append(s) } else { groups.append([s]) }
        }
        var out: [LabelPlacer.Item] = []
        for g in groups {
            let infos = g.compactMap { info($0) }
            guard let first = infos.first, let s0 = g.first else { continue }
            let top = g.map(\.score).max() ?? 0
            let score = top > 0 ? "\(Int((top * 100).rounded())) %" : nil
            let text = g.count > 1 ? Self.plural(s0.label, g.count) : tr(s0.label)
            let b = infos.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
            let anchor = g.count > 1 ? CGPoint(x: infos.map(\.anchor.x).reduce(0, +) / CGFloat(infos.count), y: infos.map(\.anchor.y).reduce(0, +) / CGFloat(infos.count)) : first.anchor
            let badge = s0.source?.badge
            out.append(LabelPlacer.Item(id: s0.id, text: text, score: score, badge: badge, anchor: anchor, bounds: b,
                                        width: LabelPlacer.width(text: text, score: score, badge: badge), large: false,
                                        dots: g.count > 1 ? infos.map(\.anchor) : []))
        }
        for s in labelled where !s.isDamage {
            guard let i = info(s) else { continue }
            let score = s.score > 0 ? "\(Int((s.score * 100).rounded())) %" : nil
            let badge = s.source?.badge
            let large = i.bounds.width * i.bounds.height > 0.3 * size.width * size.height
            func nearest(_ t: CGPoint) -> CGPoint { i.pts.min { hypot($0.x - t.x, $0.y - t.y) < hypot($1.x - t.x, $1.y - t.y) } ?? t }
            let b = i.bounds
            let corners = [b.origin, CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.minX, y: b.maxY), CGPoint(x: b.maxX, y: b.maxY)].map { i.pts.isEmpty ? $0 : nearest($0) }
            // "Lötpad +" -> disc "+" and text "Lötpad": the sign is not shown twice
            let text = tr(s.polarity == nil ? s.label : Self.stripPolarity(s.label))
            out.append(LabelPlacer.Item(id: s.id, text: text, score: score, badge: badge, polarity: s.polarity, anchor: i.anchor, bounds: b,
                                        width: LabelPlacer.width(text: text, score: score, badge: badge, polarity: s.polarity), large: large, corners: corners))
        }
        return out
    }
}

private struct PinView: View {
    let placed: LabelPlacer.Placed
    let color: Color
    let emphasized: Bool

    var body: some View {
        let it = placed.item, r = placed.rect
        let beside = placed.dot.y >= r.minY && placed.dot.y <= r.maxY
        let tail = beside ? CGPoint(x: placed.dot.x < r.midX ? r.minX : r.maxX, y: r.midY)
                          : CGPoint(x: min(max(placed.dot.x, r.minX + 12), r.maxX - 12), y: placed.dot.y < r.midY ? r.minY : r.maxY)
        ZStack(alignment: .topLeading) {
            let dots = it.dots.isEmpty ? [placed.dot] : it.dots
            Path { p in for d in dots { p.move(to: d); p.addLine(to: tail) } }
                .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                .shadow(color: .black.opacity(0.5), radius: 1.5)
            ForEach(Array(dots.enumerated()), id: \.offset) { _, d in
                Circle().fill(color).frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.45), radius: 2)
                    .position(d)
            }
            HStack(spacing: 5) {
                if let pol = it.polarity { PolarityDisc(polarity: pol, diameter: 15) }
                Text(it.text).font(.system(size: 11.5, weight: .semibold))
                if let s = it.score { Text(s).font(.system(size: 11, weight: .medium, design: .rounded)).monospacedDigit().opacity(0.7) }
                if let b = it.badge {
                    Text(b).font(.system(size: 8.5, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 1.5)
                        .background(.white.opacity(0.18), in: Capsule())
                }
            }
            .lineLimit(1).foregroundStyle(.white)
            .frame(width: r.width, height: r.height)
            .background(Capsule().fill(.black.opacity(0.58)))
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(emphasized ? color.opacity(0.9) : .white.opacity(0.28), lineWidth: 0.75))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            .position(x: r.midX, y: r.midY)
        }
    }
}
