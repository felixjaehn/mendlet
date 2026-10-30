import Foundation
import CoreGraphics

// MARK: - Tolerant enums

protocol TolerantEnum: RawRepresentable, Codable, Sendable, Hashable, CaseIterable where RawValue == String {
    static var fallback: Self { get }
}

extension TolerantEnum {
    static func decodeTolerant(_ decoder: Decoder) throws -> Self {
        let c = try decoder.singleValueContainer()
        let raw = (try? c.decode(String.self)) ?? ""
        return Self(rawValue: raw) ?? Self.fallback
    }
    func encodeRaw(_ encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

enum Category: String, TolerantEnum {
    case textile, shoe
    case lowVoltageElectronics = "low_voltage_electronics"
    case unsupported
    static var fallback: Category { .unsupported }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }
}

enum RiskLevel: String, TolerantEnum {
    case allowed
    case warnOnly = "warn_only"
    case professional
    static var fallback: RiskLevel { .warnOnly }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }
}

enum SegmentKind: String, TolerantEnum {
    case part, damage
    static var fallback: SegmentKind { .part }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }
}

enum Recommendation: String, TolerantEnum {
    case repairSelf = "repair_self"
    case repairPro = "repair_pro"
    case replace
    static var fallback: Recommendation { .repairPro }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }
}

enum Effort: String, TolerantEnum {
    case low, medium, high
    static var fallback: Effort { .medium }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }
}

enum ItemKind: String, TolerantEnum {
    case material, tool
    static var fallback: ItemKind { .material }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }
}

enum QuestionType: String, TolerantEnum {
    case photo
    case voiceOrText = "voice_or_text"
    case choice
    static var fallback: QuestionType { .voiceOrText }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }
}

enum Purpose: String, TolerantEnum {
    case label, closeup, other
    static var fallback: Purpose { .other }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }
}

enum OverlayType: String, TolerantEnum {
    case stitchPath = "stitch_path"
    case solder
    case highlight
    static var fallback: OverlayType { .highlight }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }
}

enum StitchType: String, TolerantEnum {
    case ladderStitch = "ladder_stitch"
    case runningStitch = "running_stitch"
    case darning
    case whipStitch = "whip_stitch"
    static var fallback: StitchType { .runningStitch }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }

}

// MARK: - Segments

struct MaskRing: Codable, Sendable, Hashable {
    var points: [[Double]]
    var hole: Bool
    var cgPoints: [CGPoint] {
        points.compactMap { $0.count >= 2 && $0[0].isFinite && $0[1].isFinite ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }
    private enum CodingKeys: String, CodingKey { case points, hole }
    init(points: [[Double]], hole: Bool = false) { self.points = points; self.hole = hole }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = (try? c.decode([[Double]].self, forKey: .points)) ?? []
        hole = (try? c.decode(Bool.self, forKey: .hole)) ?? false
    }
}

struct SegmentMask: Codable, Sendable, Hashable {
    var points: [[Double]]
    /// Optional multi-ring mask (outer rings and holes, drawn even-odd). `points` keeps working on its own.
    var rings: [MaskRing]
    var cgPoints: [CGPoint] {
        points.compactMap { $0.count >= 2 && $0[0].isFinite && $0[1].isFinite ? CGPoint(x: $0[0], y: $0[1]) : nil }
    }
    private enum CodingKeys: String, CodingKey { case points, rings }
    init(points: [[Double]], rings: [MaskRing] = []) { self.points = points; self.rings = rings }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        points = (try? c.decode([[Double]].self, forKey: .points)) ?? []
        rings = (try? c.decode([MaskRing].self, forKey: .rings)) ?? []
    }
}

enum SegmentSource: String, Codable, Sendable, Hashable {
    case text, grounding, tap
    var badge: String { self == .grounding ? "Spark → SAM" : "SAM 3.1" }
}

