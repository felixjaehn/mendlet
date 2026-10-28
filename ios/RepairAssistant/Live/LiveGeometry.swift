import CoreGraphics
import simd

/// Homographies here map normalized, top-left image coordinates to the next image.
struct LiveHomography: Sendable {
    var matrix: simd_double3x3
    static let identity = LiveHomography(matrix: matrix_identity_double3x3)

    func apply(_ point: CGPoint) -> CGPoint? {
        let p = matrix * SIMD3(Double(point.x), Double(point.y), 1)
        guard p.x.isFinite, p.y.isFinite, p.z.isFinite, abs(p.z) > 1e-8 else { return nil }
        return CGPoint(x: p.x / p.z, y: p.y / p.z)
    }

    func warp(_ points: [CGPoint]) -> [CGPoint]? {
        let result = points.compactMap(apply)
        return result.count == points.count ? result : nil
    }

    /// Vision returns a floating-image → reference-image transform in bottom-left pixels.
    static func vision(_ matrix: simd_float3x3, size: CGSize) -> Self {
        let pixels = simd_double3x3(rows: [SIMD3(Double(size.width), 0, 0),
                                         SIMD3(0, -Double(size.height), Double(size.height)), SIMD3(0, 0, 1)])
        let h = simd_double3x3(matrix.columns.0.double, matrix.columns.1.double, matrix.columns.2.double)
        return Self(matrix: pixels.inverse * h * pixels)
    }

    var isPlausible: Bool {
        guard abs(simd_determinant(matrix)) > 1e-8,
              let corners = warp([.zero, CGPoint(x: 1, y: 0), CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 1)]),
              corners.allSatisfy({ abs($0.x) < 4 && abs($0.y) < 4 }) else { return false }
        // Reject reflections, collapsed registrations and extreme changes of scale.
        let area = LiveGeometry.area(corners)
        return area > 0.12 && area < 6
    }

    func warp(_ plan: StitchPlan) -> StitchPlan? {
        guard let center = warp(plan.centerline), let stitches = warp(plan.stitches.map(\.position)) else { return nil }
        let grid = plan.gridLines.compactMap(warp)
        guard grid.count == plan.gridLines.count else { return nil }
        var result = plan
        result.centerline = center
        result.stitches = zip(plan.stitches, stitches).map { old, position in
            StitchPoint(position: position, side: old.side, index: old.index)
        }
        result.gridLines = grid
        return result
    }
}

private extension SIMD3<Float> {
    var double: SIMD3<Double> { SIMD3<Double>(Double(x), Double(y), Double(z)) }
}

enum LiveGeometry {
    static func area(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 3 else { return 0 }
        return points.indices.reduce(0) { sum, i in
            let a = points[i], b = points[(i + 1) % points.count]
            return sum + a.x * b.y - b.x * a.y
        } / 2
    }

    static func bounds(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    static func usable(_ points: [CGPoint]) -> Bool {
        points.count >= 3 && points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }
            && abs(area(points)) > 0.00001
    }

    /// Fixed sample count makes successive model masks morph even when vertex counts differ.
    static func resample(_ polygon: [CGPoint], count: Int = 48) -> [CGPoint] {
        guard polygon.count >= 3 else { return [] }
        let points = area(polygon) < 0 ? Array(polygon.reversed()) : polygon
        let closed = points + [points[0]]
        var lengths: [CGFloat] = [0]
        for i in 1..<closed.count { lengths.append(lengths[i - 1] + hypot(closed[i].x - closed[i - 1].x, closed[i].y - closed[i - 1].y)) }
        guard let total = lengths.last, total > 1e-8 else { return [] }
        var edge = 1
        return (0..<count).map { i in
            let distance = total * CGFloat(i) / CGFloat(count)
            while edge < lengths.count - 1 && lengths[edge] < distance { edge += 1 }
            let t = (distance - lengths[edge - 1]) / max(1e-8, lengths[edge] - lengths[edge - 1])
            return CGPoint(x: closed[edge - 1].x + (closed[edge].x - closed[edge - 1].x) * t,
                           y: closed[edge - 1].y + (closed[edge].y - closed[edge - 1].y) * t)
        }
    }

    static func aligned(_ points: [CGPoint], to previous: [CGPoint]) -> [CGPoint] {
        guard points.count == previous.count, !points.isEmpty else { return points }
        let offset = points.indices.min { a, b in
            func error(_ offset: Int) -> CGFloat {
                points.indices.reduce(0) { sum, i in
                    let p = points[(i + offset) % points.count], q = previous[i]
                    return sum + pow(p.x - q.x, 2) + pow(p.y - q.y, 2)
                }
            }
            return error(a) < error(b)
        } ?? 0
        return points.indices.map { points[($0 + offset) % points.count] }
    }

    static func aspectFill(image: CGSize, viewport: CGSize) -> CGRect {
        let scale = max(viewport.width / max(1, image.width), viewport.height / max(1, image.height))
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (viewport.width - size.width) / 2, y: (viewport.height - size.height) / 2, width: size.width, height: size.height)
    }
}
