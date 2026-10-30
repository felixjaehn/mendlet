import Foundation
import UIKit

struct SavedCase: Codable, Sendable, Identifiable, Hashable {
    var id: String
    var createdAt: Date
    var userNote: String
    var response: AnalyzeResponse
    var shoppingStatus: [String: ItemStatus]
    var currentStep: Int
    var completedSteps: [Int]
    var finished: Bool
    /// Set when the user taps "Start repair" (or "Save for later"): only started cases are projects on Home.
    var started: Bool? = nil
    /// "Save for later" on a pro verdict: the project waits for a professional.
    var parked: Bool? = nil
    var finishedAt: Date? = nil
    /// Demo mode only: which recorded scenario this project replays (its after-preview, recordings).
    var scenario: String? = nil
}

struct RescueEntry: Codable, Sendable, Hashable {
    var caseId: String
    var date: Date
    var garment: String
    var kilograms: Double
}

struct StoreFile: Codable, Sendable {
    var cases: [SavedCase] = []
    var rescues: [RescueEntry] = []
}

@MainActor
@Observable
final class CaseStore {
    static let maxCases = 20
    private(set) var cases: [SavedCase] = []
    private(set) var rescues: [RescueEntry] = []
    private let directory: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("RepairAssistant", isDirectory: true)
        self.directory = base
        try? FileManager.default.createDirectory(at: base.appendingPathComponent("images"), withIntermediateDirectories: true)
        load()
    }

    private var fileURL: URL { directory.appendingPathComponent("store.json") }
    private func imageURL(_ id: String) -> URL { directory.appendingPathComponent("images/\(id).jpg") }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let f = try? dec.decode(StoreFile.self, from: data) { cases = f.cases; rescues = f.rescues }
    }

    private func persist() {
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(StoreFile(cases: cases, rescues: rescues)) { try? data.write(to: fileURL, options: .atomic) }
    }

    func upsert(_ c: SavedCase, image: UIImage? = nil) {
        if let image, let data = ImageResizer.jpegData(image, maxEdge: 1024, quality: 0.8) { try? data.write(to: imageURL(c.id), options: .atomic) }
        cases.removeAll { $0.id == c.id }
        cases.insert(c, at: 0)
        if cases.count > Self.maxCases {
            for old in cases[Self.maxCases...] { try? FileManager.default.removeItem(at: imageURL(old.id)) }
            cases = Array(cases.prefix(Self.maxCases))
        }
        persist()
    }

    func image(for id: String) -> UIImage? { UIImage(contentsOfFile: imageURL(id).path) }
    func savedCase(_ id: String) -> SavedCase? { cases.first { $0.id == id } }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: imageURL(id))
        cases.removeAll { $0.id == id }
        persist()
    }

    func clearHistory() {
        for c in cases { try? FileManager.default.removeItem(at: imageURL(c.id)) }
        cases = []
        persist()
    }

    func recordRescue(caseId: String, garment: String, kilograms: Double) {
        guard !rescues.contains(where: { $0.caseId == caseId }) else { return }
        rescues.append(RescueEntry(caseId: caseId, date: Date(), garment: garment, kilograms: kilograms))
        persist()
    }

    var rescuedCount: Int { rescues.count }
    var rescuedKilograms: Double { rescues.reduce(0) { $0 + $1.kilograms } }
}
