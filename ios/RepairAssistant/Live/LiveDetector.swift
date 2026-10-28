import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

protocol LiveDetector: Sendable {
    func detect(frame: CGImage, concept: String) async throws -> [Segment]
}

struct ProxyLiveDetector: LiveDetector {
    let baseURL: URL
    var session: URLSession = .shared

    func detect(frame: CGImage, concept: String) async throws -> [Segment] {
        struct Body: Encodable { let imageBase64: String; let concept: String }
        struct Response: Decodable { let segments: [Segment] }
        guard ["http", "https"].contains(baseURL.scheme?.lowercased() ?? ""), baseURL.host != nil else { throw APIError.invalidURL }
        let image = LiveImage.scaled(frame, longestSide: 768)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { throw APIError.decoding }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw APIError.decoding }
        var request = URLRequest(url: baseURL.appendingPathComponent("detect"))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try ContractCoding.encoder().encode(Body(imageBase64: (data as Data).base64EncodedString(), concept: concept))
        do {
            let (body, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
            guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
            return try ContractCoding.decoder().decode(Response.self, from: body).segments.filter {
                $0.isDamage && $0.score.isFinite && LiveGeometry.usable($0.polygon)
            }
        } catch is CancellationError { throw CancellationError() }
        catch { throw APIError.from(error) }
    }
}

struct MockLiveDetector: LiveDetector {
    var reference: CGImage?
    var segment: Segment?
    private let registrar = LiveImageRegistrar()

    init(reference: CGImage? = nil, segment: Segment? = nil) {
        self.reference = reference; self.segment = segment
    }

    func detect(frame: CGImage, concept: String) async throws -> [Segment] {
        try await Task.sleep(for: .milliseconds(700))
        var result = segment ?? Segment(id: "live-damage", label: "Riss", kind: .damage, prompt: concept,
                                       mask: SegmentMask(points: [[0.33, 0.47], [0.47, 0.44], [0.66, 0.48], [0.62, 0.53], [0.46, 0.51], [0.34, 0.54]]), score: 0.94)
        if let reference, let transform = await registrar.register(reference: reference, current: frame),
           let polygon = transform.warp(result.polygon) {
            result.mask = SegmentMask(points: polygon.map { [Double($0.x), Double($0.y)] })
        }
        try Task.checkCancellation()
        return [result]
    }
}

struct LiveDetectionResult: Sendable {
    let segments: [Segment]
    let latencyMilliseconds: Int
}

/// The flag stays set across suspension and cancellation until the detector actually returns.
actor LiveDetectionThrottle {
    private var detector: any LiveDetector
    let minimumInterval: TimeInterval
    private var inFlight = false
    private var lastStart: TimeInterval = -.infinity

    init(detector: any LiveDetector, minimumInterval: TimeInterval = 1) {
        self.detector = detector; self.minimumInterval = minimumInterval
    }

    func use(_ detector: any LiveDetector) { self.detector = detector }

    func detect(frame: CGImage, concept: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) async throws -> LiveDetectionResult? {
        guard !inFlight, now - lastStart >= minimumInterval else { return nil }
        try Task.checkCancellation()
        inFlight = true; lastStart = now
        let start = ProcessInfo.processInfo.systemUptime
        defer { inFlight = false }
        let segments = try await detector.detect(frame: frame, concept: concept)
        try Task.checkCancellation()
        return LiveDetectionResult(segments: segments, latencyMilliseconds: Int((ProcessInfo.processInfo.systemUptime - start) * 1000))
    }
}
