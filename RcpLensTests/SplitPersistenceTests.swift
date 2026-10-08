import XCTest
import Foundation
@testable import RcpLens

@MainActor final class SplitPersistenceTests: XCTestCase {
    private struct Key: ReceiptStoreKeyProvider {
        func loadKey() throws -> Data? { Data(repeating: 0x56, count: 32) }
        func createKey() throws -> Data { Data(repeating: 0x56, count: 32) }
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("T06-fictional-" + UUID().uuidString) }
    private func create(_ store: ReceiptStore, review: ReceiptRevision.Review = .sourceReviewed) async throws -> ReceiptRecord {
        let fixture = SplitFixture.record(amounts: [101, 200], adjustments: [(.tax, 3)])
        return try await store.create(extraction: fixture.original, originalImage: SyntheticFixture.imageData(), mediaType: "image/png", correction: fixture.current.fields, review: review)
    }
    func testEncryptedRestartLegacyDecodeDeletionAndEditInvalidation() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let store = try ReceiptStore(directory: url, keyProvider: Key())
        let record = try await create(store)
        XCTAssertNil(record.splitPlan)
        let legacy = try JSONDecoder().decode(ReceiptRecord.self, from: JSONEncoder().encode(record)); XCTAssertNil(legacy.splitPlan)
        let plan = SplitFixture.plan(record, owners: [[SplitFixture.a], [SplitFixture.b, SplitFixture.c]])
        let saved = try await store.saveSplit(id: record.id, expectedRevision: record.current.id, expectedPlan: nil, plan: plan, finalize: true)
        XCTAssertEqual(saved.revisions, record.revisions); XCTAssertEqual(saved.original, record.original); XCTAssertEqual(saved.updatedAt, record.updatedAt)
        XCTAssertEqual(saved.splitPlan?.finalizedRevision, record.current.id)
        try await store.close()
        let raw = try Data(contentsOf: url.appendingPathComponent("receipts.sqlite"))
        for privateText in ["Fictional Alex", "Fictional Blair", "participants", "assignments", "finalizedRevision"] { XCTAssertNil(raw.range(of: Data(privateText.utf8))) }
        let reopened = try ReceiptStore(directory: url, keyProvider: Key())
        let loaded = try await reopened.receipt(id: saved.id)
        XCTAssertEqual(loaded, saved)
        XCTAssertTrue(try ReceiptSplitEngine.summary(saved, plan: XCTUnwrap(saved.splitPlan)).contains("CAD 3.04"))
        var fields = saved.current.fields
        fields.items[0].amount = .init(minorUnits: 102, currency: .cad); fields.total = .init(minorUnits: 305, currency: .cad)
        let edited = try await reopened.revise(id: saved.id, expectedRevision: saved.current.id, fields: fields, review: .sourceReviewed)
        let rebased = try XCTUnwrap(edited.splitPlan)
        XCTAssertNil(rebased.finalizedRevision); XCTAssertEqual(rebased.assignments, plan.assignments); XCTAssertFalse(rebased.policies[0].accepted)
        XCTAssertThrowsError(try ReceiptSplitEngine.summary(edited, plan: rebased))
        var confirmed = rebased; confirmed.policies[0].accepted = true
        XCTAssertEqual(try ReceiptSplitEngine.compute(edited, plan: confirmed).total, 305)
        fields.items.removeFirst(); fields.total = .init(minorUnits: 203, currency: .cad)
        let removed = try await reopened.revise(id: saved.id, expectedRevision: edited.current.id, fields: fields, review: .sourceReviewed)
        XCTAssertEqual(removed.splitPlan?.assignments.count, 1)
        fields.items.append(.init(id: UUID(), description: "NEW FICTIONAL", sku: nil, quantity: nil, unitPrice: nil, amount: .init(minorUnits: 1, currency: .cad), taxMarker: nil, sourceLineIDs: [])); fields.total = .init(minorUnits: 204, currency: .cad)
        let added = try await reopened.revise(id: saved.id, expectedRevision: removed.current.id, fields: fields, review: .sourceReviewed)
        XCTAssertNil(added.splitPlan?.assignments[fields.items.last!.id])
        XCTAssertThrowsError(try ReceiptSplitEngine.compute(added, plan: XCTUnwrap(added.splitPlan)))
        try await reopened.delete(id: saved.id)
        let deleted = try await reopened.receipt(id: saved.id); XCTAssertNil(deleted)
        do { _ = try await reopened.originalImage(receiptID: saved.id); XCTFail("Deleted asset survived") } catch { XCTAssertEqual(error as? ReceiptStoreError, .notFound) }
        try await reopened.close()
    }
    func testStaleRevisionStalePlanAndRevokedPermitCannotWrite() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let store = try ReceiptStore(directory: url, keyProvider: Key())
        let record = try await create(store), plan = SplitFixture.plan(record)
        let saved = try await store.saveSplit(id: record.id, expectedRevision: record.current.id, expectedPlan: nil, plan: plan, finalize: false)
        do { _ = try await store.saveSplit(id: record.id, expectedRevision: record.current.id, expectedPlan: nil, plan: plan, finalize: true); XCTFail("Stale plan saved") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .editConflict) }
        do { _ = try await store.saveSplit(id: record.id, expectedRevision: UUID(), expectedPlan: saved.splitPlan?.id, plan: plan, finalize: true); XCTFail("Stale revision saved") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .editConflict) }
        let permit = ReceiptOperationPermit(); permit.revoke()
        do { _ = try await store.saveSplit(id: record.id, expectedRevision: record.current.id, expectedPlan: saved.splitPlan?.id, plan: plan, finalize: true, permit: permit); XCTFail("Revoked write saved") }
        catch { XCTAssertTrue(error is CancellationError) }
        let loaded = try await store.receipt(id: record.id); XCTAssertEqual(loaded, saved)
        try await store.close()
    }
    func testDraftAndIncompletePlansPersistButCannotFinalize() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let store = try ReceiptStore(directory: url, keyProvider: Key())
        let record = try await create(store, review: .draft)
        let saved = try await store.saveSplit(id: record.id, expectedRevision: record.current.id, expectedPlan: nil, plan: ReceiptSplitPlan(), finalize: false)
        XCTAssertNil(saved.splitPlan?.finalizedRevision)
        do { _ = try await store.saveSplit(id: record.id, expectedRevision: record.current.id, expectedPlan: saved.splitPlan?.id, plan: SplitFixture.plan(record), finalize: true); XCTFail("Draft finalized") }
        catch { XCTAssertEqual(error as? SplitError, .receiptNeedsReview) }
        let loaded = try await store.receipt(id: record.id); XCTAssertEqual(loaded, saved)
        try await store.close()
    }
    func testFailedCommitRollsBackSplitWithoutChangingEvidence() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let original = try ReceiptStore(directory: url, keyProvider: Key())
        let record = try await create(original); try await original.close()
        let faulty = try ReceiptStore(directory: url, keyProvider: Key(), fault: { point in if point == .beforeCommit { throw ReceiptStoreError.injectedFailure } })
        do { _ = try await faulty.saveSplit(id: record.id, expectedRevision: record.current.id, expectedPlan: nil, plan: SplitFixture.plan(record), finalize: true); XCTFail("Injected failure committed") } catch { XCTAssertEqual(error as? ReceiptStoreError, .injectedFailure) }
        let unchanged = try await faulty.receipt(id: record.id); XCTAssertEqual(unchanged, record)
        try await faulty.close()
    }
    func testRevocationAtCommitRollsBackSplit() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let original = try ReceiptStore(directory: url, keyProvider: Key())
        let record = try await create(original); try await original.close()
        let permit = ReceiptOperationPermit()
        let store = try ReceiptStore(directory: url, keyProvider: Key(), fault: { point in if point == .beforeCommit { permit.revoke() } })
        do { _ = try await store.saveSplit(id: record.id, expectedRevision: record.current.id, expectedPlan: nil,
            plan: SplitFixture.plan(record), finalize: true, permit: permit); XCTFail("Revocation committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        let restored = try await store.receipt(id: record.id); XCTAssertEqual(restored, record)
        try await store.close()
    }
    func testWorkspaceBackgroundClearsSplitPresentationAndRevokesQueuedWrite() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let store = try ReceiptStore(directory: url, keyProvider: Key())
        let record = try await create(store); try await store.close()
        let workspace = ReceiptWorkspace(directory: url, keyProvider: Key())
        workspace.activate(protectedDataAvailable: true)
        for _ in 0..<200 { if workspace.availability == .ready { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(workspace.availability, .ready)
        workspace.open(record)
        for _ in 0..<200 { if workspace.image != nil { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertNotNil(workspace.image)
        workspace.splitVisible = true; workspace.saveSplit(SplitFixture.plan(record), finalize: true)
        workspace.suspend()
        XCTAssertNil(workspace.selected); XCTAssertNil(workspace.image); XCTAssertFalse(workspace.splitVisible); XCTAssertFalse(workspace.saving)
        workspace.activate(protectedDataAvailable: true)
        for _ in 0..<200 { if workspace.availability == .ready { break }; try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(workspace.availability, .ready); XCTAssertNil(workspace.receipts.first?.splitPlan)
        workspace.suspend()
    }
    func testInvalidEncryptedPlanStructureFailsClosed() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let store = try ReceiptStore(directory: url, keyProvider: Key())
        let record = try await create(store); try await store.close()
        var invalid = record; var plan = SplitFixture.plan(record); plan.participants.append(plan.participants[0]); invalid.splitPlan = plan
        let cipher = try ReceiptStoreCipher(key: Data(repeating: 0x56, count: 32))
        let db = try ReceiptSQLiteDatabase(url: url.appendingPathComponent("receipts.sqlite"), create: false)
        let payload = try cipher.seal(JSONEncoder().encode(invalid), context: ReceiptStoreCipher.receiptContext(record.id))
        try db.run("UPDATE receipts SET payload = ? WHERE id = ?", [.blob(payload), .text(record.id.uuidString)]); try db.close()
        let reopened = try ReceiptStore(directory: url, keyProvider: Key())
        do { _ = try await reopened.receipt(id: record.id); XCTFail("Invalid plan loaded") } catch { XCTAssertEqual(error as? SplitError, .invalidPlan) }
        try await reopened.close()
    }
}
