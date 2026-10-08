import XCTest
import UIKit
import ImageIO
import UniformTypeIdentifiers
@testable import RcpLens

final class ReceiptWorkflowTests: XCTestCase, @unchecked Sendable {
    func testElasticStackIsOrderedReversibleAndAnchoredAtThePocket() {
        for height: CGFloat in [480, 656, 820] {
            let curve = ReceiptStackProjection(viewportHeight: height, readingY: height / 3 - 30, anchor: height - 332)
            XCTAssertEqual(curve.position(curve.anchor), curve.anchor, accuracy: 0.0001)
            for y: CGFloat in stride(from: -500, through: 2500, by: 20) {
                let visibleY = curve.position(y)
                XCTAssertEqual(curve.logicalPosition(visibleY), y, accuracy: 0.0001)
                let gap = curve.position(y + 136) - visibleY
                XCTAssertGreaterThanOrEqual(gap, 36 - 0.0001)
                XCTAssertLessThanOrEqual(gap, 224 + 0.0001)
            }
            let focus = curve.logicalPosition(curve.readingY)
            let speed = (curve.position(focus + 0.1) - curve.position(focus - 0.1)) / 0.2
            XCTAssertEqual(speed, 224 / 136, accuracy: 0.001)
            for pull: CGFloat in [0, 20, 100] {
                XCTAssertEqual(curve.displayedPosition(curve.anchor - pull, endPull: pull), curve.anchor - pull, accuracy: 0.001)
            }
        }
    }
    struct Key: ReceiptStoreKeyProvider {
        func loadKey() -> Data? { Data(repeating: 0x5a, count: 32) }
        func createKey() -> Data { Data(repeating: 0x5a, count: 32) }
    }
    @MainActor func testAddingTenDemoReceiptsPreservesExistingReceiptAndSettingsAndIsIdempotent() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ReceiptStore(directory: dir, keyProvider: Key())
        let extraction = try ReceiptParser.extraction(OCRResult(lines: lines("FICTIONAL EXISTING CAD\n2026-10-07\nTEST ITEM 1.00\nSUBTOTAL 1.00\nTOTAL 1.00"), revision: 3))
        let old = try await store.create(extraction: extraction, originalImage: SyntheticFixture.imageData(), mediaType: "image/png")
        let preferences = ReceiptWalletSettings(leftSwipe: .delete, paperAppearance: .alwaysWhite)
        try await store.saveWalletSettings(preferences); try await store.close()
        let model = ReceiptWorkspace(directory: dir, keyProvider: Key())
        model.activate(protectedDataAvailable: true); try await wait { model.availability == .ready }
        let added = await model.addFictionalDemoReceipts()
        XCTAssertEqual(added, 10); XCTAssertEqual(model.receipts.count, 11)
        XCTAssertEqual(model.receipts.first { $0.id == old.id }, old)
        XCTAssertEqual(model.walletSettings, preferences)
        let samples = model.receipts.filter { $0.id != old.id }
        XCTAssertTrue(samples.allSatisfy { ($0.current.fields.merchant ?? "").hasPrefix("DEMO ") && ReceiptCompletion.isComplete($0) })
        let repeated = await model.addFictionalDemoReceipts()
        XCTAssertEqual(repeated, 0); XCTAssertEqual(model.receipts.count, 11)
        model.suspend()
    }
    private func lines(_ text: String) -> [ReceiptOCRLine] {
        text.split(separator: "\n").map { ReceiptOCRLine(id: UUID(), text: String($0), engineConfidence: nil) }
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("T05-unit-\(UUID())") }
    private func draft() -> ReceiptReviewDraft {
        var draft = ReceiptReviewDraft()
        draft.merchant = "FICTIONAL SHOP"; draft.date = "2026-10-07"; draft.currency = "CAD"
        draft.lines = [.init(id: UUID(), kind: "purchase", name: "FICTIONAL APPLES", quantity: "1.250", amount: "10.00", sourceLineIDs: []),
                       .init(id: UUID(), kind: "discount", name: "Coupon", quantity: "", amount: "-1.00", sourceLineIDs: []),
                       .init(id: UUID(), kind: "deposit", name: "Deposit", quantity: "", amount: "0.30", sourceLineIDs: []),
                       .init(id: UUID(), kind: "tax", name: "Tax", quantity: "", amount: "1.20", sourceLineIDs: [])]
        draft.subtotal = "9.30"; draft.total = "10.50"; draft.sourceOpened = true; draft.sourceChecked = true
        return draft
    }
    func testExactAmountsGroupedSignsAndBounds() {
        for (text, value) in [("1,234.56", Int64(123456)), ("-1,234.56", -123456), ("1,234.56-", -123456), ("$12.34", 1234), (".30", Int64.min), ("0", 0), ("0.01", 1)] {
            XCTAssertEqual(ExactInput.money(text), value == Int64.min ? nil : value)
        }
        for bad in ["1,23.45", "1,23,456.78", "1234,567.89", "1.234,56", "--1.00", "-1.00-", "NaN", "1.001", "9999999999999999999999999", "1e3"] { XCTAssertNil(ExactInput.money(bad)) }
        XCTAssertEqual(ExactInput.format(Int64.min), "-92233720368547758.08")
        XCTAssertNil(ExactInput.decimal("0")); XCTAssertNil(ExactInput.decimal("-1")); XCTAssertNil(ExactInput.decimal("1.0000000000"))
        XCTAssertEqual(ExactInput.quantity(ExactInput.decimal("0.375")), "0.375")
        XCTAssertNil(ExactInput.date("2026-02-30")); XCTAssertNotNil(ExactInput.date("2024-02-29"))
    }
    func testParserNoPartialNumbersOrFalseCurrency() {
        let p = ReceiptParser.parse(lines("NO FRILLS\n2026-10-07\nSTORE CA\nAPPLE 1,234.56\nSUBTOTAL 1,234.56\nTOTAL 1,234.56"))
        XCTAssertEqual(p.lines.first?.amount, 123456); XCTAssertEqual(p.total, 123456); XCTAssertNil(p.currency)
        XCTAssertNil(p.fields().items.first?.amount)
        XCTAssertEqual(ReceiptParser.parse(lines("COSTCO\nCA$\nAPPLE 1.00\nTOTAL 1.00")).currency, .cad)
        for bad in ["1,23.45", "1,23,456.78", "12345678.90", "1.234,56", "11.000", "1.00.30"] {
            let parsed = ReceiptParser.parse(lines("T&T\nAPPLE \(bad)\nTOTAL \(bad)"))
            XCTAssertNil(parsed.total); XCTAssertTrue(parsed.lines.isEmpty)
            XCTAssertTrue(parsed.issues.contains { $0.code == "amount_unparsed_check_source" })
        }
        let signed = ReceiptParser.parse(lines("COSTCO\nAPPLE 11.00\nCOUPON 1.00-\nTOTAL 10.00"))
        XCTAssertEqual(signed.lines.map(\.amount), [1100, -100])
    }
    func testDatePickerBridgePreservesCivilDayAcrossDSTAndTimeZones() throws {
        for zone in ["America/Toronto", "Pacific/Kiritimati", "Pacific/Pago_Pago"] {
            let timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            for text in ["2024-02-29", "2026-03-08", "2026-11-01", "2026-12-31"] {
                let date = try XCTUnwrap(ReceiptDateSelection.date(text, timeZone: timeZone))
                XCTAssertEqual(ReceiptDateSelection.text(date, timeZone: timeZone), text)
            }
            XCTAssertNil(ReceiptDateSelection.date("", timeZone: timeZone))
            XCTAssertNil(ReceiptDateSelection.date("2026-02-29", timeZone: timeZone))
        }
    }
    func testGeometryGroupingOrderingAndSourceIdentity() throws {
        func obs(_ text: String, x: Double, y: Double) throws -> ReceiptOCRLine {
            .init(id: UUID(), text: text, engineConfidence: 0.9,
                  boundingBox: try ReceiptOCRBox(x: x, y: y, width: 0.2, height: 0.02))
        }
        let name = try obs("APPLE", x: 0.1, y: 0.7), amount = try obs("3.00", x: 0.7, y: 0.7001)
        let total = try obs("TOTAL 3.00", x: 0.1, y: 0.3), merchant = try obs("COSTCO CAD", x: 0.1, y: 0.9)
        let source = [total, amount, name, merchant]
        let parsed = ReceiptParser.parse(source)
        XCTAssertEqual(parsed.lines.count, 1); XCTAssertEqual(parsed.lines[0].sourceLineIDs, [name.id, amount.id])
        XCTAssertEqual(parsed.total, 300)
        let noBox = ReceiptOCRLine(id: UUID(), text: "MANUAL SOURCE", engineConfidence: nil)
        let mixed = [total, noBox, name, amount]
        XCTAssertEqual(ReceiptParser.rows(mixed).map(\.ids), mixed.map { [$0.id] })
        XCTAssertNil(ReceiptParser.parse(lines("COSTCO\n2026-02-30\nAPPLE 1.00\nTOTAL 1.00")).date)
    }
    func testLongReceiptRetainsAllRowsAndRepeatedLines() {
        let text = "NO FRILLS CAD\n2026-10-07\n" + Array(repeating: "APPLE 1.00", count: 300).joined(separator: "\n") + "\nTOTAL 300.00"
        let observations = lines(text)
        let parsed = ReceiptParser.parse(observations)
        XCTAssertEqual(parsed.lines.count, 300)
        XCTAssertEqual(Set(parsed.lines.map(\.id)).count, 300)
        XCTAssertEqual(parsed.lines.flatMap(\.sourceLineIDs).count, 300)
        XCTAssertEqual(parsed.total, 30000)
    }
    func testReconciliationDepositDiscountAndSourceGate() throws {
        var d = draft()
        XCTAssertTrue(d.reconciliation.issues.isEmpty); XCTAssertTrue(d.canFinalize)
        XCTAssertEqual(d.reconciliation.difference, 0)
        d.sourceChecked = false; XCTAssertFalse(d.canFinalize)
        d.sourceChecked = true; d.sourceOpened = false; XCTAssertFalse(d.canFinalize)
        d.sourceOpened = true; d.total = "10.51"
        XCTAssertEqual(d.reconciliation.difference, 1); XCTAssertFalse(d.canFinalize); XCTAssertTrue(d.canSaveDraft)
        d.total = "10.50"; d.subtotal = "9.50"; XCTAssertFalse(d.canFinalize)
        d.subtotal = ""; XCTAssertFalse(d.canFinalize)
        d.subtotalNotPrinted = true; XCTAssertTrue(d.canFinalize)
        d.lines[1].amount = "1.00"; XCTAssertFalse(d.canFinalize)
        d.lines[0].quantity = "-1"; XCTAssertFalse(d.canSaveDraft)
    }
    func testCurrencyUnknownEditableDraftRoundTripAndAtomicCorrection() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ReceiptStore(directory: dir, keyProvider: Key())
        let extraction = try ReceiptParser.extraction(OCRResult(lines: lines("NO FRILLS\nAPPLE 12.34\nTOTAL 12.34"), revision: 3))
        var d = ReceiptReviewDraft(parsed: try JSONDecoder().decode(ParsedReceipt.self, from: extraction.rawParserOutput))
        XCTAssertEqual(d.currency, ""); XCTAssertTrue(d.canSaveDraft)
        XCTAssertNil(d.fields.total)
        let raw = try JSONEncoder().encode(d)
        let record = try await store.create(extraction: extraction, originalImage: SyntheticFixture.imageData(), mediaType: "image/png", correction: d.fields, reviewInput: raw)
        XCTAssertEqual(record.revisions.count, 2); XCTAssertEqual(record.original, extraction)
        try await store.close()
        let reopened = try ReceiptStore(directory: dir, keyProvider: Key())
        let fetched = try await reopened.receipt(id: record.id)
        let loaded = try XCTUnwrap(fetched)
        XCTAssertEqual(try JSONDecoder().decode(ReceiptReviewDraft.self, from: XCTUnwrap(loaded.current.reviewInput)), d)
        XCTAssertFalse(ReceiptCompletion.isComplete(loaded))
        d.currency = "CAD"; d.date = "2026-10-07"; d.subtotalNotPrinted = true; d.sourceOpened = true; d.sourceChecked = true
        let revised = try await reopened.revise(id: record.id, expectedRevision: loaded.current.id, fields: d.fields, review: .sourceReviewed, reviewInput: JSONEncoder().encode(d))
        XCTAssertEqual(revised.original, extraction); XCTAssertEqual(revised.current.fields.total?.minorUnits, 1234); XCTAssertTrue(ReceiptCompletion.isComplete(revised))
        try await reopened.delete(id: record.id)
        let empty = try await reopened.receipts()
        XCTAssertTrue(empty.isEmpty); try await reopened.close()
    }
    func testRevocationAtWriteFaultRollsBackWithoutOrphanOrDuplicate() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let lease = ReceiptOperationPermit()
        let store = try ReceiptStore(directory: dir, keyProvider: Key(), fault: { point in if point == .beforeCommit { lease.revoke() } })
        let extraction = try ReceiptParser.extraction(OCRResult(lines: lines("COSTCO CAD\nAPPLE 1.00\nTOTAL 1.00"), revision: 3))
        do { _ = try await store.create(extraction: extraction, originalImage: SyntheticFixture.imageData(), mediaType: "image/png", correction: draft().fields, permit: lease); XCTFail("Revoked save must roll back") }
        catch is CancellationError { }
        let empty = try await store.receipts()
        XCTAssertTrue(empty.isEmpty)
        try await store.close()
        let reopened = try ReceiptStore(directory: dir, keyProvider: Key())
        _ = try await reopened.create(extraction: extraction, originalImage: SyntheticFixture.imageData(), mediaType: "image/png", correction: draft().fields)
        let retried = try await reopened.receipts()
        XCTAssertEqual(retried.count, 1)
        try await reopened.purgeAllReceipts(); try await reopened.close()
    }
    func testRevokedRevisionAndDeleteLeaveCommittedReceiptUnchanged() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ReceiptStore(directory: dir, keyProvider: Key())
        let extraction = try ReceiptParser.extraction(OCRResult(lines: lines("COSTCO CAD\nAPPLE 1.00\nTOTAL 1.00"), revision: 3))
        let old = try await store.create(extraction: extraction, originalImage: SyntheticFixture.imageData(), mediaType: "image/png")
        let permit = ReceiptOperationPermit(); permit.revoke()
        do { _ = try await store.revise(id: old.id, expectedRevision: old.current.id, fields: draft().fields, review: .sourceReviewed, permit: permit); XCTFail("Revoked edit must fail") } catch is CancellationError { }
        do { try await store.delete(id: old.id, permit: permit); XCTFail("Revoked delete must fail") } catch is CancellationError { }
        let unchanged = try await store.receipt(id: old.id)
        XCTAssertEqual(unchanged, old)
        try await store.close()
    }
    @MainActor private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Timed out waiting for a synthetic workflow state")
    }
    @MainActor func testBackgroundClearsStateAndFreshForegroundWaitsForClose() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = ReceiptWorkspace(directory: dir, keyProvider: Key())
        model.activate(protectedDataAvailable: true); try await wait { model.availability == .ready }
        model.startImport { try SyntheticFixture.imageData() }
        try await wait { model.flow == .review }
        model.draft = draft(); model.showSource()
        model.suspend()
        XCTAssertNil(model.image); XCTAssertNil(model.extraction); XCTAssertNil(model.selected)
        XCTAssertTrue(model.receipts.isEmpty); XCTAssertEqual(model.draft, ReceiptReviewDraft()); XCTAssertFalse(model.sourceVisible)
        model.activate(protectedDataAvailable: true); try await wait { model.availability == .ready }
        XCTAssertEqual(model.flow, .wallet); XCTAssertTrue(model.receipts.isEmpty)
        model.activate(protectedDataAvailable: false); XCTAssertEqual(model.availability, .closed)
        model.suspend()
    }
    @MainActor func testCancelledImportCannotRepopulateNewSessionAndEditsResetReview() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = ReceiptWorkspace(directory: dir, keyProvider: Key())
        model.activate(protectedDataAvailable: true); try await wait { model.availability == .ready }
        model.startImport { try await Task.sleep(for: .milliseconds(80)); return try SyntheticFixture.imageData() }
        model.cancelImport(); try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(model.image); XCTAssertEqual(model.flow, .wallet)
        model.startImport { try await Task.sleep(for: .milliseconds(100)); return try SyntheticFixture.imageData() }
        model.suspend(); model.activate(protectedDataAvailable: true)
        try await wait { model.availability == .ready }; try await Task.sleep(for: .milliseconds(150))
        XCTAssertNil(model.image); XCTAssertEqual(model.flow, .wallet)
        model.draft = draft(); model.updateDraft { $0.merchant = "CHANGED SYNTHETIC" }
        XCTAssertFalse(model.draft.sourceOpened); XCTAssertFalse(model.draft.sourceChecked)
        model.draft.sourceOpened = true; model.draft.sourceChecked = true
        XCTAssertTrue(model.draft.sourceChecked) // Confirmation does not reset itself.
        model.suspend()
    }
    @MainActor func testManualFallbackForNoTextAndMalformedInput() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = ReceiptWorkspace(directory: dir, keyProvider: Key())
        model.activate(protectedDataAvailable: true); try await wait { model.availability == .ready }
        model.startImport { Data([0, 1, 2, 3]) }; try await wait { model.flow == .failed }
        XCTAssertNil(model.image)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let blank = UIGraphicsImageRenderer(size: CGSize(width: 100, height: 100), format: format).pngData { _ in UIColor.white.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: 100, height: 100)) }
        model.startImport { blank }; try await wait { model.flow == .failed }
        XCTAssertNotNil(model.image); model.manualReview(); XCTAssertEqual(model.flow, .review)
        XCTAssertNotNil(model.extraction); model.draft = draft(); model.save(asDraft: false)
        try await wait { model.flow == .detail }
        XCTAssertTrue(ReceiptCompletion.isComplete(try XCTUnwrap(model.selected)))
        model.deleteSelected(); try await wait { model.flow == .wallet }; XCTAssertTrue(model.receipts.isEmpty)
        model.suspend()
    }
    @MainActor func testOrientedDisplayAndVisionGeometryOnMirroredRotation() async throws {
        let png = try SyntheticFixture.imageData()
        let source = try XCTUnwrap(CGImageSourceCreateWithData(png as CFData, nil))
        let cg = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let out = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, cg, [kCGImagePropertyOrientation: 5] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let bytes = out as Data
        let display = try XCTUnwrap(ReceiptDisplayImage.make(bytes))
        XCTAssertEqual(display.imageOrientation, .up)
        XCTAssertEqual(display.size.width / display.size.height, CGFloat(cg.height) / CGFloat(cg.width), accuracy: 0.001)
        let result = try await Task.detached { try ReceiptRecognitionJob().run(ReceiptImage.decode(bytes)) }.value
        XCTAssertFalse(result.lines.isEmpty)
        XCTAssertTrue(result.lines.allSatisfy { $0.boundingBox != nil })
        let rendered = try XCTUnwrap(display.cgImage)
        for box in result.lines.compactMap(\.boundingBox) {
            let rect = CGRect(x: box.x * Double(rendered.width), y: (1 - box.y - box.height) * Double(rendered.height),
                              width: box.width * Double(rendered.width), height: box.height * Double(rendered.height))
            let crop = try XCTUnwrap(rendered.cropping(to: rect.integral))
            var pixels = [UInt8](repeating: 255, count: 32 * 32 * 4)
            let dark = pixels.withUnsafeMutableBytes { pointer -> Int in
                let context = CGContext(data: pointer.baseAddress, width: 32, height: 32, bitsPerComponent: 8, bytesPerRow: 128,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(crop, in: CGRect(x: 0, y: 0, width: 32, height: 32))
                return stride(from: 0, to: 32 * 32 * 4, by: 4).filter { pointer[$0] < 200 && pointer[$0 + 1] < 200 && pointer[$0 + 2] < 200 }.count
            }
            XCTAssertGreaterThan(dark, 2, "Oriented OCR regions must contain printed ink in the display image")
        }
        XCTAssertEqual(try ReceiptImage.decode(bytes).bytes, bytes)
    }
    @MainActor func testDeniedInputAndSaveDuringBackgroundNeverRestorePrivateState() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = ReceiptWorkspace(directory: dir, keyProvider: Key())
        model.activate(protectedDataAvailable: true); try await wait { model.availability == .ready }
        model.startImport { throw ImportFailure.unavailableFile }; try await wait { model.flow == .failed }
        XCTAssertEqual(model.errorMessage, ImportFailure.unavailableFile.message); XCTAssertNil(model.image)
        model.startImport { try SyntheticFixture.imageData() }; try await wait { model.flow == .review }
        model.draft = draft(); model.save(asDraft: false); model.suspend()
        model.activate(protectedDataAvailable: true); try await wait { model.availability == .ready }
        XCTAssertEqual(model.flow, .wallet); XCTAssertNil(model.image); XCTAssertNil(model.selected); XCTAssertFalse(model.saving)
        XCTAssertLessThanOrEqual(model.receipts.count, 1) // An explicit committed save may survive; a queued one is revoked.
        model.suspend()
    }
    func testFiveHundredReceiptsRemainListableWithoutPlaintextThumbnails() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ReceiptStore(directory: dir, keyProvider: Key())
        let extraction = try ReceiptParser.extraction(OCRResult(lines: lines("COSTCO CAD\n2026-10-07\nAPPLE 1.00\nSUBTOTAL 1.00\nTOTAL 1.00"), revision: 3))
        let image = try SyntheticFixture.imageData()
        for _ in 0..<500 { _ = try await store.create(extraction: extraction, originalImage: image, mediaType: "image/png") }
        let start = ContinuousClock.now
        let records = try await store.receipts()
        XCTAssertEqual(records.count, 500)
        XCTAssertLessThan(start.duration(to: .now), .seconds(10))
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.contains { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension) })
        try await store.purgeAllReceipts(); try await store.close()
    }

    @MainActor func testSceneDeactivationInstallsOpaqueNativeCoverBeforeSnapshot() throws {
        let window = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first)
        ReceiptPrivacyCover.hide()
        NotificationCenter.default.post(name: UIScene.willDeactivateNotification, object: window.windowScene)
        XCTAssertTrue(ReceiptPrivacyCover.isCovered)
        XCTAssertNotNil(window.subviews.first { $0.accessibilityIdentifier == "privacyCover" })
        XCTAssertEqual(window.subviews.last?.backgroundColor, .systemBackground)
        ReceiptPrivacyCover.hide()
        XCTAssertFalse(ReceiptPrivacyCover.isCovered)
    }

    @MainActor func testImmediatePaperOpeningWaitsForOriginalAndCannotResurrectAfterReturn() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ReceiptStore(directory: dir, keyProvider: Key())
        let extraction = try ReceiptParser.extraction(OCRResult(lines: lines("FICTIONAL SHOP CAD\n2026-10-07\nTEST ITEM 1.00\nSUBTOTAL 1.00\nTOTAL 1.00"), revision: 3))
        _ = try await store.create(extraction: extraction, originalImage: SyntheticFixture.imageData(), mediaType: "image/png")
        try await store.close()
        let model = ReceiptWorkspace(directory: dir, keyProvider: Key())
        model.activate(protectedDataAvailable: true); try await wait { model.availability == .ready }
        let record = try XCTUnwrap(model.receipts.first)
        model.open(record)
        XCTAssertEqual(model.flow, .detail); XCTAssertEqual(model.selected?.id, record.id)
        XCTAssertNil(model.image)
        model.edit(); XCTAssertEqual(model.flow, .detail, "Editing must wait for immutable evidence")
        model.backToWallet(); try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(model.flow, .wallet); XCTAssertNil(model.selected); XCTAssertNil(model.image)
        model.open(record); try await wait { model.image != nil }
        model.edit(); XCTAssertEqual(model.flow, .review)
        model.suspend(); XCTAssertNil(model.selected); XCTAssertNil(model.image)
    }

    @MainActor func testCommittedSaveAndDeleteRemainTruthfulWhenWalletRefreshFails() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let model = ReceiptWorkspace(directory: dir, keyProvider: Key())
        model.activate(protectedDataAvailable: true); try await wait { model.availability == .ready }
        model.startImport { try SyntheticFixture.imageData() }; try await wait { model.flow == .review }
        model.draft = draft(); model.failNextListRefresh = true; model.save(asDraft: false)
        try await wait { model.flow == .detail && !model.saving }
        let committedID = try XCTUnwrap(model.selected?.id)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.receipts.map(\.id), [committedID], "A committed receipt is reopenable even before a successful list refresh")
        model.backToWallet(); model.open(try XCTUnwrap(model.receipts.first))
        try await wait { model.flow == .detail && model.image != nil }
        model.edit(); model.draft = draft(); model.draft.merchant = "SYNTHETIC REVISED STORE"
        model.failNextListRefresh = true; model.save(asDraft: false)
        try await wait { model.flow == .detail && !model.saving }
        XCTAssertEqual(model.receipts.count, 1)
        XCTAssertEqual(model.receipts.first?.current.fields.merchant, "SYNTHETIC REVISED STORE")
        XCTAssertEqual(model.receipts.first?.current.id, model.selected?.current.id)
        model.edit(); model.draft = draft(); model.save(asDraft: false)
        try await wait { model.flow == .detail && !model.saving }
        XCTAssertEqual(model.receipts.count, 1); XCTAssertEqual(model.selected?.id, committedID)
        model.failNextListRefresh = true; model.deleteSelected()
        try await wait { model.flow == .wallet && !model.saving }
        XCTAssertNil(model.selected); XCTAssertNil(model.image); XCTAssertNil(model.extraction)
        XCTAssertFalse(model.sourceVisible); XCTAssertTrue(model.receipts.isEmpty)
        model.suspend(); model.activate(protectedDataAvailable: true); try await wait { model.availability == .ready }
        XCTAssertTrue(model.receipts.isEmpty); model.suspend()
    }

}
