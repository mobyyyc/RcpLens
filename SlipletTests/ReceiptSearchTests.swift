import XCTest
import Foundation
@testable import Sliplet

enum SearchFixture {
    static func extraction(merchant: String? = "FICTIONAL CORNER MART", date: ReceiptDate? = try! .init(year: 2026, month: 10, day: 8)) -> ReceiptExtraction {
        let names = ["ORG MLK 2%", "CREME OCR", "REMOVED APPLES"]
        var rows = names.map { ReceiptOCRLine(id: UUID(), text: $0 + " RAWTOKEN", engineConfidence: nil) }
        let items = rows.enumerated().map { index, row in ReceiptLine(id: UUID(), description: names[index], sku: index == 0 ? "OLD-123456" : nil,
            quantity: nil, unitPrice: nil, amount: .init(minorUnits: Int64(index + 1) * 100, currency: .cad), taxMarker: nil, sourceLineIDs: [row.id]) }
        rows.append(.init(id: UUID(), text: "UNPARSED FENNEL 9.99", engineConfidence: nil))
        let fields = ReceiptFields(merchant: merchant, purchaseDate: date, currency: .cad, items: items, adjustments: [], subtotal: nil, total: .init(minorUnits: 600, currency: .cad))
        return ReceiptExtraction(capturedAt: Date(timeIntervalSince1970: 1700000000), recognizer: "Fictional", recognizerVersion: "1", parser: "Fictional", parserVersion: "1", rawOCR: rows, rawParserOutput: Data("fictional parser bytes".utf8), fields: fields, issues: [])
    }
    static func correction(_ extraction: ReceiptExtraction) -> ReceiptFields {
        var fields = extraction.fields
        fields.items.removeLast(); fields.items[0].description = "Organic milk"; fields.items[0].sku = "NEW-654321"
        fields.items[1].description = "Crème fraîche 有机苹果 日本茶 한국차"
        fields.total = .init(minorUnits: 300, currency: .cad)
        return fields
    }
    static func record() -> ReceiptRecord {
        let original = extraction(), now = original.capturedAt
        return ReceiptRecord(id: UUID(), createdAt: now, updatedAt: now, original: original,
            asset: .init(id: UUID(), mediaType: "image/png", byteCount: 1, sha256: Data(repeating: 0, count: 32)),
            revisions: [.init(id: UUID(), createdAt: now, fields: original.fields, review: .draft), .init(id: UUID(), createdAt: now, fields: correction(original), review: .sourceReviewed)])
    }
    struct Key: ReceiptStoreKeyProvider {
        func loadKey() -> Data? { Data(repeating: 0x71, count: 32) }
        func createKey() -> Data { Data(repeating: 0x71, count: 32) }
    }
}