struct Segment: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var label: String
    var kind: SegmentKind
    var prompt: String
    var box: [Double]?
    var mask: SegmentMask?
    var score: Double
    var source: SegmentSource?
    /// Solder pads: "+" or "-" (read from the silkscreen). Nil for everything else.
    var polarity: String?

    private enum CodingKeys: String, CodingKey { case id, label, kind, prompt, box, mask, score, source, polarity }

    init(id: String, label: String, kind: SegmentKind, prompt: String = "", box: [Double]? = nil, mask: SegmentMask? = nil, score: Double = 0, source: SegmentSource? = nil, polarity: String? = nil) {
        self.id = id; self.label = label; self.kind = kind; self.prompt = prompt
        self.box = box; self.mask = mask; self.score = score; self.source = source; self.polarity = Self.normalize(polarity)
    }

    /// Accepts "+", "-", "−", "plus", "minus"; anything else is nil.
    static func normalize(_ raw: String?) -> String? {
        switch raw?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "+", "plus": "+"
        case "-", "−", "–", "minus": "-"
        default: nil
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        label = (try? c.decode(String.self, forKey: .label)) ?? tr("Bereich")
        kind = (try? c.decode(SegmentKind.self, forKey: .kind)) ?? .part
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        box = try? c.decode([Double].self, forKey: .box)
        mask = (try? c.decodeIfPresent(SegmentMask.self, forKey: .mask)) ?? nil
        score = (try? c.decode(Double.self, forKey: .score)) ?? 0
        source = (try? c.decodeIfPresent(SegmentSource.self, forKey: .source)) ?? nil
        polarity = Self.normalize((try? c.decodeIfPresent(String.self, forKey: .polarity)) ?? nil)
    }

    /// Normalized box (0..1) or nil.
    var normalizedBox: CGRect? {
        guard let b = box, b.count >= 4, b.allSatisfy({ $0.isFinite }) else { return nil }
        return CGRect(x: b[0], y: b[1], width: max(0, b[2]), height: max(0, b[3]))
    }

    /// Normalized polygon or empty (then use the box).
    var polygon: [CGPoint] {
        let p = mask?.cgPoints ?? []
        if p.count >= 3 { return p }
        return mask?.rings.first(where: { !$0.hole && $0.cgPoints.count >= 3 })?.cgPoints ?? []
    }

    /// All drawable rings (normalized): `mask.rings` if present, else the single `mask.points` polygon.
    var ringPolygons: [(points: [CGPoint], hole: Bool)] {
        let r = (mask?.rings ?? []).map { (points: $0.cgPoints, hole: $0.hole) }.filter { $0.points.count >= 3 }
        if !r.isEmpty { return r }
        let p = polygon
        return p.count >= 3 ? [(p, false)] : []
    }

    /// Normalized bounds of the mask (outer rings) or the box.
    var normalizedBounds: CGRect? {
        let pts = ringPolygons.filter { !$0.hole }.flatMap(\.points)
        guard let f = pts.first else { return normalizedBox }
        return pts.reduce(CGRect(origin: f, size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    var isDamage: Bool { kind == .damage }
}

// MARK: - Diagnosis

struct FollowUpQuestion: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var type: QuestionType
    var prompt: String
    var purpose: Purpose
    var options: [String]

    private enum CodingKeys: String, CodingKey { case id, type, prompt, purpose, options }
    init(id: String, type: QuestionType, prompt: String, purpose: Purpose = .other, options: [String] = []) {
        self.id = id; self.type = type; self.prompt = prompt; self.purpose = purpose; self.options = options
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        type = (try? c.decode(QuestionType.self, forKey: .type)) ?? .voiceOrText
        prompt = (try? c.decode(String.self, forKey: .prompt)) ?? ""
        purpose = (try? c.decode(Purpose.self, forKey: .purpose)) ?? .other
        options = (try? c.decode([String].self, forKey: .options)) ?? []
    }
}

struct LabelInfo: Codable, Sendable, Hashable {
    var materials: [String]
    var care: [String]
    private enum CodingKeys: String, CodingKey { case materials, care }
    init(materials: [String] = [], care: [String] = []) { self.materials = materials; self.care = care }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        materials = (try? c.decode([String].self, forKey: .materials)) ?? []
        care = (try? c.decode([String].self, forKey: .care)) ?? []
    }
}

struct Diagnosis: Codable, Sendable, Hashable {
    var summary: String
    var likelyCauses: [String]
    var confidence: Double
    var evidenceSegmentIds: [String]
    var needsMoreInfo: Bool
    var followUpQuestions: [FollowUpQuestion]
    var labelInfo: LabelInfo?

    static let empty = Diagnosis(summary: "", likelyCauses: [], confidence: 0, evidenceSegmentIds: [], needsMoreInfo: false, followUpQuestions: [], labelInfo: nil)

