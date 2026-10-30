// Animated dotted orb. SwiftUI Canvas + TimelineView port of the "listening" (wave) and "working" (orbits)
// states of thinking-orbs by Jakub Antalik (MIT), 64 px preset. See THIRD_PARTY_NOTICES.md.
// The geometry below is a hand transcription of the library's engine (core.ts, lattice.ts, orbits.ts);
// ThinkingOrbTests checks it against the library's golden vectors.

import SwiftUI

enum OrbState: Sendable {
    /// Library state "listening": a waveform rolling through a dotted sphere.
    case listening
    /// Library state "working": particles running on tilted orbits.
    case working
}

/// One finished dot in the 64 pt coordinate space, already culled, radius-clamped and z-sorted (far to near).
struct OrbDot: Sendable, Equatable {
    var x: Double, y: Double, z: Double, r: Double
    /// Ink value, 0 = dark. Mirrored on dark substrates at paint time.
    var white: Double
    var a: Double
}

enum OrbEngine {
    static let size = 64.0
    /// Frame time is `elapsed seconds * speed` (the library's preset speed).
    static func speed(_ state: OrbState) -> Double { state == .listening ? 4.388 : 1.885 }
    /// Reduced motion renders one static frame at this time.
    static let staticTime = 0.6

    static func frame(_ state: OrbState, t: Double) -> [OrbDot] {
        state == .listening ? wave(t: t) : orbits(t: t)
    }

    // MARK: Shared primitives (core.ts)

    static func hashD(_ a: Double, _ b: Double) -> Double {
        let h = sin(a * 12.9898 + b * 78.233) * 43758.5453
        return h - h.rounded(.down)
    }

    static func radiusScale(_ size: Double, _ pow: Double) -> Double { Foundation.pow(size / 300, pow) }

    /// Spin + tilt + orthographic projection.
    static func makeProj(yaw: Double, tilt: Double, cx: Double, cy: Double, scale: Double) -> (Double, Double, Double) -> (Double, Double, Double) {
        let st = sin(tilt), ct = cos(tilt), sy = sin(yaw), cyw = cos(yaw)
        return { x, y, z in
            let x1 = x * cyw + z * sy
            let z1 = -x * sy + z * cyw
            let y1 = y * ct - z1 * st
            let z2 = y * st + z1 * ct
            return (cx + x1 * scale, cy - y1 * scale, z2)
        }
    }

    /// Drops invisible marks, clamps radii, sorts far to near (stable).
    static func finalize(_ dots: [OrbDot], rMin: Double) -> [OrbDot] {
        var visible: [(Int, OrbDot)] = []
        for (i, var d) in dots.enumerated() where d.a >= 0.02 {
            d.r = max(rMin, d.r)
            visible.append((i, d))
        }
        visible.sort { $0.1.z != $1.1.z ? $0.1.z < $1.1.z : $0.0 < $1.0 }
        return visible.map(\.1)
    }

    // MARK: Wave, 64 px preset: rings 9, lonDensity 23, rBase 0.6, rDepth 1.7, rsPow 0.6, rMin 0.3

    static func wave(t: Double) -> [OrbDot] {
        let size = Self.size
        let rings = 9, lonDensity = 23.0
        let rBase = 0.6, rDepth = 1.7
        let cx = size / 2, cy = size / 2
        let R = (size / 2) * 0.874
        let pt = makeProj(yaw: t * 0.18, tilt: 0.38, cx: cx, cy: cy, scale: 1)
        let rs = radiusScale(size, 0.6)
        var dots: [OrbDot] = []
        for ri in 0...rings {
            let lat = -Double.pi / 2 + Double(ri) / Double(rings) * Double.pi
            let cosLat = cos(lat), sinLat = sin(lat)
            let w = 0.62 * sin(t * 2.1 - Double(ri) * 0.52) + 0.38 * sin(t * 1.27 + Double(ri) * 0.83)
            let rr = R * (0.88 + 0.105 * w)
            let lonCount = max(1, Int((abs(cosLat) * lonDensity).rounded()))
            for lj in 0..<lonCount {
                let lon = Double(lj) / Double(lonCount) * 2 * Double.pi
                let (px, py, z) = pt(cosLat * cos(lon) * rr, sinLat * rr, cosLat * sin(lon) * rr)
                let depth = (z / R + 1) / 2
                let crest = max(0, w)
                dots.append(OrbDot(x: px, y: py, z: z,
                                   r: (rBase + rDepth * depth) * (1 + 0.4 * crest) * rs,
                                   white: 0.66 - 0.56 * depth - 0.1 * crest, a: 1))
            }
        }
        return finalize(dots, rMin: 0.3)
    }

