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
        var x = 8 + w(text, 13, .semibold) + (polarity != nil ? 20 : 0)
        if let score { x += 5 + w(score, 11, .medium) }
        if let badge { x += 5 + w(badge, 8.5, .bold) + 9 }
        return x
    }

    static func place(_ items: [Item], in size: CGSize, obstacles: [CGRect] = [], clip: CGRect? = nil) -> [Placed] {
        var taken = obstacles
        var out: [Placed] = []
        let h = chipHeight, bounds = (clip.map { $0.intersection(CGRect(origin: .zero, size: size)) } ?? CGRect(origin: .zero, size: size)).insetBy(dx: 4, dy: 4)
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

/// Label items for one set of segments (grouped damage instances, parts); drawn by `MarkLabels`.
struct LabelPinsLayer {
    let segments: [Segment]
    let all: [Segment]
    let size: CGSize

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
        // anchor on the topmost contour point near the centre: the label sits right above it with a short leader
        let near = pts.filter { abs($0.x - centroid.x) < b.width * 0.3 }
        let top = (near.isEmpty ? pts : near).min { $0.y < $1.y }
        return (pts.isEmpty ? CGPoint(x: b.midX, y: b.minY) : (top ?? nearest(centroid)), b, pts)
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
            let score: String? = nil
            let text = g.count > 1 ? Self.plural(s0.label, g.count) : tr(s0.label)
            let b = infos.dropFirst().reduce(first.bounds) { $0.union($1.bounds) }
            // groups: one label, one leader to the top of the group (above its centre)
            let anchor = g.count > 1 ? CGPoint(x: b.midX, y: b.minY) : first.anchor
            let badge: String? = nil
            out.append(LabelPlacer.Item(id: s0.id, text: text, score: score, badge: badge, anchor: anchor, bounds: b,
                                        width: LabelPlacer.width(text: text, score: score, badge: badge), large: false,
                                        dots: []))
        }
        for s in labelled where !s.isDamage {
            guard let i = info(s) else { continue }
            let score: String? = nil
            let badge: String? = nil
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
