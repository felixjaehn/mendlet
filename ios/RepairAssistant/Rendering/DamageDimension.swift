import SwiftUI

/// Honest size hint: only when a part segment with a known typical width exists to scale from.
enum DamageDimension {
    /// Typical real-world width (cm) of the part's box, matched by keyword in its label.
    static let typicalWidthsCM: [(keys: [String], cm: Double)] = [
        (["jeans", "hose", "trouser", "pants"], 20), (["shirt"], 50), (["sohle", "schuh", "sole", "shoe"], 28),
    ]

    struct Layout { let a: CGPoint, b: CGPoint, offset: CGVector, cm: Double, chipRect: CGRect }

    static func typicalWidth(for label: String) -> Double? {
        let l = label.lowercased()
        return typicalWidthsCM.first { $0.keys.contains { l.contains($0) } }?.cm
    }

    static func layout(segments: [Segment], size: CGSize) -> Layout? {
        guard let damage = segments.first(where: { $0.isDamage }), let db = damage.normalizedBounds else { return nil }
        let pts = damage.ringPolygons.filter { !$0.hole }.flatMap(\.points).map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        guard pts.count >= 3 else { return nil }
        // part with a known typical width that contains the damage centre; no such part means no number
        let c = CGPoint(x: db.midX, y: db.midY)
        let scale = segments.filter { !$0.isDamage }.compactMap { s -> (CGRect, Double)? in
            guard let w = typicalWidth(for: s.label), let b = s.normalizedBox ?? s.normalizedBounds, b.contains(c), b.width > 0.05 else { return nil }
            return (b, w)
        }.first
        guard let (pb, width) = scale else { return nil }
        // principal axis of the damage mask
        let mean = CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count), y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count))
        var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
        for p in pts { let dx = p.x - mean.x, dy = p.y - mean.y; sxx += dx * dx; syy += dy * dy; sxy += dx * dy }
        let ang = 0.5 * atan2(2 * sxy, sxx - syy)
        let u = CGVector(dx: cos(ang), dy: sin(ang))
        let proj = pts.map { ($0.x - mean.x) * u.dx + ($0.y - mean.y) * u.dy }
        guard let lo = proj.min(), let hi = proj.max(), hi - lo > 8 else { return nil }
        let a = CGPoint(x: mean.x + u.dx * lo, y: mean.y + u.dy * lo), b = CGPoint(x: mean.x + u.dx * hi, y: mean.y + u.dy * hi)
        let cm = Double((hi - lo) / (pb.width * size.width)) * width
        guard cm.isFinite, cm > 0.5, cm < 200 else { return nil }
        var n = CGVector(dx: -u.dy, dy: u.dx); if n.dy < 0 { n = CGVector(dx: -n.dx, dy: -n.dy) }
        let off = CGVector(dx: n.dx * 30, dy: n.dy * 30)
        let mid = CGPoint(x: (a.x + b.x) / 2 + off.dx, y: (a.y + b.y) / 2 + off.dy)
        let chipW: CGFloat = 134, chipH: CGFloat = 24
        var r = CGRect(x: mid.x - chipW / 2, y: mid.y - chipH / 2, width: chipW, height: chipH)
        r.origin.x = min(max(r.origin.x, 4), size.width - chipW - 4); r.origin.y = min(max(r.origin.y, 4), size.height - chipH - 4)
        return Layout(a: a, b: b, offset: off, cm: (cm * 2).rounded() / 2, chipRect: r)
    }
}

struct DimensionLineView: View {
    let layout: DamageDimension.Layout
    var body: some View {
        let l = layout
        let a = CGPoint(x: l.a.x + l.offset.dx, y: l.a.y + l.offset.dy), b = CGPoint(x: l.b.x + l.offset.dx, y: l.b.y + l.offset.dy)
        let d = CGVector(dx: b.x - a.x, dy: b.y - a.y), len = max(hypot(d.dx, d.dy), 1)
        let n = CGVector(dx: -d.dy / len * 4, dy: d.dx / len * 4)
        let cm = l.cm.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(l.cm)) : String(format: "%.1f", l.cm).replacingOccurrences(of: ".", with: Lang.shared.isEnglish ? "." : ",")
        ZStack(alignment: .topLeading) {
            Path { p in
                p.move(to: a); p.addLine(to: b)
                for q in [a, b] { p.move(to: CGPoint(x: q.x - n.dx, y: q.y - n.dy)); p.addLine(to: CGPoint(x: q.x + n.dx, y: q.y + n.dy)) }
            }
            .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 1, lineCap: .round))
            .shadow(color: .black.opacity(0.5), radius: 1.5)
            HStack(spacing: 5) {
                Text(tr("ca. %@ cm", cm)).font(.system(size: 11.5, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("geschätzt").font(.system(size: 9, weight: .medium)).opacity(0.65)
            }
            .lineLimit(1).foregroundStyle(.white)
            .frame(width: l.chipRect.width, height: l.chipRect.height)
            .background(Capsule().fill(.black.opacity(0.58)))
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 0.75))
            .position(x: l.chipRect.midX, y: l.chipRect.midY)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