    private enum CodingKeys: String, CodingKey {
        case summary, likelyCauses, confidence, evidenceSegmentIds, needsMoreInfo, followUpQuestions, labelInfo
    }
    init(summary: String, likelyCauses: [String], confidence: Double, evidenceSegmentIds: [String], needsMoreInfo: Bool, followUpQuestions: [FollowUpQuestion], labelInfo: LabelInfo?) {
        self.summary = summary; self.likelyCauses = likelyCauses
        self.confidence = min(1, max(0, confidence)); self.evidenceSegmentIds = evidenceSegmentIds
        self.needsMoreInfo = needsMoreInfo; self.followUpQuestions = followUpQuestions; self.labelInfo = labelInfo
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        likelyCauses = (try? c.decode([String].self, forKey: .likelyCauses)) ?? []
        let conf = (try? c.decode(Double.self, forKey: .confidence)) ?? 0
        confidence = conf.isFinite ? min(1, max(0, conf)) : 0
        evidenceSegmentIds = (try? c.decode([String].self, forKey: .evidenceSegmentIds)) ?? []
        needsMoreInfo = (try? c.decode(Bool.self, forKey: .needsMoreInfo)) ?? false
        followUpQuestions = Array(((try? c.decode([FollowUpQuestion].self, forKey: .followUpQuestions)) ?? []).prefix(3))
        labelInfo = (try? c.decodeIfPresent(LabelInfo.self, forKey: .labelInfo)) ?? nil
    }
}

// MARK: - Decision

/// Replace only: what to do with the old item (upcycle, recycle, donate).
struct SecondLife: Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable { case upcycle, recycle, donate }
    var kind: Kind
    var title: String
    var text: String

}

struct Decision: Codable, Sendable, Hashable {
    var recommendation: Recommendation
    var reasoning: String
    var effort: Effort
    var timeMinutes: [Int]
    var costEur: [Double]
    var estimateNote: String
    var secondLife: [SecondLife] = []

    private enum CodingKeys: String, CodingKey { case recommendation, reasoning, effort, timeMinutes, costEur, estimateNote, secondLife }
    init(recommendation: Recommendation, reasoning: String, effort: Effort, timeMinutes: [Int], costEur: [Double], estimateNote: String = "Schätzung") {
        self.recommendation = recommendation; self.reasoning = reasoning; self.effort = effort
        self.timeMinutes = timeMinutes; self.costEur = costEur; self.estimateNote = estimateNote
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        recommendation = (try? c.decode(Recommendation.self, forKey: .recommendation)) ?? .repairPro
        reasoning = (try? c.decode(String.self, forKey: .reasoning)) ?? ""
        effort = (try? c.decode(Effort.self, forKey: .effort)) ?? .medium
        if let d = try? c.decode([Double].self, forKey: .timeMinutes) { timeMinutes = d.filter { $0.isFinite }.map { Int($0) } } else { timeMinutes = [] }
        costEur = (try? c.decode([Double].self, forKey: .costEur))?.filter { $0.isFinite } ?? []
        let note = (try? c.decode(String.self, forKey: .estimateNote)) ?? ""
        estimateNote = note.isEmpty ? "Schätzung" : note
        secondLife = (try? c.decode([SecondLife].self, forKey: .secondLife)) ?? []
    }
}

// MARK: - Shopping & guide

struct ShoppingItem: Codable, Sendable, Hashable, Identifiable {
    var id: String
    var name: String
    var kind: ItemKind
    var quantity: String
    var required: Bool
    var searchTerm: String
    var householdAlternative: String?

    private enum CodingKeys: String, CodingKey { case id, name, kind, quantity, required, searchTerm, householdAlternative }
    init(id: String, name: String, kind: ItemKind, quantity: String = "", required: Bool = true, searchTerm: String = "", householdAlternative: String? = nil) {
        self.id = id; self.name = name; self.kind = kind; self.quantity = quantity
        self.required = required; self.searchTerm = searchTerm; self.householdAlternative = householdAlternative
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decode(String.self, forKey: .name)) ?? tr("Artikel")
        kind = (try? c.decode(ItemKind.self, forKey: .kind)) ?? .material
        quantity = (try? c.decode(String.self, forKey: .quantity)) ?? ""
        required = (try? c.decode(Bool.self, forKey: .required)) ?? true
        searchTerm = (try? c.decode(String.self, forKey: .searchTerm)) ?? ""
        householdAlternative = (try? c.decodeIfPresent(String.self, forKey: .householdAlternative)) ?? nil
    }
}

