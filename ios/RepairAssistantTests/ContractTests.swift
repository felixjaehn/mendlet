import XCTest
@testable import RepairAssistant

final class ContractTests: XCTestCase {
    private func fixture(_ name: String) throws -> AnalyzeResponse { try Fixtures.load(name) }

    func testFullFixtureDecodes() throws {
        let r = try fixture("textile_tear")
        XCTAssertEqual(r.category, .textile)
        XCTAssertEqual(r.riskLevel, .allowed)
        XCTAssertEqual(r.segments.count, 3)
        XCTAssertEqual(r.segments.first?.kind, .damage)
        XCTAssertGreaterThan(r.segments[0].polygon.count, 10)
        XCTAssertEqual(r.diagnosis.labelInfo?.materials.first, "98 % Baumwolle")
        XCTAssertEqual(r.decision?.recommendation, .repairSelf)
        XCTAssertEqual(r.decision?.timeMinutes, [20, 40])
        XCTAssertEqual(r.shoppingList.count, 5)
        XCTAssertEqual(r.guide.steps.count, 6)
        XCTAssertEqual(r.guide.steps[3].overlay?.stitchType, .ladderStitch)
        XCTAssertTrue(r.guide.steps[0].needsConfirmation)
    }

    func testAllFixturesDecode() throws {
        for n in ["textile_tear_needs_label", "textile_hole", "shoe_sole", "battery_jacket", "helmet"] {
            XCTAssertNoThrow(try fixture(n), n)
        }
        XCTAssertTrue(try fixture("textile_tear_needs_label").diagnosis.needsMoreInfo)
    }

    func testUnknownEnumsFallBackSafely() throws {
        let json = """
        {"category":"spaceship","risk_level":"banana","segments":[{"id":"s","label":"x","kind":"weird","score":0.5}],
         "diagnosis":{"summary":"s","confidence":3.5,"follow_up_questions":[{"id":"q","type":"hologram","prompt":"p","purpose":"zzz"}]},
         "decision":{"recommendation":"teleport","effort":"extreme"},
         "shopping_list":[{"id":"i","name":"n","kind":"gadget"}],
         "guide":{"steps":[{"n":1,"title":"t","text":"x","overlay":{"type":"laser","stitch_type":"zigzag"}}]}}
        """
        let r = try ContractCoding.decoder().decode(AnalyzeResponse.self, from: Data(json.utf8))
        XCTAssertEqual(r.category, .unsupported)
        XCTAssertEqual(r.riskLevel, .warnOnly)
        XCTAssertEqual(r.segments[0].kind, .part)
        XCTAssertEqual(r.diagnosis.confidence, 1.0)
        XCTAssertEqual(r.diagnosis.followUpQuestions[0].type, .voiceOrText)
        XCTAssertEqual(r.diagnosis.followUpQuestions[0].purpose, .other)
        XCTAssertEqual(r.decision?.recommendation, .repairPro)
        XCTAssertEqual(r.decision?.effort, .medium)
        XCTAssertEqual(r.shoppingList[0].kind, .material)
        XCTAssertEqual(r.guide.steps[0].overlay?.type, .highlight)
        XCTAssertEqual(r.guide.steps[0].overlay?.stitchType, .runningStitch)
    }

    func testMissingOptionalFields() throws {
        let r = try ContractCoding.decoder().decode(AnalyzeResponse.self, from: Data("{}".utf8))
        XCTAssertEqual(r.category, .unsupported)
        XCTAssertEqual(r.riskLevel, .warnOnly)
        XCTAssertTrue(r.segments.isEmpty)
        XCTAssertNil(r.decision)
        XCTAssertTrue(r.guide.steps.isEmpty)
        XCTAssertEqual(r.diagnosis.confidence, 0)
    }

    func testMaskAsStringFallsBackToBox() throws {
        let json = #"{"id":"a","label":"L","kind":"damage","box":[0.1,0.2,0.3,0.4],"mask":"<rle>","score":0.9}"#
        let s = try ContractCoding.decoder().decode(Segment.self, from: Data(json.utf8))
        XCTAssertNil(s.mask)
        XCTAssertTrue(s.polygon.isEmpty)
        XCTAssertEqual(s.normalizedBox, CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4))
    }

    func testMaxThreeQuestions() throws {
        let q = (1...5).map { #"{"id":"q\#($0)","type":"choice","prompt":"p"}"# }.joined(separator: ",")
        let d = try ContractCoding.decoder().decode(Diagnosis.self, from: Data(#"{"follow_up_questions":[\#(q)]}"#.utf8))
        XCTAssertEqual(d.followUpQuestions.count, 3)
    }

    func testRequestEncodesSnakeCase() throws {
        let req = AnalyzeRequest(imageBase64: "AAA", userNote: "n", extraImages: [ExtraImage(purpose: .label, imageBase64: "B")],
                                 answers: [AnswerPayload(questionId: "q1", text: "t")], mockScenario: "textile_tear")
        let data = try ContractCoding.encoder().encode(req)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["image_base64"] as? String, "AAA")
        XCTAssertEqual(obj["user_note"] as? String, "n")
        XCTAssertEqual(obj["mock_scenario"] as? String, "textile_tear")
        XCTAssertEqual(obj["locale"] as? String, "de")
        let extra = try XCTUnwrap(obj["extra_images"] as? [[String: Any]])
        XCTAssertEqual(extra[0]["purpose"] as? String, "label")
        let ans = try XCTUnwrap(obj["answers"] as? [[String: Any]])
        XCTAssertEqual(ans[0]["question_id"] as? String, "q1")
    }

    func testSSEParser() throws {
        var p = SSEParser()
        var out: [SSEMessage] = []
        for line in ["event: progress", "data: {\"stage\":\"classify\",\"label\":\"x\"}", "", ": ping", "event: result", "data: {}"] { out += p.feed(line) }
        out += p.finish()
        XCTAssertEqual(out.map(\.event), ["progress", "result"])
        // without blank separators
        var q = SSEParser(); var o2: [SSEMessage] = []
        for l in ["event: progress", "data: {\"stage\":\"segment\"}", "event: error", "data: {\"message\":\"boom\"}"] { o2 += q.feed(l) }
        o2 += q.finish()
        XCTAssertEqual(o2.map(\.event), ["progress", "error"])
        XCTAssertThrowsError(try SSEDecoder.decode(o2[1]))
        if case .progress(let s, _, _)? = try SSEDecoder.decode(o2[0]) { XCTAssertEqual(s, .segment) } else { XCTFail() }
        XCTAssertNil(try SSEDecoder.decode(SSEMessage(event: "progress", data: "{\"stage\":\"nonsense\"}")))
    }
}
