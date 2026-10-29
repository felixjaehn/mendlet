import SwiftUI

/// Launch-argument driven jumps for automated screenshots:
/// `-demoRoute home|review|analysis|diagnosis|followup|decision|shopping|guide|block|done|settings|stephelp`
/// `-demoScenario textile_tear|textile_hole|shoe_sole|battery_jacket|helmet`, `-demoStep N`, `-demoShopping none|partial|all`
@MainActor
enum DemoBootstrap {
    static func run(_ flow: FlowModel) async {
        let d = UserDefaults.standard
        guard let route = d.string(forKey: "demoRoute"), route != "home" else { return }
        let scenario = DemoScenario(rawValue: d.string(forKey: "demoScenario") ?? "") ?? .textileTear
        flow.settings.demoMode = true
        flow.settings.scenario = scenario
        let image = await DemoPhotos.imageAsync(for: scenario)
        flow.photo = ImageResizer.resized(image)
        flow.note = scenario.userNote

        func loaded(label: Bool) -> AnalyzeResponse? {
            let rec = LiveRecordings.recording(for: scenario)
            guard var r = (label ? rec?.labelResponse : nil) ?? rec?.response ?? (try? Fixtures.response(scenario, labelProvided: label)) else { return nil }
            r.caseId = "demo-" + scenario.rawValue
            return FlowGate.sanitized(r)
        }

        switch route {
        case "review":
            flow.showReview = true
        case "settings":
            flow.showSettings = true
        case "analysis":
            flow.startAnalysis()
        case "diagnosis":
            flow.response = loaded(label: true); flow.followUpUsed = true
            if scenario == .textileTear { flow.labelImage = LiveRecordings.recording(for: scenario)?.labelPhoto ?? DemoImageFactory.labelImage(); flow.newInfoBanner = tr("Etikett erkannt: %@", "98 % Baumwolle, 2 % Elasthan") }
            flow.path = [.diagnosis]
        case "followup":
            flow.response = loaded(label: false)
            flow.path = [.diagnosis]
        case "decision":
            flow.response = loaded(label: true); flow.path = [.decision]
        case "shopping", "guide", "stephelp", "done":
            flow.response = loaded(label: true)
            guard let r = flow.response else { return }
            let mode = d.string(forKey: "demoShopping") ?? (route == "shopping" ? "partial" : "all")
            if mode == "all" { for i in r.shoppingList where i.required { flow.statuses[i.id] = .have } }
            if mode == "partial" {
                for (n, i) in r.shoppingList.enumerated() {
                    if n == 0 || n == 2 { flow.statuses[i.id] = .have }
                    if n == 1 { flow.statuses[i.id] = .buy }
                }
            }
            flow.guideStartedAt = Date().addingTimeInterval(-26 * 60)
            switch route {
            case "shopping": flow.path = [.decision, .shopping]
            case "guide", "stephelp":
                flow.currentStep = d.integer(forKey: "demoStep")
                flow.path = [.decision, .shopping, .guide]
            default:
                flow.currentStep = r.guide.steps.count - 1
                flow.store.recordRescue(caseId: "demo-a", garment: "Jeans", kilograms: 0.6)
                flow.path = [.completion]
            }
        case "block":
            flow.response = loaded(label: true)
            flow.path = [.block]
        default:
            break
        }
    }
}