struct Overlay: Codable, Sendable, Hashable {
    var type: OverlayType
    var stitchType: StitchType?
    var segmentId: String?
    /// Solder overlay: bare wire end -> pad, held for `holdSeconds`.
    var fromSegmentId: String?
    var toSegmentId: String?
    var holdSeconds: Double?
    private enum CodingKeys: String, CodingKey { case type, stitchType, segmentId, fromSegmentId, toSegmentId, holdSeconds }
    init(type: OverlayType, stitchType: StitchType? = nil, segmentId: String? = nil, fromSegmentId: String? = nil, toSegmentId: String? = nil, holdSeconds: Double? = nil) {
        self.type = type; self.stitchType = stitchType; self.segmentId = segmentId
        self.fromSegmentId = fromSegmentId; self.toSegmentId = toSegmentId; self.holdSeconds = holdSeconds
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(OverlayType.self, forKey: .type)) ?? .highlight
        stitchType = (try? c.decodeIfPresent(StitchType.self, forKey: .stitchType)) ?? nil
        segmentId = (try? c.decodeIfPresent(String.self, forKey: .segmentId)) ?? nil
        fromSegmentId = (try? c.decodeIfPresent(String.self, forKey: .fromSegmentId)) ?? nil
        toSegmentId = (try? c.decodeIfPresent(String.self, forKey: .toSegmentId)) ?? nil
        holdSeconds = (try? c.decodeIfPresent(Double.self, forKey: .holdSeconds)) ?? nil
    }
}

struct GuideStep: Codable, Sendable, Hashable, Identifiable {
    var n: Int
    var title: String
    var text: String
    var commonMistake: String?
    var safetyCritical: Bool
    var requiresConfirmation: Bool
    var segmentIds: [String]
    var usesItems: [String]
    var overlay: Overlay?

    var id: Int { n }
    var needsConfirmation: Bool { safetyCritical || requiresConfirmation }

    private enum CodingKeys: String, CodingKey { case n, title, text, commonMistake, safetyCritical, requiresConfirmation, segmentIds, usesItems, overlay }
    init(n: Int, title: String, text: String, commonMistake: String? = nil, safetyCritical: Bool = false, requiresConfirmation: Bool = false, segmentIds: [String] = [], usesItems: [String] = [], overlay: Overlay? = nil) {
        self.n = n; self.title = title; self.text = text; self.commonMistake = commonMistake
        self.safetyCritical = safetyCritical; self.requiresConfirmation = requiresConfirmation
        self.segmentIds = segmentIds; self.usesItems = usesItems; self.overlay = overlay
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = (try? c.decode(Int.self, forKey: .n)) ?? 0
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        text = (try? c.decode(String.self, forKey: .text)) ?? ""
        commonMistake = (try? c.decodeIfPresent(String.self, forKey: .commonMistake)) ?? nil
        safetyCritical = (try? c.decode(Bool.self, forKey: .safetyCritical)) ?? false
        requiresConfirmation = (try? c.decode(Bool.self, forKey: .requiresConfirmation)) ?? false
        segmentIds = (try? c.decode([String].self, forKey: .segmentIds)) ?? []
        usesItems = (try? c.decode([String].self, forKey: .usesItems)) ?? []
        overlay = (try? c.decodeIfPresent(Overlay.self, forKey: .overlay)) ?? nil
    }
}

struct Guide: Codable, Sendable, Hashable {
    var steps: [GuideStep]
    static let empty = Guide(steps: [])
    private enum CodingKeys: String, CodingKey { case steps }
    init(steps: [GuideStep]) { self.steps = steps }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        steps = (try? c.decode([GuideStep].self, forKey: .steps)) ?? []
    }
}

struct Safety: Codable, Sendable, Hashable {
    var blocked: Bool
    var reason: String?
    private enum CodingKeys: String, CodingKey { case blocked, reason }
    init(blocked: Bool = false, reason: String? = nil) { self.blocked = blocked; self.reason = reason }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blocked = (try? c.decode(Bool.self, forKey: .blocked)) ?? false
        reason = (try? c.decodeIfPresent(String.self, forKey: .reason)) ?? nil
    }
}

// MARK: - Response

