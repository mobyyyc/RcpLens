import XCTest
import UIKit
@testable import Sliplet

final class ReceiptCorrectionTests: XCTestCase, @unchecked Sendable {
    struct Key: ReceiptStoreKeyProvider {
        func loadKey() -> Data? { Data(repeating: 0x61, count: 32) }
        func createKey() -> Data { Data(repeating: 0x61, count: 32) }
    }
    private func extraction(_ text: String) throws -> ReceiptExtraction {
        try ReceiptParser.extraction(OCRResult(lines: text.split(separator: "\n").map { ReceiptOCRLine(id: UUID(), text: String($0), engineConfidence: nil) }, revision: 3))
    }
    func testInstalledDraftDecodesWithoutGuidanceChecks() throws {
        let data = Data(#"{"merchant":"","date":"","currency":"","lines":[],"subtotal":"","total":"","subtotalNotPrinted":false,"sourceOpened":false,"sourceChecked":false}"#.utf8)
        let draft = try JSONDecoder().decode(ReceiptReviewDraft.self, from: data)
        XCTAssertNil(draft.guidanceChecks); XCTAssertTrue(draft.canSaveDraft); XCTAssertFalse(draft.canFinalize)
    }
    func testGroupUnpricedHeadersAndAmountsWithoutLosingEvidence() throws {
        let original = try extraction("FICTIONAL STORE CAD\n2026-10-09\nTEST HEADER\nTEST WRAPPED\nITEM 1.00\n2.00\n3.00\nTOTAL 1.00")
        let draft = ReceiptReviewDraft(fields: original.fields)
        let checks = ReceiptReviewGuidance.checks(draft: draft, extraction: original)
        let unpriced = try XCTUnwrap(checks.first { $0.title == "Check unassigned text" })
        XCTAssertEqual(checks.filter { $0.title == "Check unassigned text" }.count, 1)
        XCTAssertEqual(Set(unpriced.sourceLineIDs), Set(original.issues.filter { $0.code == "unpriced_source_row" }.flatMap(\.sourceLineIDs)))
        let amounts = try XCTUnwrap(checks.first { $0.title == "Check unassigned amounts" })
        XCTAssertEqual(Set(amounts.sourceLineIDs), Set(original.issues.filter { $0.code == "unpaired_amount" }.flatMap(\.sourceLineIDs)))
        XCTAssertFalse(checks.contains { $0.title.contains("geometry") })
    }
    func testScopedCheckSurvivesUnrelatedEditButReopensOnRelatedEdit() throws {
        let original = try extraction("FICTIONAL STORE CAD\n10/09/2026\nITEM 1.00\nSUBTOTAL 1.00\nTOTAL 1.00")
        var draft = ReceiptReviewDraft(fields: original.fields)
        let date = try XCTUnwrap(ReceiptReviewGuidance.checks(draft: draft, extraction: original).first { $0.title == "Verify the printed date" })
        draft.guidanceChecks = [date.id: date.signature(in: draft)]
        XCTAssertTrue(date.isChecked(in: draft)); XCTAssertEqual(date.signature(in: draft), date.signature(in: draft))
        draft.merchant = "FICTIONAL CHANGED STORE"; XCTAssertTrue(date.isChecked(in: draft))
        draft.date = "2026-10-08"; XCTAssertFalse(date.isChecked(in: draft))
        XCTAssertFalse(draft.canFinalize)
    }
    func testLineAndUnassignedChecksReopenAfterEvidenceOrAmountChange() throws {
        let original = try extraction("FICTIONAL STORE CAD\n2026-10-09\nCOUPON 1.00\nWRAPPED ROW\nTOTAL 1.00")
        var draft = ReceiptReviewDraft(fields: original.fields)
        let checks = ReceiptReviewGuidance.checks(draft: draft, extraction: original).filter { !$0.requiresCorrection }
        draft.guidanceChecks = Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0.signature(in: draft)) })
        XCTAssertTrue(checks.allSatisfy { $0.isChecked(in: draft) })
        let encoded = try JSONEncoder().encode(draft)
        draft = try JSONDecoder().decode(ReceiptReviewDraft.self, from: encoded)
        XCTAssertTrue(checks.allSatisfy { $0.isChecked(in: draft) })
        draft.lines[0].amount = "-1.00"
        XCTAssertTrue(checks.allSatisfy { !$0.isChecked(in: draft) })
    }
    func testMultipleMalformedFieldsCanBeCorrectedIndependentlyAndNewErrorsRejected() {
        var baseline = ReceiptReviewDraft()
        baseline.currency = "CAD"; baseline.date = "bad date"; baseline.total = "bad total"
        baseline.lines = [.blank()]; baseline.lines[0].amount = "bad amount"; baseline.lines[0].quantity = "bad quantity"
        var corrected = baseline; corrected.total = "1.00"
        XCTAssertTrue(ReceiptFocusedCorrection.canApply(corrected, replacing: baseline)); XCTAssertFalse(corrected.canSaveDraft)
        var invalid = corrected; invalid.lines[0].quantity = "still bad"
        XCTAssertFalse(ReceiptFocusedCorrection.canApply(invalid, replacing: baseline))
        var repaired = corrected; repaired.lines[0].quantity = ""; repaired.lines[0].amount = "1.00"; repaired.date = "2026-10-09"
        XCTAssertTrue(ReceiptFocusedCorrection.canApply(repaired, replacing: corrected)); XCTAssertTrue(repaired.canSaveDraft)
        XCTAssertFalse(repaired.canFinalize)
    }
    func testAddingLinkedManualPurchaseRetainsUnassignedGroupIdentityAndDeletingFlaggedLineReopens() throws {
        let original = try extraction("FICTIONAL STORE CAD\n2026-10-09\nITEM 1.00\n2.00\nCOUPON 1.00\nSUBTOTAL 3.00\nTOTAL 3.00")
        var draft = ReceiptReviewDraft(fields: original.fields)
        let before = ReceiptReviewGuidance.checks(draft: draft, extraction: original)
        let unassigned = try XCTUnwrap(before.first { $0.title == "Check unassigned amounts" })
        var line = EditableReceiptLine.blank(); line.name = "TEST ADDED"; line.amount = "2.00"; line.sourceLineIDs = unassigned.sourceLineIDs
        draft.lines.append(line); draft.guidanceChecks = [unassigned.id: unassigned.signature(in: draft)]
        let after = try XCTUnwrap(ReceiptReviewGuidance.checks(draft: draft, extraction: original).first { $0.id == unassigned.id })
        XCTAssertEqual(after.target, .source); XCTAssertTrue(after.isChecked(in: draft))
        let sign = try XCTUnwrap(before.first { $0.title == "Check the adjustment" })
        let signature = sign.signature(in: draft)
        draft.guidanceChecks?[sign.id] = signature
        if case .line(let id) = sign.target { draft.lines.removeAll { $0.id == id } }
        let removed = try XCTUnwrap(ReceiptReviewGuidance.checks(draft: draft, extraction: original).first { $0.id == sign.id })
        XCTAssertEqual(removed.target, .source); XCTAssertFalse(removed.isChecked(in: draft))
        XCTAssertEqual(Set(removed.sourceLineIDs), Set(sign.sourceLineIDs))
    }
    func testChangingEitherSummaryValueReopensSummaryChecks() {
        var draft = ReceiptReviewDraft(); draft.subtotal = "1.00"; draft.total = "1.00"
        let check = ReceiptReviewGuidance(id: "summary", title: "Verify", message: "", target: .total, sourceLineIDs: [], requiresCorrection: false)
        draft.guidanceChecks = [check.id: check.signature(in: draft)]
        draft.subtotal = "2.00"; XCTAssertFalse(check.isChecked(in: draft))
    }
    func testSourceFocusPreservesCoordinatesAndShowsLongReceiptLastRow() throws {
        let box = try ReceiptOCRBox(x: 0.1, y: 0.02, width: 0.8, height: 0.01)
        let focus = try XCTUnwrap(ReceiptSourceGeometry.focus(boxes: [box], size: CGSize(width: 800, height: 10000)))
        XCTAssertTrue(focus.contains(CGPoint(x: 400, y: 9750)))
        XCTAssertGreaterThan(focus.minY, 9000); XCTAssertLessThanOrEqual(focus.maxY, 10000)
        XCTAssertEqual(box.y, 0.02); XCTAssertNil(ReceiptSourceGeometry.focus(boxes: [], size: CGSize(width: 800, height: 10000)))
    }
    @MainActor func testNormalAndLongFocusedAmountRepairThenExplicitReviewCanFinalize() throws {
        for mode in ["correction-normal", "correction-long"] {
            let (bytes, extraction, draft) = try SyntheticCorrectionPreview.fixture(mode)
            let workspace = ReceiptWorkspace(); workspace.active = true; workspace.flow = .review
            workspace.image = try ReceiptImage.decode(bytes); workspace.extraction = extraction; workspace.draft = draft
            let check = try XCTUnwrap(ReceiptReviewGuidance.checks(draft: draft, extraction: extraction).first { if case .line = $0.target { return true }; return false })
            var corrected = draft; corrected.lines[corrected.lines.count - 1].amount = "1.00"
            workspace.applyFocusedCorrection(corrected, check: check)
            XCTAssertTrue(workspace.draft.reconciliation.issues.isEmpty)
            XCTAssertFalse(workspace.draft.canFinalize)
            workspace.showSource(); workspace.sourceVisible = false; workspace.draft.sourceChecked = true
            XCTAssertTrue(workspace.draft.canFinalize)
        }
    }
    @MainActor func testPartialMultiRowCorrectionDoesNotAcknowledgeUncheckedRows() throws {
        let original = try extraction("FICTIONAL NO FRILLS CAD\n2026-10-09\nITEM 1.00\n2.00\n3.00\nSUBTOTAL 6.00\nTOTAL 6.00")
        let workspace = ReceiptWorkspace(); workspace.active = true; workspace.flow = .review
        workspace.image = try ReceiptImage.decode(SyntheticFixture.imageData()); workspace.extraction = original
        workspace.draft = ReceiptReviewDraft(fields: original.fields)
        let check = try XCTUnwrap(ReceiptReviewGuidance.checks(draft: workspace.draft, extraction: original).first { $0.title == "Check unassigned amounts" })
        XCTAssertEqual(check.sourceLineIDs.count, 2)
        var input = workspace.draft; var line = EditableReceiptLine.blank()
        line.name = "TEST EXPLICIT PURCHASE"; line.amount = "2.00"; line.sourceLineIDs = [check.sourceLineIDs[0]]; input.lines.append(line)
        workspace.applyFocusedCorrection(input, check: check, markChecked: false)
        XCTAssertEqual(workspace.draft.lines.count, 2); XCTAssertFalse(check.isChecked(in: workspace.draft))
        XCTAssertFalse(workspace.draft.sourceChecked); XCTAssertFalse(workspace.draft.canFinalize)
        XCTAssertEqual(workspace.extraction, original)
    }
    @MainActor func testZoomCommandsOnlyAffectTheirIntendedViewer() {
        let first = ZoomReceiptImage.Coordinator(), second = ZoomReceiptImage.Coordinator()
        let views = [UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 240)), UIScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))]
        for (coordinator, view) in zip([first, second], views) {
            coordinator.imageView.frame = CGRect(x: 0, y: 0, width: 800, height: 3000)
            view.addSubview(coordinator.imageView); view.contentSize = coordinator.imageView.bounds.size
            view.delegate = coordinator; view.minimumZoomScale = 0.4; view.maximumZoomScale = 4
            view.setZoomScale(1, animated: false); view.contentOffset = CGPoint(x: 0, y: 1500)
            coordinator.scrollView = view; coordinator.reduceMotion = true; coordinator.observeZoom()
        }
        defer { first.stopObserving(); second.stopObserving() }
        let originalOffset = views[0].contentOffset
        NotificationCenter.default.post(name: .receiptZoomIn, object: nil, userInfo: ["target": second.zoomTarget])
        XCTAssertEqual(views[1].zoomScale, 1.6, accuracy: 0.001); XCTAssertEqual(views[0].zoomScale, 1, accuracy: 0.001)
        NotificationCenter.default.post(name: .receiptZoomReset, object: nil, userInfo: ["target": second.zoomTarget])
        XCTAssertEqual(views[1].zoomScale, 0.4, accuracy: 0.001); XCTAssertEqual(views[1].contentOffset, .zero)
        XCTAssertEqual(views[0].contentOffset, originalOffset); XCTAssertEqual(views[0].zoomScale, 1, accuracy: 0.001)
        NotificationCenter.default.post(name: .receiptZoomOut, object: nil)
        XCTAssertEqual(views[0].zoomScale, 1); XCTAssertEqual(views[1].zoomScale, 0.4, accuracy: 0.001)
    }
    @MainActor func testApplySaveReopenAndEditPreserveGuidanceOriginalAndDraftGates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("P204-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = ReceiptWorkspace(directory: directory, keyProvider: Key())
        workspace.activate(protectedDataAvailable: true)
        try await wait { workspace.availability == .ready }
        let (bytes, original, input) = try SyntheticCorrectionPreview.fixture("correction-difficult")
        workspace.image = try ReceiptImage.decode(bytes); workspace.extraction = original; workspace.draft = input; workspace.flow = .review
        let check = try XCTUnwrap(ReceiptReviewGuidance.checks(draft: input, extraction: original).first { !$0.requiresCorrection && $0.title == "Check unassigned amounts" })
        workspace.applyFocusedCorrection(input, check: check)
        XCTAssertTrue(check.isChecked(in: workspace.draft)); XCTAssertTrue(workspace.draft.sourceOpened); XCTAssertFalse(workspace.draft.sourceChecked)
        XCTAssertFalse(workspace.draft.canFinalize); XCTAssertEqual(workspace.extraction, original)
        workspace.save(asDraft: true); try await wait { workspace.flow == .detail && !workspace.saving }
        let record = try XCTUnwrap(workspace.selected)
        XCTAssertFalse(ReceiptCompletion.isComplete(record)); XCTAssertFalse(record.revisions.isEmpty)
        workspace.open(record); try await wait { workspace.image != nil }
        workspace.edit()
        XCTAssertTrue(check.isChecked(in: workspace.draft)); XCTAssertFalse(workspace.draft.sourceChecked)
        XCTAssertEqual(workspace.extraction, original); XCTAssertEqual(workspace.image?.bytes, bytes)
        workspace.updateDraft { $0.lines[0].amount = "2.00" }
        XCTAssertFalse(check.isChecked(in: workspace.draft)); XCTAssertFalse(workspace.draft.sourceOpened)
        let before = workspace.draft
        var malformed = before; malformed.total = "bad"
        workspace.applyFocusedCorrection(malformed, check: check)
        XCTAssertEqual(workspace.draft, before)
        workspace.suspend(); workspace.applyFocusedCorrection(input, check: check)
        XCTAssertEqual(workspace.draft, ReceiptReviewDraft())
    }
    @MainActor private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<200 { if predicate() { return }; try await Task.sleep(for: .milliseconds(25)) }
        XCTFail("Disposable workflow did not settle")
    }
}