    // MARK: Orbits, 64 px preset: orbitN 12, ghostN 40, ghostR 0.9, ghostA 0.5, particles 3, partR 1.2, partRDepth 1.6

    static func orbits(t: Double) -> [OrbDot] {
        let size = Self.size
        let orbitN = 12, ghostN = 40, particles = 3
        let ghostR = 0.9, ghostA = 0.5, partR = 1.2, partRDepth = 1.6
        let cx = size / 2, cy = size / 2
        let R = (size / 2) * 0.82
        let pt = makeProj(yaw: t * 0.12, tilt: 0.3, cx: cx, cy: cy, scale: 1)
        let rs = radiusScale(size, 0.6)
        var dots: [OrbDot] = []
        for orb in 0..<orbitN {
            let o = Double(orb)
            let h1 = hashD(o, 1.7), h2 = hashD(o, 5.2), h3 = hashD(o, 8.9)
            let ro = R * (0.45 + 0.52 * h1)
            let th = h1 * 2 * Double.pi
            let phi = acos(2 * h2 - 1)
            let nx = sin(phi) * cos(th), ny = cos(phi), nz = sin(phi) * sin(th)
            var ux = -ny, uy = nx
            let uz = 0.0
            let ul = max(1e-6, (ux * ux + uy * uy).squareRoot())
            ux /= ul; uy /= ul
            let vx = ny * uz - nz * uy
            let vy = nz * ux - nx * uz
            let vz = nx * uy - ny * ux
            let speed = (0.25 + 0.55 * h3) * (h3 > 0.5 ? 1 : -1)
            func point(_ a: Double) -> (Double, Double, Double) {
                pt((ux * cos(a) + vx * sin(a)) * ro, (uy * cos(a) + vy * sin(a)) * ro, (uz * cos(a) + vz * sin(a)) * ro)
            }
            for k in 0..<ghostN {
                let (px, py, z) = point(Double(k) / Double(ghostN) * 2 * Double.pi)
                let depth = (z / ro + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: z, r: ghostR * rs, white: 0.72, a: ghostA * (0.4 + 0.6 * depth)))
            }
            for m in 0..<particles {
                let a = t * speed + Double(m) / Double(particles) * 2 * Double.pi + h2 * 6
                let (px, py, z) = point(a)
                let depth = (z / ro + 1) / 2
                dots.append(OrbDot(x: px, y: py, z: z, r: (partR + partRDepth * depth) * rs, white: 0.3 - 0.22 * depth, a: 1))
            }
        }
        return finalize(dots, rMin: 0.3)
    }
}

/// Dotted orb, painted exactly like the library: matte grayscale dots, z-sorted far to near. On the dark glass the ink
/// value is mirrored (1 - white) so near dots read bright (core.ts `paint`). No colour, no glow: the original look.
struct ThinkingOrb: View {
    var state: OrbState = .listening
    /// Rendered edge length in points (the 64 pt geometry is scaled to it).
    var size: CGFloat = 44
    /// Speed multiplier on the library preset (1 = as shipped).
    var tempo: Double = 1
    /// Microphone level 0...1: the orb breathes slightly with the voice.
    var level: Float = 0
    /// Dark substrate (the voice glass is dark in both appearances).
    var dark = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                orb(t: OrbEngine.staticTime)
            } else {
                TimelineView(.animation) { tl in
                    orb(t: tl.date.timeIntervalSinceReferenceDate * OrbEngine.speed(state) * tempo)
                }
            }
        }
        .frame(width: size, height: size)
        .scaleEffect(1 + 0.08 * CGFloat(level))
        .animation(reduceMotion ? nil : .interpolatingSpring(stiffness: 220, damping: 18), value: level)
        .accessibilityHidden(true)
    }

    private func orb(t: Double) -> some View {
        Canvas { ctx, canvasSize in
            let k = canvasSize.width / OrbEngine.size
            for d in OrbEngine.frame(state, t: t) {
                let w = min(1, max(0, d.white))
                let g = dark ? 1 - w : w
                let rect = CGRect(x: (d.x - d.r) * k, y: (d.y - d.r) * k, width: d.r * 2 * k, height: d.r * 2 * k)
                ctx.fill(Path(ellipseIn: rect), with: .color(Color(white: g).opacity(d.a)))
            }
        }
    }
}