@MainActor final class ReceiptSearchTests: XCTestCase {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("T07-fictional-" + UUID().uuidString) }
    private func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 { if predicate() { return }; try await Task.sleep(for: .milliseconds(20)) }
        XCTFail("Timed out waiting for isolated fictional search state")
    }
    func testMerchantRawCorrectedSKUAndSameItemQueryCoverage() throws {
        let record = SearchFixture.record(), index = ReceiptSearchIndex([record])
        for query in ["fictional corner", "FICTIONALCORNERMART", "organic milk", "org mlk", "creme ocr", "rawtoken", "new 654321", "old 123456", "corner milk", "fictionalcorner milk", "fictional-corner old 123456"] {
            XCTAssertEqual(index.results(query: query).map(\.id), [record.id], "Fictional query failed: \(query)")
        }
        XCTAssertTrue(index.results(query: "milk creme").isEmpty, "Words from different purchases must not form an invented item match")
        XCTAssertTrue(index.results(query: "missingword").isEmpty)
        XCTAssertTrue(index.results(query: "---").isEmpty)
        XCTAssertTrue(index.results(query: "milk" + String(repeating: " ", count: 512) + "absent").isEmpty, "Never silently ignore the end of a long query")
        XCTAssertEqual(index.results(query: "   ").count, 1)
        XCTAssertEqual(index.results(query: "mlk").first?.matches.first?.basis, .original)
        XCTAssertEqual(index.results(query: "milk").first?.matches.first?.basis, .corrected)
        XCTAssertEqual(index.results(query: "old 123456").first?.matches.first?.basis, .originalSKU)
        XCTAssertEqual(index.results(query: "new 654321").first?.matches.first?.basis, .sku)
        XCTAssertEqual(index.results(query: "rawtoken").first?.matches.first?.basis, .rawText)
    }
    func testRemovedOriginalIsEvidenceWithoutCurrentItemOrAmount() throws {
        let record = SearchFixture.record()
        let hit = try XCTUnwrap(ReceiptSearchIndex([record]).results(query: "removed apples").first?.matches.first)
        XCTAssertTrue(hit.originalOnly); XCTAssertNil(hit.itemID); XCTAssertFalse(hit.sourceLineIDs.isEmpty)
        XCTAssertFalse(record.current.fields.items.contains { $0.id == hit.itemID })
        XCTAssertEqual(record.original.fields.items.count, 3); XCTAssertEqual(record.current.fields.items.count, 2)
    }
    func testUnlinkedRawOCRIsEvidenceWithoutInventingAPurchase() throws {
        let record = SearchFixture.record()
        let hit = try XCTUnwrap(ReceiptSearchIndex([record]).results(query: "fennel").first?.matches.first)
        XCTAssertTrue(hit.originalOnly); XCTAssertTrue(hit.unparsed); XCTAssertNil(hit.itemID)
        XCTAssertEqual(hit.basis, .rawText); XCTAssertEqual(hit.sourceLineIDs.count, 1)
    }
    func testUnicodeAccentWidthComposedTextAndExplicitAbbreviations() {
        let index = ReceiptSearchIndex([SearchFixture.record()])
        for query in ["creme", "CRÈME", "cre\u{0300}me", "ＣＲＥＭＥ", "苹果", "有机", "日本", "한국", "org mlk", "mil"] {
            XCTAssertEqual(index.results(query: query).count, 1, "Fictional Unicode query failed: \(query)")
        }
        XCTAssertTrue(index.results(query: "蘋果").isEmpty, "No undocumented script conversion or semantic inference")
        XCTAssertEqual(ReceiptSearchText.tokens("CHKN BRD YOG"), ReceiptSearchText.tokens("chicken bread yogurt"))
    }
    func testArchiveStarMonthMissingDateCurrencyAndMerchantFilterSemantics() throws {
        var archived = SearchFixture.record(); archived.organization = .init(archived: true, starred: true)
        let index = ReceiptSearchIndex([archived])
        XCTAssertTrue(index.results(query: "milk").isEmpty)
        XCTAssertEqual(index.results(query: "milk", includeArchived: true).count, 1)
        XCTAssertEqual(index.results(query: "milk", collection: "Archive").count, 1)
        XCTAssertTrue(index.results(query: "milk", collection: "Starred").isEmpty)
        XCTAssertEqual(index.results(query: "milk", collection: "Starred", includeArchived: true).count, 1)
        var record = SearchFixture.record(); var fields = record.current.fields
        fields.purchaseDate = nil; fields.merchant = nil; fields.currency = nil; fields.total = nil
        for i in fields.items.indices { fields.items[i].amount = nil }
        record = ReceiptRecord(id: record.id, createdAt: record.createdAt, updatedAt: record.updatedAt, original: record.original, asset: record.asset,
            revisions: record.revisions + [.init(id: UUID(), createdAt: record.updatedAt, fields: fields, review: .draft)])
        let unknown = ReceiptSearchIndex([record])
        XCTAssertEqual(unknown.results(query: "milk", merchant: .missing, month: .missing).count, 1)
        XCTAssertNil(ReceiptHistory.monthKey(record)); XCTAssertNil(record.current.fields.currency)
        XCTAssertTrue(unknown.results(query: "milk", month: .value("2026-10")).isEmpty)
        XCTAssertTrue(unknown.results(query: "milk", merchant: .value("FICTIONAL CORNER MART")).isEmpty)
        XCTAssertEqual(unknown.results(query: "fictional corner").first?.matches.first?.basis, .merchant)
        let ordered = ReceiptSearchIndex([record, SearchFixture.record()]).results(query: "")
        XCTAssertNotNil(ordered.first?.record.current.fields.purchaseDate); XCTAssertNil(ordered.last?.record.current.fields.purchaseDate)
    }
    func testWorkspaceCreateEditArchiveDeleteFailedRefreshAndRestartKeepIndexConsistent() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let workspace = ReceiptWorkspace(directory: dir, keyProvider: SearchFixture.Key())
        workspace.activate(protectedDataAvailable: true); try await wait { workspace.availability == .ready }
        workspace.startImport { try SyntheticFixture.imageData() }; try await wait { workspace.flow == .review }
        var fields = SearchFixture.correction(SearchFixture.extraction())
        for i in fields.items.indices { fields.items[i].sourceLineIDs = [] }
        workspace.draft = ReceiptReviewDraft(fields: fields)
        workspace.failNextListRefresh = true; workspace.save(asDraft: true)
        try await wait { workspace.flow == .detail && !workspace.saving }
        let saved = try XCTUnwrap(workspace.selected)
        XCTAssertEqual(workspace.searchIndex.results(query: "milk").map(\.id), [saved.id])
        workspace.edit(); workspace.updateDraft { $0.lines[0].name = "Fictional coffee"; $0.merchant = "FICTIONAL REVISED MART" }
        workspace.failNextListRefresh = true; workspace.save(asDraft: true)
        try await wait { workspace.flow == .detail && !workspace.saving }
        XCTAssertTrue(workspace.searchIndex.results(query: "milk").isEmpty)
        XCTAssertEqual(workspace.searchIndex.results(query: "coffee").count, 1)
        XCTAssertEqual(workspace.searchIndex.results(query: "revised").count, 1)
        let revised = try XCTUnwrap(workspace.selected)
        workspace.organize(revised, action: .archive); try await wait { !workspace.saving }
        XCTAssertTrue(workspace.searchIndex.results(query: "coffee").isEmpty)
        XCTAssertEqual(workspace.searchIndex.results(query: "coffee", collection: "Archive").count, 1)
        workspace.suspend(); workspace.activate(protectedDataAvailable: true); try await wait { workspace.availability == .ready }
        let archived = try XCTUnwrap(workspace.receipts.first)
        XCTAssertEqual(workspace.searchIndex.results(query: "coffee", includeArchived: true).count, 1)
        workspace.open(archived); try await wait { workspace.image != nil }
        workspace.failNextListRefresh = true; workspace.deleteSelected(); try await wait { !workspace.saving }
        XCTAssertEqual(workspace.searchIndex.count, 0)
        workspace.suspend(); workspace.activate(protectedDataAvailable: true); try await wait { workspace.availability == .ready }
        XCTAssertTrue(workspace.searchIndex.results(query: "coffee", includeArchived: true).isEmpty); workspace.suspend()
    }
    func testEvidenceAndIndexSurviveEncryptedStoreRestartWithoutPlaintextIndex() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ReceiptStore(directory: dir, keyProvider: SearchFixture.Key())
        let original = SearchFixture.extraction(), image = try SyntheticFixture.imageData()
        let saved = try await store.create(extraction: original, originalImage: image, mediaType: "image/png", correction: SearchFixture.correction(original), review: .sourceReviewed)
        try await store.close()
        let reopened = try ReceiptStore(directory: dir, keyProvider: SearchFixture.Key())
        let records = try await reopened.receipts(), index = ReceiptSearchIndex(records)
        XCTAssertEqual(index.results(query: "removed apples").first?.id, saved.id)
        let bytes = try await reopened.originalImage(receiptID: saved.id); XCTAssertEqual(bytes, image)
        XCTAssertEqual(records.first?.original, original)
        try await reopened.close()
        let raw = try Data(contentsOf: dir.appendingPathComponent("receipts.sqlite"))
        for value in ["FICTIONAL CORNER MART", "Organic milk", "RAWTOKEN", "OLD-123456", "NEW-654321"] { XCTAssertNil(raw.range(of: Data(value.utf8))) }
        let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(files, ["receipts.sqlite"], "No search cache, image or plaintext index file")
    }
    func testBackgroundSynchronouslyClearsQueryIndexMatchAndResults() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ReceiptStore(directory: dir, keyProvider: SearchFixture.Key())
        let original = SearchFixture.extraction()
        _ = try await store.create(extraction: original, originalImage: SyntheticFixture.imageData(), mediaType: "image/png", correction: SearchFixture.correction(original)); try await store.close()
        let workspace = ReceiptWorkspace(directory: dir, keyProvider: SearchFixture.Key())
        workspace.activate(protectedDataAvailable: true); try await wait { workspace.availability == .ready }
        workspace.searchQuery = "milk"; workspace.includeArchived = true; workspace.library = true
        let result = try XCTUnwrap(workspace.searchIndex.results(query: workspace.searchQuery).first)
        workspace.open(result.record, match: result.matches[0]); try await wait { workspace.image != nil }
        workspace.suspend()
        XCTAssertEqual(workspace.searchQuery, ""); XCTAssertNil(workspace.searchMatch); XCTAssertEqual(workspace.searchIndex.count, 0)
        XCTAssertTrue(workspace.receipts.isEmpty); XCTAssertNil(workspace.selected); XCTAssertFalse(workspace.includeArchived)
        XCTAssertTrue(workspace.searchIndex.results(query: "milk").isEmpty)
        workspace.activate(protectedDataAvailable: true); try await wait { workspace.availability == .ready }
        XCTAssertEqual(workspace.searchIndex.results(query: "milk").count, 1); workspace.suspend()
    }
    func testFiveHundredEncryptedReceiptsMeasuredRebuildSearchAndRestart() async throws {
        let dir = directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let store = try ReceiptStore(directory: dir, keyProvider: SearchFixture.Key()), image = try SyntheticFixture.imageData()
        let original = SearchFixture.extraction()
        for _ in 0..<500 { _ = try await store.create(extraction: original, originalImage: image, mediaType: "image/png", correction: SearchFixture.correction(original)) }
        try await store.close()
        let reopened = try ReceiptStore(directory: dir, keyProvider: SearchFixture.Key())
        let clock = ContinuousClock(); let readStart = clock.now
        let records = try await reopened.receipts(); let readTime = readStart.duration(to: clock.now)
        let indexStart = clock.now; let index = ReceiptSearchIndex(records); let indexTime = indexStart.duration(to: clock.now)
        var times: [Duration] = []
        for _ in 0..<50 {
            let start = clock.now
            for query in ["milk", "creme", "苹果", "old 123456", "missingword", "corner milk"] {
                let results = index.results(query: query)
                XCTAssertEqual(results.count, query == "missingword" ? 0 : 500)
                XCTAssertEqual(Set(results.map(\.id)).count, results.count)
            }
            times.append(start.duration(to: clock.now))
        }
        XCTAssertEqual(records.count, 500); XCTAssertEqual(index.results(query: "").count, 500)
        XCTAssertLessThan(readTime, .seconds(10)); XCTAssertLessThan(indexTime, .seconds(2)); XCTAssertLessThan(times.max()!, .seconds(1))
        let report = "T07_FICTIONAL_500 read=\(readTime) index=\(indexTime) sixQueryBatchMedian=\(times.sorted()[25]) sixQueryBatchMax=\(times.max()!) iterations=50"
        print(report)
        let attachment = XCTAttachment(string: report); attachment.name = "T07-fictional-performance"; attachment.lifetime = .keepAlways; add(attachment)
        try await reopened.close()
    }
}