struct AnalyzeResponse: Codable, Sendable, Hashable {
    var caseId: String
    var category: Category
    var riskLevel: RiskLevel
    var safety: Safety
    var segments: [Segment]
    var diagnosis: Diagnosis
    var decision: Decision?
    var shoppingList: [ShoppingItem]
    var guide: Guide
    /// Optional: number of emitted damage segments per prompt (e.g. ["tear": 2]).
    var instances: [String: Int]?

    private enum CodingKeys: String, CodingKey { case caseId, category, riskLevel, safety, segments, diagnosis, decision, shoppingList, guide, instances }

    init(caseId: String = UUID().uuidString, category: Category, riskLevel: RiskLevel, safety: Safety = Safety(), segments: [Segment] = [], diagnosis: Diagnosis = .empty, decision: Decision? = nil, shoppingList: [ShoppingItem] = [], guide: Guide = .empty, instances: [String: Int]? = nil) {
        self.instances = instances
        self.caseId = caseId; self.category = category; self.riskLevel = riskLevel; self.safety = safety
        self.segments = segments; self.diagnosis = diagnosis; self.decision = decision
        self.shoppingList = shoppingList; self.guide = guide
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        caseId = (try? c.decode(String.self, forKey: .caseId)) ?? UUID().uuidString
        category = (try? c.decode(Category.self, forKey: .category)) ?? .unsupported
        riskLevel = (try? c.decode(RiskLevel.self, forKey: .riskLevel)) ?? .warnOnly
        safety = (try? c.decode(Safety.self, forKey: .safety)) ?? Safety()
        segments = (try? c.decode([Segment].self, forKey: .segments)) ?? []
        diagnosis = (try? c.decode(Diagnosis.self, forKey: .diagnosis)) ?? .empty
        decision = (try? c.decodeIfPresent(Decision.self, forKey: .decision)) ?? nil
        shoppingList = (try? c.decode([ShoppingItem].self, forKey: .shoppingList)) ?? []
        guide = (try? c.decode(Guide.self, forKey: .guide)) ?? .empty
        instances = (try? c.decodeIfPresent([String: Int].self, forKey: .instances)) ?? nil
    }

    func segment(_ id: String) -> Segment? { segments.first { $0.id == id } }
}

// MARK: - Requests

struct ExtraImage: Codable, Sendable, Hashable {
    var purpose: Purpose
    var imageBase64: String
}

struct AnswerPayload: Codable, Sendable, Hashable {
    var questionId: String
    var text: String
}

struct AnalyzeRequest: Codable, Sendable {
    var imageBase64: String
    var userNote: String
    var extraImages: [ExtraImage] = []
    var answers: [AnswerPayload] = []
    var locale: String = "de"
    var mockScenario: String?
    /// Precision mode: Muse Wonder agent verifies every damage mask (nil = server default).
    var agent: Bool?
}

struct StepRef: Codable, Sendable, Hashable {
    var n: Int
    var title: String
    var text: String
}

struct StepHelpRequest: Codable, Sendable {
    var step: StepRef
    var diagnosisSummary: String
    var riskLevel: RiskLevel
    var issueText: String
    var imageBase64: String?
    var locale: String = Lang.apiCode
}

struct StepHelpResponse: Codable, Sendable, Hashable {
    var answer: String
    var retryHint: String?
    var escalate: Bool
    private enum CodingKeys: String, CodingKey { case answer, retryHint, escalate }
    init(answer: String, retryHint: String? = nil, escalate: Bool = false) {
        self.answer = answer; self.retryHint = retryHint; self.escalate = escalate
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answer = (try? c.decode(String.self, forKey: .answer)) ?? ""
        retryHint = (try? c.decodeIfPresent(String.self, forKey: .retryHint)) ?? nil
        escalate = (try? c.decode(Bool.self, forKey: .escalate)) ?? false
    }
}

// MARK: - /refine, /track, /after-preview

struct RefinePoint: Codable, Sendable, Hashable {
    var x: Double
    var y: Double
    /// "positive" or "negative"
    var label: String
}

struct RefineRequest: Codable, Sendable {
    var imageBase64: String
    var points: [RefinePoint] = []
    /// [x, y, w, h] normalized to the EXIF-oriented photo.
    var box: [Double]?
    var label: String
    var locale: String = Lang.apiCode
}

