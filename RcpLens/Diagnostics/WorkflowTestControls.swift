#if DEBUG
import SwiftUI

/// Local-only debug boundary. The input lives in an ignored Simulator container, never in the bundle.
/// These controls only exist after an explicit debug test launch; Release contains no test importer.
enum WorkflowTestInput {
    @MainActor static func recordPrivacy(event: String, covered: Bool) {
        guard enabled else { return }
        let url = directory.appendingPathComponent("privacy.json")
        var report = (try? Data(contentsOf: url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Int] } ?? [:]
        report[event, default: 0] += 1
        if covered { report["coversObserved", default: 0] += 1 }
        if let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) { try? bytes.write(to: url, options: .atomic) }
    }
    @MainActor static func recordState(_ workspace: ReceiptWorkspace, event: String) {
        guard enabled else { return }
        let availability: String
        switch workspace.availability { case .closed: availability = "closed"; case .opening: availability = "opening"; case .ready: availability = "ready"; case .failed: availability = "failed" }
        let inputReadable = (try? input()) != nil
        let report: [String: Any] = ["event": event, "flow": String(describing: workspace.flow), "availability": availability,
            "active": workspace.active, "imagePresent": workspace.image != nil, "inputReadable": inputReadable,
            "sourceObservationCount": workspace.extraction?.rawOCR.count ?? 0, "savedCount": workspace.receipts.count, "extractionPresent": workspace.extraction != nil,
            "noTextFailure": workspace.errorMessage == ImportFailure.noText.message, "recognitionFailure": workspace.errorMessage == ImportFailure.recognitionFailed.message]
        if let bytes = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? bytes.write(to: directory.appendingPathComponent("state.json"), options: .atomic)
        }
    }
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--t05-local-test") }
    static var directory: URL {
        let args = ProcessInfo.processInfo.arguments
        let slot = args.firstIndex(of: "--t05-slot").flatMap { $0 + 1 < args.count ? Int(args[$0 + 1]) : nil } ?? 0
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("T05TestInbox")
        return root.appendingPathComponent("slot\(max(0, min(5, slot)))")
    }
    struct Input: Decodable {
        var image: String
        var expected: Expected?
    }
    struct Expected: Decodable {
        struct Line: Decodable { var kind: String; var description: String; var amount: Int64?; var quantity: String? }
        var merchant: String?
        var date: String?
        var subtotal: Int64?
        var total: Int64?
        var lines: [Line]
        var completeReference: Bool {
            guard merchant != nil, date != nil, let subtotal, let total, lines.allSatisfy({ $0.amount != nil }) else { return false }
            func sum(_ included: (Line) -> Bool) -> Int64? {
                var result: Int64 = 0
                for line in lines where included(line) {
                    let (next, overflow) = result.addingReportingOverflow(line.amount!)
                    if overflow { return nil }; result = next
                }
                return result
            }
            return sum({ _ in true }) == total
                && [sum({ $0.kind == "purchase" }), sum({ $0.kind == "purchase" || $0.kind == "discount" }), sum({ $0.kind != "tax" && $0.kind != "tip" })].contains(subtotal)
        }
    }
    static func input() throws -> Input { try JSONDecoder().decode(Input.self, from: Data(contentsOf: directory.appendingPathComponent("request.json"))) }
    static func imageURL() throws -> URL {
        let name = try input().image
        guard !name.contains("/"), !name.contains("..") else { throw ImportFailure.unavailableFile }
        return directory.appendingPathComponent(name)
    }
    @MainActor static func applyReference(_ workspace: ReceiptWorkspace) {
        guard enabled, let expected = try? input().expected else { return }
        var draft = ReceiptReviewDraft()
        draft.merchant = expected.merchant ?? ""; draft.date = expected.date ?? ""; draft.currency = "CAD"
        draft.subtotal = expected.subtotal.map { ExactInput.format($0) } ?? ""; draft.total = expected.total.map { ExactInput.format($0) } ?? ""
        draft.subtotalNotPrinted = false // Null reference means unknown, never confirmed absence.
        draft.lines = expected.lines.map { line in
            EditableReceiptLine(id: UUID(), kind: line.kind == "adjustment" ? "other" : line.kind,
                name: line.description, quantity: line.quantity.flatMap { ReceiptParser.first(#"\d+(?:\.\d+)?"#, $0) } ?? "",
                amount: line.amount.map { ExactInput.format($0) } ?? "", sourceLineIDs: [])
        }
        workspace.draft = draft
    }
    struct Report: Codable {
        var status: String
        var originalBytesEqual: Bool
        var originalParserUnchanged: Bool
        var correctionMatchesReference: Bool
        var complete: Bool
        var revisions: Int
        var sourceObservationCount: Int
        var hasGeometry: Bool
        var sourceOpened: Bool
        var sourceChecked: Bool
        var remainingIssueCount: Int
        var referenceAllowsCompletion: Bool
    }
    @MainActor static func verify(_ workspace: ReceiptWorkspace) {
        guard enabled, let record = workspace.selected, let image = workspace.image else { return }
        do {
            let expected = try input().expected
            let bytes = try Data(contentsOf: imageURL())
            let current = record.current.fields
            var matches = true
            if let expected {
                let actual = current.items.map { ("purchase", $0.description ?? "", $0.amount?.minorUnits) }
                    + current.adjustments.map { ($0.kind == .other ? "adjustment" : $0.kind.rawValue, $0.label ?? "", $0.amount?.minorUnits) }
                let desired = expected.lines.map { ($0.kind, $0.description, $0.amount) }
                // Preserve duplicates; compare multisets because the digital layout groups adjustment kinds.
                func sorted(_ lines: [(String, String, Int64?)]) -> [String] { lines.map { "\($0.0)|\($0.1)|\($0.2.map(String.init) ?? "unknown")" }.sorted() }
                matches = sorted(actual) == sorted(desired) && current.merchant == expected.merchant
                    && ExactInput.dateText(current.purchaseDate) == (expected.date ?? "")
                    && current.subtotal?.minorUnits == expected.subtotal && current.total?.minorUnits == expected.total
            }
            let parsed = try JSONDecoder().decode(ParsedReceipt.self, from: record.original.rawParserOutput)
            let savedInput = record.current.reviewInput.flatMap { try? JSONDecoder().decode(ReceiptReviewDraft.self, from: $0) }
            let report = Report(status: "verified", originalBytesEqual: bytes == image.bytes,
                originalParserUnchanged: parsed.fields() == record.original.fields,
                correctionMatchesReference: matches, complete: ReceiptCompletion.isComplete(record), revisions: record.revisions.count,
                sourceObservationCount: record.original.rawOCR.count, hasGeometry: record.original.rawOCR.allSatisfy { $0.boundingBox != nil }, sourceOpened: savedInput?.sourceOpened ?? false,
                sourceChecked: savedInput?.sourceChecked ?? false, remainingIssueCount: savedInput?.reconciliation.issues.count ?? 0,
                referenceAllowsCompletion: expected?.completeReference ?? false)
            try JSONEncoder().encode(report).write(to: directory.appendingPathComponent("report.json"), options: .atomic)
            workspace.notice = report.originalBytesEqual && report.originalParserUnchanged && report.correctionMatchesReference && report.complete == (expected?.completeReference ?? false) ? "Local verification passed" : "Local verification failed"
        } catch { workspace.notice = "Local test verification could not complete." }
    }
}

struct WorkflowTestControls: View {
    var workspace: ReceiptWorkspace
    var body: some View {
        if WorkflowTestInput.enabled {
            Section("Local test controls · Debug only") {
                Button("Import local test image") {
                    WorkflowTestInput.recordState(workspace, event: "testImportTapped")
                    guard let url = try? WorkflowTestInput.imageURL() else { return }
                    workspace.importFile(url)
                }.accessibilityIdentifier("debugImportFooter")
                Button("Import malformed test data") { workspace.startImport { Data([0, 1, 2, 3]) } }.accessibilityIdentifier("debugMalformed")
                Button("Enter manual test receipt") {
                    workspace.startImport { try SyntheticFixture.imageData() }
                }.accessibilityIdentifier("debugSynthetic")
            }
        }
    }
}
struct WorkflowReviewTestControls: View {
    var workspace: ReceiptWorkspace
    var body: some View {
        if WorkflowTestInput.enabled {
            Section("Local test controls · Debug only") {
                if let expected = try? WorkflowTestInput.input().expected, !expected.completeReference {
                    Text("Local reference retains unresolved fields").accessibilityIdentifier("debugReferenceIncomplete")
                }
                Button("Apply local checked reference") { WorkflowTestInput.applyReference(workspace) }.accessibilityIdentifier("debugReference")
            }
        }
    }
}
struct WorkflowDetailTestControls: View {
    var workspace: ReceiptWorkspace
    var body: some View {
        if WorkflowTestInput.enabled {
            if let notice = workspace.notice { Text(notice).accessibilityIdentifier("debugReport") }
        }
    }
}
#endif
