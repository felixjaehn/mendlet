import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers

/// Illustrated repair guide as a PDF: cover (own photo with the SAM masks, diagnosis, recommendation, Muse Image
/// preview), "What you need", then one page per step with that step's overlay drawn on the user's own photo.
/// Generated only when shared (Transferable), rendered as vector pages with ImageRenderer.
struct GuidePDF: Transferable {
    let response: AnalyzeResponse
    let photo: UIImage
    var after: UIImage?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { doc in
            SentTransferredFile(try await MainActor.run { try GuideExporter.write(doc) })
        }
    }
}

@MainActor
enum GuideExporter {
    /// US Letter in points; A4 differs by a few millimetres and prints fine either way.
    static let page = CGSize(width: 612, height: 792)

    static func write(_ doc: GuidePDF) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(tr("Reparaturanleitung") + ".pdf")
        var box = CGRect(origin: .zero, size: page)
        guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { throw CocoaError(.fileWriteUnknown) }
        let steps = doc.response.guide.steps
        let total = 2 + steps.count
        var pages: [AnyView] = [AnyView(CoverPage(doc: doc)), AnyView(NeedsPage(response: doc.response))]
        pages += steps.enumerated().map { i, s in AnyView(StepPage(doc: doc, step: s, index: i, count: steps.count)) }
        for (n, content) in pages.enumerated() {
            let framed = PageFrame(number: n + 1, total: total) { content }
                .frame(width: page.width, height: page.height)
                .environment(\.staticRendering, true)  // overlays draw their final state
                .environment(\.colorScheme, .light)
                .environment(\.locale, Lang.shared.locale)
            let renderer = ImageRenderer(content: framed)
            renderer.proposedSize = ProposedViewSize(page)
            renderer.render { _, draw in
                pdf.beginPDFPage(nil)
                draw(pdf)
                pdf.endPDFPage()
            }
        }
        pdf.closePDF()
        return url
    }
}

// MARK: Pages

private struct PageFrame<Content: View>: View {
    let number: Int
    let total: Int
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
            Spacer(minLength: 0)
            HStack {
                Text("Reparaturanleitung")
                Spacer()
                Text(tr("Seite %lld von %lld", number, total)).monospacedDigit()
            }
            .font(.caption2).foregroundStyle(Color(white: 0.55))
        }
        .padding(.horizontal, 44).padding(.vertical, 36)
        .background(Color.white)
    }
}

private struct PhotoPanel<Overlay: View>: View {
    let photo: UIImage
    var height: CGFloat = 330
    @ViewBuilder var overlay: (CGSize) -> Overlay

    var body: some View {
        PhotoStage(image: photo, cornerRadius: 18, minAspect: 0.9) { size in overlay(size) }
            .frame(height: height)
            .frame(maxWidth: .infinity)
    }
}

private struct CoverPage: View {
    let doc: GuidePDF
    private var r: AnalyzeResponse { doc.response }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reparaturanleitung").font(.system(size: 30, weight: .bold))
            Text(r.diagnosis.summary).font(.system(size: 13)).foregroundStyle(Color(white: 0.3))
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: 12) {
                PhotoPanel(photo: doc.photo, height: 300) { size in
                    SegmentOverlayView(segments: r.segments, size: size, appeared: true, showLabels: true)
                }
                if let after = doc.after {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(uiImage: after).resizable().scaledToFill()
                            .frame(width: 150, height: 200).clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        Text("So könnte es aussehen").font(.system(size: 10)).foregroundStyle(Color(white: 0.45))
                        Text("Vorschau · Muse Image").font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(white: 0.45))
                    }
                    .frame(width: 150)
                }
            }
            if let d = r.decision {
                HStack(spacing: 14) {
                    Image(systemName: d.recommendation.icon).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 40, height: 40).background(d.recommendation.tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(d.recommendation.title).font(.system(size: 17, weight: .bold))
                        Text("\(Fmt.minutes(d.timeMinutes)) · \(Fmt.euro(d.costEur)) · \(tr("Schätzung"))")
                            .font(.system(size: 12)).foregroundStyle(Color(white: 0.4))
                    }
                }
                Text(d.reasoning).font(.system(size: 12)).foregroundStyle(Color(white: 0.25)).fixedSize(horizontal: false, vertical: true)
            }
            Text("Erstellt mit SAM 3.1, Muse Spark und Muse Image").font(.system(size: 10)).foregroundStyle(Color(white: 0.55))
        }
    }
}

private struct NeedsPage: View {
    let response: AnalyzeResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Du brauchst").font(.system(size: 26, weight: .bold))
            ForEach([ItemKind.material, .tool], id: \.self) { kind in
                let items = response.shoppingList.filter { $0.kind == kind }
                if !items.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(kind == .material ? "Material" : "Werkzeug").font(.system(size: 15, weight: .semibold))
                        ForEach(items) { it in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: "square").font(.system(size: 14)).foregroundStyle(Color(white: 0.5))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(it.name).font(.system(size: 13, weight: .medium))
                                    Text([it.quantity, it.required ? tr("Pflicht") : tr("Optional"), it.householdAlternative.map { tr("oder: %@", $0) }]
                                        .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                        .font(.system(size: 11)).foregroundStyle(Color(white: 0.45))
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct StepPage: View {
    let doc: GuidePDF
    let step: GuideStep
    let index: Int
    let count: Int

    var body: some View {
        let aspect = doc.photo.size.width / max(doc.photo.size.height, 1)
        VStack(alignment: .leading, spacing: 14) {
            Text(tr("Schritt %lld von %lld", index + 1, count)).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.45)).monospacedDigit()
            Text(step.title).font(.system(size: 24, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            PhotoPanel(photo: doc.photo, height: 340) { size in
                StepOverlay(step: step, response: doc.response, size: size, aspect: aspect,
                            staticPlan: StepOverlay.stitchPlan(step: step, response: doc.response, aspect: aspect))
            }
            Text(step.text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            if step.needsConfirmation {
                Label { Text("Vorsicht bei diesem Schritt") } icon: { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow) }
                    .font(.system(size: 12, weight: .semibold))
            }
            if let m = step.commonMistake, !m.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Typischer Fehler").font(.system(size: 12, weight: .semibold))
                    Text(m).font(.system(size: 12)).foregroundStyle(Color(white: 0.3)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }
}