struct TrackRequest: Codable, Sendable {
    var videoBase64: String
    var concept: String
    var locale: String = Lang.apiCode
}

/// A segment inside a tracked frame; carries SAM's decimal `object_id` as string.
struct TrackedSegment: Codable, Sendable, Hashable, Identifiable {
    var segment: Segment
    var objectId: String
    var id: String { segment.id }

    private enum ExtraKeys: String, CodingKey { case objectId }
    init(segment: Segment, objectId: String) { self.segment = segment; self.objectId = objectId }
    init(from decoder: Decoder) throws {
        segment = try Segment(from: decoder)
        let c = try decoder.container(keyedBy: ExtraKeys.self)
        if let s = try? c.decode(String.self, forKey: .objectId) { objectId = s }
        else if let i = try? c.decode(Int.self, forKey: .objectId) { objectId = String(i) }
        else { objectId = "" }
    }
    func encode(to encoder: Encoder) throws {
        try segment.encode(to: encoder)
        var c = encoder.container(keyedBy: ExtraKeys.self)
        try c.encode(objectId, forKey: .objectId)
    }
}

struct TrackFrame: Codable, Sendable, Hashable {
    var index: Int
    var segments: [TrackedSegment]
    private enum CodingKeys: String, CodingKey { case index, segments }
    init(index: Int, segments: [TrackedSegment]) { self.index = index; self.segments = segments }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        index = (try? c.decode(Int.self, forKey: .index)) ?? 0
        segments = (try? c.decode([TrackedSegment].self, forKey: .segments)) ?? []
    }
}

struct TrackResponse: Codable, Sendable, Hashable {
    var frames: [TrackFrame]
    var fps: Double?
    private enum CodingKeys: String, CodingKey { case frames, fps }
    init(frames: [TrackFrame], fps: Double? = nil) { self.frames = frames; self.fps = fps }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        frames = (try? c.decode([TrackFrame].self, forKey: .frames)) ?? []
        fps = (try? c.decodeIfPresent(Double.self, forKey: .fps)) ?? nil
    }
}

struct AfterPreviewRequest: Codable, Sendable {
    var imageBase64: String
    var diagnosisSummary: String
    /// Textile: stitch type of the first stitch_path step. Shoes: nil (nil fields are omitted when encoding).
    var stitchType: StitchType?
    /// Optional: "shoe" for glued soles.
    var category: String?
    var repairHint: String?
    /// /step-image only: the guide step whose result the picture shows.
    var stepTitle: String?
    var stepText: String?
    var locale: String = Lang.apiCode
}

struct AfterPreviewResponse: Codable, Sendable, Hashable {
    /// Plain base64 image (PNG/JPEG/WebP), no data URL.
    var imageBase64: String
    var model: String
    var imageData: Data? { Data(base64Encoded: imageBase64, options: .ignoreUnknownCharacters) }
}

// MARK: - Agent trace (SSE `agent_step`)

enum AgentStatus: String, TolerantEnum {
    case done, failed
    static var fallback: AgentStatus { .done }
    init(from decoder: Decoder) throws { self = try Self.decodeTolerant(decoder) }
    func encode(to encoder: Encoder) throws { try encodeRaw(encoder) }
}

/// One tool call of the analysis agent: `data: {"n":1,"tool":"classify","label":"…","model":"Muse Spark","status":"done","ms":2800}`.
struct AgentStep: Codable, Sendable, Hashable, Identifiable {
    var n: Int
    var tool: String
    var label: String
    var model: String
    var status: AgentStatus
    var ms: Int
    var id: Int { n }

    private enum CodingKeys: String, CodingKey { case n, tool, label, model, status, ms }
    init(n: Int, tool: String = "", label: String, model: String, status: AgentStatus = .done, ms: Int = 0) {
        self.n = n; self.tool = tool; self.label = label; self.model = model; self.status = status; self.ms = max(0, ms)
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        n = (try? c.decode(Int.self, forKey: .n)) ?? 0
        tool = (try? c.decode(String.self, forKey: .tool)) ?? ""
        label = (try? c.decode(String.self, forKey: .label)) ?? ""
        model = (try? c.decode(String.self, forKey: .model)) ?? ""
        status = (try? c.decode(AgentStatus.self, forKey: .status)) ?? .done
        ms = max(0, (try? c.decode(Int.self, forKey: .ms)) ?? 0)
    }
}

enum ContractCoding {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }
}
