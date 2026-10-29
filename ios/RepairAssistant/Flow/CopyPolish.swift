import Foundation

/// Display-only text polish for model copy (docs/design/REDESIGN-SPEC.md 5.3). Never changes what is stored or sent;
/// German text is returned untouched. No other rewriting happens on the device.
enum CopyPolish {
    private static let hedges = ["presumably ", "assumed ", "likely ", "probably ", "apparently "]

    static func sentences(_ text: String) -> [String] {
        var out: [String] = [], cur = ""
        let chars = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var i = 0
        while i < chars.count {
            let c = chars[i]
            cur.append(c)
            if ".!?".contains(c), i + 1 < chars.count, chars[i + 1].isWhitespace {
                out.append(cur.trimmingCharacters(in: .whitespaces)); cur = ""
            }
            i += 1
        }
        let rest = cur.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    /// One sentence: hedges removed, first letter capital, final period. Returns "" for a dropped sentence.
    static func sentence(_ raw: String, english: Bool = true) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return "" }
        guard english else { return s }
        if s.lowercased().hasPrefix("assumed ") { return "" }
        for h in hedges { s = s.replacingOccurrences(of: h, with: "", options: .caseInsensitive) }
        s = s.replacingOccurrences(of: "looks intact", with: "is intact", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "looks like", with: "is", options: .caseInsensitive)
        s = s.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
        guard let f = s.first else { return "" }
        s = f.uppercased() + s.dropFirst()
        if let l = s.last, !".!?".contains(l) { s += "." }
        return s
    }

    static func text(_ raw: String, english: Bool = true) -> String {
        sentences(raw).map { sentence($0, english: english) }.filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// First sentence as the headline, the rest as body.
    static func headlineAndBody(_ summary: String, english: Bool = true) -> (headline: String, body: String) {
        let s = sentences(text(summary, english: english))
        guard let first = s.first else { return ("", "") }
        return (first, s.dropFirst().joined(separator: " "))
    }

    /// "Cutting stable fabric - trim only fluff" -> "Cutting stable fabric. Trim only fluff."
    static func mistake(_ raw: String, english: Bool = true) -> String {
        guard english else { return raw }
        var t = raw
        while let r = t.range(of: " - ") {
            let after = t[r.upperBound...]
            let cap = after.first.map { String($0).uppercased() + after.dropFirst() } ?? ""
            t = t[..<r.lowerBound] + ". " + cap
        }
        return text(t, english: english)
    }

    /// Reasoning for the verdict: at most the first two polished sentences.
    static func reason(_ raw: String, english: Bool = true) -> String {
        sentences(text(raw, english: english)).prefix(2).joined(separator: " ")
    }
}

/// A step text ends with "Done when ..." (or "End state: ..."): shown on its own line under the instruction.
enum DoneWhenLine {
    static func split(_ text: String, english: Bool = true) -> (body: String, doneWhen: String?) {
        var s = CopyPolish.sentences(text)
        guard english, let last = s.last else { return (text, nil) }
        let low = last.lowercased()
        var done: String?
        if low.hasPrefix("done when ") { done = last }
        else if low.hasPrefix("you're done when ") { done = "Done when " + last.dropFirst("you're done when ".count) }
        else if low.hasPrefix("end state:") {
            let rest = last.dropFirst("end state:".count).trimmingCharacters(in: .whitespaces)
            let lowered = rest.first.map { String($0).lowercased() + rest.dropFirst() } ?? rest
            done = "Done when " + lowered
        }
        guard let d = done else { return (text, nil) }
        s.removeLast()
        var dw = d.trimmingCharacters(in: .whitespaces)
        if let l = dw.last, !".!?".contains(l) { dw += "." }
        return (s.joined(separator: " "), dw)
    }
}

/// Short project title and repair line derived from the case, never the raw model summary.
enum ProjectTitle {
    static func title(summary: String, english: Bool = true) -> String {
        let first = CopyPolish.sentences(summary).first ?? summary
        var t = first.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        for h in ["Assumed ", "assumed ", "presumably ", "Presumably "] { t = t.replacingOccurrences(of: h, with: "") }
        let low = t.lowercased()
        for key in [" in ", " on ", " of "] {
            if let r = low.range(of: key) {
                let after = String(t[t.index(t.startIndex, offsetBy: low.distance(from: low.startIndex, to: r.upperBound))...])
                if let w = trimmed(after) { return w }
            }
        }
        if let r = low.range(of: " with ") {
            let before = String(t[..<t.index(t.startIndex, offsetBy: low.distance(from: low.startIndex, to: r.lowerBound))])
            if let w = trimmed(before) { return w }
        }
        return trimmed(t) ?? "Repair"
    }

    private static func trimmed(_ s: String) -> String? {
        var words = (s.split(separator: ",").first.map(String.init) ?? s).split(separator: " ").map(String.init)
        while let f = words.first, ["a", "an", "the", "worn", "heavily"].contains(f.lowercased()) && words.count > 2 { words.removeFirst() }
        if let f = words.first, f.lowercased() == "a" || f.lowercased() == "the" { words.removeFirst() }
        words = Array(words.prefix(4))
        guard !words.isEmpty else { return nil }
        let t = words.joined(separator: " ")
        return t.prefix(1).uppercased() + t.dropFirst()
    }

    static func subtitle(for r: AnalyzeResponse, parked: Bool = false) -> String {
        if parked { return "With a pro" }
        switch r.decision?.recommendation {
        case .repairPro: return "With a pro"
        case .replace: return "Give it a second life"
        default: break
        }
        if r.guide.steps.contains(where: { $0.overlay?.type == .solder }) { return "Reconnect the wire" }
        if let st = r.guide.steps.compactMap({ $0.overlay?.stitchType }).first(where: { $0 != .runningStitch }) ?? r.guide.steps.compactMap({ $0.overlay?.stitchType }).first {
            switch st {
            case .darning: return "Darn the hole"
            case .ladderStitch: return "Close the seam"
            case .whipStitch: return "Stitch the edge"
            case .runningStitch: return "Sew the tear"
            }
        }
        if r.category == .shoe { return "Reglue the sole" }
        return "Repair it yourself"
    }
}
