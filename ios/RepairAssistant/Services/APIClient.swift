import Foundation

enum AnalysisStage: String, CaseIterable, Sendable, Codable {
    case classify, segment, diagnose, plan
}

enum AnalyzeEvent: Sendable {
    case progress(stage: AnalysisStage, label: String, segments: [Segment]?)
    case result(AnalyzeResponse)
    /// Spark fallback: no SAM text hit, Muse Spark localizes the damage, SAM segments with the box.
    case grounding(label: String)
}

enum APIError: LocalizedError, Sendable, Equatable {
    case invalidURL
    case http(Int)
    case server(String)
    case timeout
    case unreachable
    case emptyResult
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Die Server-Adresse ist ungültig. Prüfe die Einstellungen."
        case .http(let c): "Der Server meldet einen Fehler (\(c)). Bitte versuche es erneut."
        case .server(let m): m.isEmpty ? "Die Analyse ist fehlgeschlagen." : m
        case .timeout: "Die Analyse dauert zu lange. Bitte versuche es erneut."
        case .unreachable: "Der Server antwortet nicht. Läuft der Proxy?"
        case .emptyResult: "Ich finde die Stelle nicht sicher. Mach ein schärferes Foto oder versuche es noch einmal."
        case .decoding: "Die Antwort des Servers war unlesbar. Bitte versuche es erneut."
        }
    }

    static func from(_ error: Error) -> APIError {
        if let e = error as? APIError { return e }
        if let u = error as? URLError {
            switch u.code {
            case .timedOut: return .timeout
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .dnsLookupFailed: return .unreachable
            default: return .unreachable
            }
        }
        if error is DecodingError { return .decoding }
        return .server(error.localizedDescription)
    }
}

protocol AnalysisService: Sendable {
    func analyze(_ request: AnalyzeRequest) -> AsyncThrowingStream<AnalyzeEvent, Error>
    func stepHelp(_ request: StepHelpRequest) async throws -> StepHelpResponse
    func transcribe(fileURL: URL) async throws -> String
    func refine(_ request: RefineRequest) async throws -> Segment
    func track(_ request: TrackRequest) async throws -> TrackResponse
    func afterPreview(_ request: AfterPreviewRequest) async throws -> AfterPreviewResponse
}

// MARK: - SSE

struct SSEMessage: Equatable, Sendable {
    var event: String
    var data: String
}

/// Line-based Server-Sent-Events parser. Tolerates missing blank separator lines.
struct SSEParser: Sendable {
    private var event = "message"
    private var dataLines: [String] = []

    mutating func feed(_ rawLine: String) -> [SSEMessage] {
        let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty { return flush() }
        if line.hasPrefix(":") { return [] }
        let (field, value): (String, String) = {
            guard let idx = line.firstIndex(of: ":") else { return (line, "") }
            var v = String(line[line.index(after: idx)...])
            if v.hasPrefix(" ") { v.removeFirst() }
            return (String(line[..<idx]), v)
        }()
        switch field {
        case "event":
            let out = dataLines.isEmpty ? [] : flush()
            event = value
            return out
        case "data":
            dataLines.append(value)
            return []
        default:
            return []
        }
    }

    mutating func finish() -> [SSEMessage] { flush() }

    private mutating func flush() -> [SSEMessage] {
        defer { event = "message"; dataLines = [] }
        guard !dataLines.isEmpty else { return [] }
        return [SSEMessage(event: event, data: dataLines.joined(separator: "\n"))]
    }
}

enum SSEDecoder {
    struct ProgressPayload: Decodable {
        var stage: String
        var label: String?
        var segments: [Segment]?
    }
    struct GroundingPayload: Decodable { var label: String? }
    struct ErrorPayload: Decodable { var message: String? }

    /// Returns nil for events to ignore.
    static func decode(_ m: SSEMessage) throws -> AnalyzeEvent? {
        let data = Data(m.data.utf8)
        let decoder = ContractCoding.decoder()
        switch m.event {
        case "progress":
            guard let p = try? decoder.decode(ProgressPayload.self, from: data),
                  let stage = AnalysisStage(rawValue: p.stage) else { return nil }
            return .progress(stage: stage, label: p.label ?? "", segments: p.segments)
        case "result":
            do { return .result(try decoder.decode(AnalyzeResponse.self, from: data)) }
            catch { throw APIError.decoding }
        case "grounding":
            let g = try? decoder.decode(GroundingPayload.self, from: data)
            return .grounding(label: g?.label ?? "Schadstelle genauer lokalisieren")
        case "error":
            let e = try? decoder.decode(ErrorPayload.self, from: data)
            throw APIError.server(e?.message ?? "")
        default:
            return nil
        }
    }
}

