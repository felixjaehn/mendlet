import XCTest
@testable import RepairAssistant

@MainActor
final class LocalizationTests: XCTestCase {
    private var original = "de"
    override func setUp() { original = Lang.shared.choice }
    override func tearDown() { Lang.shared.choice = original }

    private func catalog(_ name: String) throws -> [String: Any] {
        // Tests run on the simulator, which shares the host file system: read the catalog source next to the app sources.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("RepairAssistant/\(name).xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(json)
    }

    func testEveryCatalogKeyHasAnEnglishTranslation() throws {
        for name in ["Localizable", "InfoPlist"] {
            let cat = try catalog(name)
            XCTAssertEqual(cat["sourceLanguage"] as? String, "de")
            let strings = try XCTUnwrap(cat["strings"] as? [String: [String: Any]])
            XCTAssertGreaterThan(strings.count, name == "Localizable" ? 200 : 4)
            for (key, entry) in strings {
                let loc = (entry["localizations"] as? [String: [String: Any]])?["en"]
                let value = (loc?["stringUnit"] as? [String: Any])?["value"] as? String
                XCTAssertFalse(value?.isEmpty ?? true, "\(name): missing English for \(key.debugDescription)")
                // placeholders must survive the translation
                for p in ["%lld", "%@"] {
                    XCTAssertEqual(key.components(separatedBy: p).count, value?.components(separatedBy: p).count, "\(name): \(p) mismatch for \(key.debugDescription)")
                }
            }
        }
    }

    func testCompiledBundleServesEnglishAndGerman() {
        Lang.shared.choice = "en"
        XCTAssertEqual(tr("Abbrechen"), "Cancel")
        XCTAssertEqual(tr("Schritt %lld von %lld", 2, 5), "Step 2 of 5")
        XCTAssertEqual(tr("%lld Löcher", 3), "3 holes")
        XCTAssertEqual(tr("Ein Satz, den es nicht im Katalog gibt"), "Ein Satz, den es nicht im Katalog gibt")
        XCTAssertEqual(ImpactEstimator.format(kg: 0.6), "0.6")
        Lang.shared.choice = "de"
        XCTAssertEqual(tr("Abbrechen"), "Abbrechen")
        XCTAssertEqual(tr("Schritt %lld von %lld", 2, 5), "Schritt 2 von 5")
        XCTAssertEqual(ImpactEstimator.format(kg: 0.6), "0,6")
    }

    func testLanguageResolution() {
        XCTAssertEqual(Lang.resolve("en", preferred: ["de-DE"]), "en")
        XCTAssertEqual(Lang.resolve("de", preferred: ["en-US"]), "de")
        XCTAssertEqual(Lang.resolve("system", preferred: ["en-US", "de-DE"]), "en")
        XCTAssertEqual(Lang.resolve("system", preferred: ["fr-FR", "de-DE"]), "de")
        XCTAssertEqual(Lang.resolve("system", preferred: ["fr-FR"]), "de")
        XCTAssertEqual(Lang.resolve("bogus", preferred: []), "de")
    }

    func testRequestLocaleFollowsUILanguage() throws {
        Lang.shared.choice = "en"
        XCTAssertEqual(Lang.apiCode, "en")
        let json = try XCTUnwrap(String(data: ContractCoding.encoder().encode(StepHelpRequest(step: StepRef(n: 1, title: "t", text: "x"), diagnosisSummary: "s", riskLevel: .allowed, issueText: "i")), encoding: .utf8))
        XCTAssertTrue(json.contains("\"locale\":\"en\""), json)
        Lang.shared.choice = "de"
        XCTAssertEqual(AnalyzeRequest(imageBase64: "", userNote: "").locale, "de")
    }

    func testEnglishRecordingFallsBackToGerman() {
        let only: Set<String> = ["jeans", "pulli", "jeans.en"]
        let exists: (String) -> Bool = { only.contains($0) }
        XCTAssertEqual(LiveRecordings.localizedJSONName("jeans", language: "en", exists: exists), "jeans.en")
        XCTAssertEqual(LiveRecordings.localizedJSONName("pulli", language: "en", exists: exists), "pulli")
        XCTAssertEqual(LiveRecordings.localizedJSONName("jeans", language: "de", exists: exists), "jeans")
        XCTAssertEqual(LiveRecordings.localizedJSONName("jeans.en", language: "en", exists: exists), "jeans.en")
        // no fake English recordings are shipped: the bundled files resolve to the German ones
        for f in ["jeans", "pulli", "sneaker", "heizjacke", "platine", "jeans_label", "jeans_agent"] {
            XCTAssertEqual(LiveRecordings.localizedJSONName(f, language: "en"), LiveRecordings.url(f + ".en", "json") == nil ? f : f + ".en")
        }
        Lang.shared.choice = "en"
        XCTAssertNotNil(LiveRecordings.recording(for: .textileTear))
    }

    func testAgentLabelsTranslateInEnglishOnly() {
        XCTAssertEqual(AgentLabel.localized("SAM sucht „rip“", english: false), "SAM sucht „rip“")
        Lang.shared.choice = "en"
        XCTAssertEqual(AgentLabel.localized("SAM sucht „rip“", english: true), "SAM is looking for “rip”")
        XCTAssertEqual(AgentLabel.localized("Spark prüft Maske seg_1", english: true), "Spark is checking mask seg_1")
        XCTAssertEqual(AgentLabel.localized("Plan zusammenstellen", english: true), "Assembling the plan")
        XCTAssertEqual(AgentLabel.localized("Riss", english: true), "Tear")
    }

    func testEnglishShoeDurationParsing() {
        XCTAssertEqual(ShoeStepKind.minutes(in: "Let it dry for 10 minutes."), 10)
        XCTAssertEqual(ShoeStepKind.minutes(in: "Wait 20 to 30 min."), 30)
        XCTAssertEqual(ShoeStepKind.minutes(in: "Press for 2 hours."), 120)
        XCTAssertEqual(ShoeStepKind.minutes(in: "10 Minuten ablüften"), 10)
    }
}