private struct ErrorEnvelope: Decodable {
    struct Inner: Decodable { var code: String?; var message: String? }
    var error: Inner?
}

// MARK: - Live client

struct LiveAPIClient: AnalysisService {
    let baseURL: URL
    let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 180
        self.session = URLSession(configuration: cfg)
    }

    private func url(_ path: String) -> URL { baseURL.appendingPathComponent(path) }

    func health() async -> Bool {
        var req = URLRequest(url: url("health"))
        req.timeoutInterval = 4
        guard let (_, resp) = try? await session.data(for: req), let h = resp as? HTTPURLResponse else { return false }
        return h.statusCode == 200
    }

    func analyze(_ request: AnalyzeRequest) -> AsyncThrowingStream<AnalyzeEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: url("analyze"))
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                    req.httpBody = try ContractCoding.encoder().encode(request)
                    let (bytes, response) = try await session.bytes(for: req)
                    guard let http = response as? HTTPURLResponse else { throw APIError.unreachable }
                    guard http.statusCode == 200 else { throw APIError.http(http.statusCode) }
                    let type = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
                    if type.contains("json") {
                        var data = Data()
                        for try await b in bytes { data.append(b) }
                        let r = try ContractCoding.decoder().decode(AnalyzeResponse.self, from: data)
                        continuation.yield(.result(r))
                        continuation.finish()
                        return
                    }
                    var parser = SSEParser()
                    var line: [UInt8] = []
                    func handle(_ msgs: [SSEMessage]) throws {
                        for m in msgs { if let e = try SSEDecoder.decode(m) { continuation.yield(e) } }
                    }
                    for try await byte in bytes {
                        if byte == 0x0A {
                            let s = String(decoding: line, as: UTF8.self)
                            line.removeAll(keepingCapacity: true)
                            try handle(parser.feed(s))
                        } else {
                            line.append(byte)
                        }
                    }
                    if !line.isEmpty { try handle(parser.feed(String(decoding: line, as: UTF8.self))) }
                    try handle(parser.finish())
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: APIError.from(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func stepHelp(_ request: StepHelpRequest) async throws -> StepHelpResponse {
        var req = URLRequest(url: url("step-help"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try ContractCoding.encoder().encode(request)
        do {
            let (data, resp) = try await session.data(for: req)
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw APIError.http(h.statusCode) }
            return try ContractCoding.decoder().decode(StepHelpResponse.self, from: data)
        } catch { throw APIError.from(error) }
    }

    private func postJSON<Body: Encodable, Out: Decodable>(_ path: String, _ body: Body, as: Out.Type, timeout: TimeInterval = 120) async throws -> Out {
        var req = URLRequest(url: url(path))
        req.httpMethod = "POST"
        req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try ContractCoding.encoder().encode(body)
        do {
            let (data, resp) = try await session.data(for: req)
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 {
                if let m = (try? JSONDecoder().decode(ErrorEnvelope.self, from: data))?.error?.message, !m.isEmpty { throw APIError.server(m) }
                throw APIError.http(h.statusCode)
            }
            return try ContractCoding.decoder().decode(Out.self, from: data)
        } catch { throw APIError.from(error) }
    }

    func refine(_ request: RefineRequest) async throws -> Segment {
        try await postJSON("refine", request, as: Segment.self)
    }

    func track(_ request: TrackRequest) async throws -> TrackResponse {
        try await postJSON("track", request, as: TrackResponse.self, timeout: 180)
    }

    func afterPreview(_ request: AfterPreviewRequest) async throws -> AfterPreviewResponse {
        try await postJSON("after-preview", request, as: AfterPreviewResponse.self)
    }

    func transcribe(fileURL: URL) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url("transcribe"))
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let audio = try Data(contentsOf: fileURL)
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        req.httpBody = body
        struct T: Decodable { var text: String }
        do {
            let (data, resp) = try await session.data(for: req)
            if let h = resp as? HTTPURLResponse, h.statusCode != 200 { throw APIError.http(h.statusCode) }
            return try JSONDecoder().decode(T.self, from: data).text
        } catch { throw APIError.from(error) }
    }
}
