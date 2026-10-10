import XCTest
import CryptoKit
@testable import Sliplet

/// Fictional records/images and fresh per-test stores only; never uses application storage/Keychain.
@MainActor final class ReceiptBackupTests: XCTestCase {
    private let password = "fictional-backup-password-2026"
    private var roots: [URL] = []
    override func tearDown() async throws { await MainActor.run { for root in roots { try? FileManager.default.removeItem(at: root) }; roots = [] } }
    private func directory() throws -> URL {
        let url = try ReceiptBackupArchive.temporaryDirectory(); roots.append(url); return url
    }
    private func store(key: UInt8 = 0x41, fault: (@Sendable (ReceiptStore.FaultPoint) throws -> Void)? = nil) throws -> ReceiptStore {
        try ReceiptStore(directory: directory(), keyProvider: ReceiptBackupTemporaryKey(bytes: Data(repeating: key, count: 32)), fault: fault)
    }
    private func record(_ store: ReceiptStore, finalized: Bool = false) async throws -> ReceiptRecord {
        let fixture = SplitFixture.record(amounts: [101, 200], adjustments: [(.tax, 3)])
        var draft = ReceiptReviewDraft(fields: fixture.current.fields)
        draft.subtotalNotPrinted = draft.subtotal.isEmpty
        draft.sourceOpened = true; draft.sourceChecked = finalized
        draft.guidanceChecks = ["fixture-check": "fixture-signature"]
        let created = try await store.create(extraction: fixture.original, originalImage: SyntheticFixture.imageData(), mediaType: "image/png",
            correction: draft.fields, review: finalized ? .sourceReviewed : .draft, reviewInput: JSONEncoder().encode(draft))
        if !finalized { return created }
        let plan = SplitFixture.plan(created, owners: [[SplitFixture.a], [SplitFixture.b, SplitFixture.c]])
        return try await store.saveSplit(id: created.id, expectedRevision: created.current.id, expectedPlan: nil, plan: plan, finalize: true)
    }
    private func backup(_ source: ReceiptStore) async throws -> URL {
        let url = try directory().appendingPathComponent("fixture.slipletbackup")
        try await source.exportBackup(to: url, password: password, permit: ReceiptOperationPermit())
        return url
    }
    private func prepare(_ url: URL, password override: String? = nil) async throws -> ReceiptPreparedBackup {
        try await ReceiptBackupPreparation.prepare(url: url, password: override ?? password, permit: ReceiptOperationPermit())
    }
    private func customArchive(records: [(ReceiptRecord, Data)], count: Int? = nil, schema: Int64 = 2) throws -> URL {
        let url = try directory().appendingPathComponent("custom.slipletbackup"), lease = ReceiptOperationPermit()
        let writer = try ReceiptBackupArchive.Writer(url: url, password: password)
        try writer.write(JSONEncoder().encode(ReceiptBackupManifest(version: 1, storeSchema: schema, createdAt: Date(),
            receiptCount: count ?? records.count, walletSettings: ReceiptWalletSettings())), maximum: 16_384, permit: lease)
        for (record, data) in records {
            try writer.write(JSONEncoder().encode(record), maximum: ReceiptStore.maximumRecordBytes, permit: lease)
            try writer.write(data, maximum: ReceiptStore.maximumAssetBytes, permit: lease)
        }
        try writer.finish(); return url
    }
    private func fails(_ url: URL, expected: ReceiptBackupError? = nil, password override: String? = nil) async {
        do { _ = try await prepare(url, password: override); XCTFail("Invalid archive accepted") }
        catch { if let expected { XCTAssertEqual(error as? ReceiptBackupError, expected) } }
    }
    func testCrossKeyRoundTripPreservesOriginalRevisionsGuidanceOrganizationAndExactSplit() async throws {
        let source = try store(), destination = try store(key: 0x72)
        let destinationDirectory = await destination.directory
        let saved = try await record(source, finalized: true)
        _ = try await source.organize(id: saved.id, expectedRevision: saved.current.id, action: .archive)
        let expected = try await source.organize(id: saved.id, expectedRevision: saved.current.id, action: .star)
        let settings = ReceiptWalletSettings(leftSwipe: .delete, rightSwipe: .none, paperAppearance: .alwaysWhite)
        try await source.saveWalletSettings(settings)
        let url = try await backup(source), prepared = try await prepare(url)
        let independent = FileManager.default.temporaryDirectory.appendingPathComponent("P205-independent-fictional.slipletbackup")
        try? FileManager.default.removeItem(at: independent)
        try FileManager.default.copyItem(at: url, to: independent)
        let evidence: [String: String] = ["testOnlyPassword": password, "receiptID": expected.id.uuidString,
            "imageSHA256": expected.asset.sha256.map { String(format: "%02x", $0) }.joined(),
            "reviewInputSHA256": Data(SHA256.hash(data: expected.current.reviewInput!)).map { String(format: "%02x", $0) }.joined(), "revisionCount": String(expected.revisions.count), "splitTotalCents": "304"]
        try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]).write(to: independent.deletingPathExtension().appendingPathExtension("json"))
        XCTAssertEqual(prepared.manifest.walletSettings, settings)
        let preview = try await destination.previewBackup(prepared, permit: ReceiptOperationPermit())
        XCTAssertEqual(preview, .init(total: 1, added: 1, skipped: 0, conflicts: 0))
        _ = try await destination.mergeBackup(prepared, expected: preview, permit: ReceiptOperationPermit())
        let loaded = try await destination.receipt(id: expected.id), original = try await destination.originalImage(receiptID: expected.id)
        XCTAssertEqual(loaded, expected); XCTAssertEqual(original, try SyntheticFixture.imageData())
        XCTAssertEqual(try ReceiptSplitEngine.compute(XCTUnwrap(loaded), plan: XCTUnwrap(loaded?.splitPlan)).total, 304)
        let localSettings = try await destination.walletSettings(); XCTAssertEqual(localSettings, ReceiptWalletSettings())
        let archive = try Data(contentsOf: url), database = try Data(contentsOf: destinationDirectory.appendingPathComponent("receipts.sqlite"))
        for text in ["Fictional", "participants", "rawOCR", "guidanceChecks", "sourceReviewed", password] {
            XCTAssertNil(archive.range(of: Data(text.utf8))); XCTAssertNil(database.range(of: Data(text.utf8)))
        }
        try await source.close(); try await destination.close()
        let reopened = try ReceiptStore(directory: destinationDirectory, keyProvider: ReceiptBackupTemporaryKey(bytes: Data(repeating: 0x72, count: 32)))
        let again = try await reopened.receipt(id: expected.id); XCTAssertEqual(again, expected); try await reopened.close()
    }
    func testMergeIsIdempotentAndDivergentExistingEditsWin() async throws {
        let source = try store(), target = try store(key: 0x71), old = try await record(source)
        let prepared = try await prepare(backup(source))
        let first = try await target.previewBackup(prepared, permit: ReceiptOperationPermit())
        _ = try await target.mergeBackup(prepared, expected: first, permit: ReceiptOperationPermit())
        let same = try await target.previewBackup(prepared, permit: ReceiptOperationPermit()); XCTAssertEqual(same.skipped, 1); XCTAssertEqual(same.conflicts, 0)
        var fields = old.current.fields; fields.merchant = "FICTIONAL LOCAL EDIT"
        let edited = try await target.revise(id: old.id, expectedRevision: old.current.id, fields: fields)
        let divergent = try await target.previewBackup(prepared, permit: ReceiptOperationPermit()); XCTAssertEqual(divergent.conflicts, 1)
        _ = try await target.mergeBackup(prepared, expected: divergent, permit: ReceiptOperationPermit())
        let kept = try await target.receipt(id: old.id); XCTAssertEqual(kept, edited)
        let all = try await target.receipts(); XCTAssertEqual(all.count, 1)
        try await source.close(); try await target.close()
    }
    func testWrongPasswordTamperTruncateAppendReorderAndChangedSaltFail() async throws {
        let source = try store(); _ = try await record(source)
        let originalURL = try await backup(source), bytes = try Data(contentsOf: originalURL)
        await fails(originalURL, expected: .authentication, password: "wrong-fictional-password")
        var tag = bytes; tag[tag.count - 1] ^= 1
        var salt = bytes; salt[ReceiptBackupArchive.magic.count] ^= 1
        let frameStart = ReceiptBackupArchive.headerBytes
        let size = bytes[frameStart..<(frameStart + 4)].reduce(0) { ($0 << 8) | Int($1) }
        let firstEnd = frameStart + 4 + size
        var reordered = bytes.prefix(frameStart); reordered.append(bytes[firstEnd...]); reordered.append(bytes[frameStart..<firstEnd])
        for variant in [tag, salt, Data(bytes.dropLast()), bytes + Data([0]), Data(reordered)] {
            let url = try directory().appendingPathComponent("damaged.slipletbackup"); try variant.write(to: url)
            await fails(url)
        }
        try await source.close()
    }
    func testMalformedLengthsUnknownVersionAndLimitsFailBeforeUnboundedRead() async throws {
        let source = try store(); let url = try await backup(source), original = try Data(contentsOf: url)
        var unknown = original; unknown[0] ^= 1
        let unknownURL = try directory().appendingPathComponent("unknown.slipletbackup"); try unknown.write(to: unknownURL)
        await fails(unknownURL, expected: .unsupported)
        var largeFrame = original; let p = ReceiptBackupArchive.headerBytes
        largeFrame.replaceSubrange(p..<(p + 4), with: [255, 255, 255, 255])
        let bad = try directory().appendingPathComponent("length.slipletbackup"); try largeFrame.write(to: bad)
        await fails(bad, expected: .limit)
        let tooMany = try customArchive(records: [], count: 1_001); await fails(tooMany, expected: .limit)
        let future = try customArchive(records: [], schema: 3); await fails(future, expected: .unsupported)
        let huge = try directory().appendingPathComponent("oversized.slipletbackup")
        FileManager.default.createFile(atPath: huge.path, contents: Data())
        let h = try FileHandle(forWritingTo: huge); try h.truncate(atOffset: UInt64(ReceiptBackupArchive.maximumBytes + 1)); try h.close()
        await fails(huge, expected: .limit)
        XCTAssertThrowsError(try ReceiptBackupArchive.validatePassword("short"))
        XCTAssertThrowsError(try ReceiptBackupArchive.validatePassword(String(repeating: "界", count: 400)))
        try await source.close()
    }
    func testAuthenticatedDuplicateReceiptAndAssetOwnersAreRejected() async throws {
        let source = try store(), a = try await record(source), b = try await record(source), bytes = try SyntheticFixture.imageData()
        await fails(try customArchive(records: [(a, bytes), (a, bytes)]), expected: .invalidArchive)
        let sharedAsset = ReceiptRecord(id: b.id, createdAt: b.createdAt, updatedAt: b.updatedAt, original: b.original, asset: a.asset, revisions: b.revisions)
        await fails(try customArchive(records: [(a, bytes), (sharedAsset, bytes)]), expected: .invalidArchive)
        try await source.close()
    }
    func testAuthenticatedInvalidImageDigestReviewInputAndFinalizedSplitAreRejected() async throws {
        let source = try store(), a = try await record(source), bytes = try SyntheticFixture.imageData()
        await fails(try customArchive(records: [(a, Data("not an image".utf8))]), expected: .invalidArchive)
        var revisions = a.revisions
        var input = ReceiptReviewDraft(fields: a.current.fields); input.merchant = "DIFFERENT FICTIONAL MERCHANT"
        revisions[revisions.count - 1].reviewInput = try JSONEncoder().encode(input)
        let inconsistent = ReceiptRecord(id: a.id, createdAt: a.createdAt, updatedAt: a.updatedAt, original: a.original, asset: a.asset, revisions: revisions)
        await fails(try customArchive(records: [(inconsistent, bytes)]), expected: .invalidArchive)
        var finalized = a; finalized.splitPlan = ReceiptSplitPlan(finalizedRevision: UUID())
        await fails(try customArchive(records: [(finalized, bytes)]), expected: .invalidArchive)
        let fake = Data("not an encoded image".utf8)
        let asset = ReceiptAsset(id: a.asset.id, mediaType: "image/png", byteCount: fake.count, sha256: Data(SHA256.hash(data: fake)))
        let badImage = ReceiptRecord(id: a.id, createdAt: a.createdAt, updatedAt: a.updatedAt, original: a.original, asset: asset, revisions: a.revisions)
        await fails(try customArchive(records: [(badImage, fake)]))
        try await source.close()
    }
    func testAssetCollisionWithExistingWalletRejectsEntireMerge() async throws {
        let source = try store(), target = try store(key: 0x61), a = try await record(source), b = try await record(target)
        let conflicting = ReceiptRecord(id: a.id, createdAt: a.createdAt, updatedAt: a.updatedAt, original: a.original, asset: b.asset, revisions: a.revisions)
        let prepared = try await prepare(customArchive(records: [(conflicting, SyntheticFixture.imageData())]))
        do { _ = try await target.previewBackup(prepared, permit: ReceiptOperationPermit()); XCTFail("Ownership collision accepted") }
        catch { XCTAssertEqual(error as? ReceiptBackupError, .assetCollision) }
        let kept = try await target.receipts(); XCTAssertEqual(kept, [b]); try await source.close(); try await target.close()
    }
    func testPreviewBecomesStaleAndCommitFailureRollsBackEveryNewRecordAndAsset() async throws {
        let source = try store(); _ = try await record(source); _ = try await record(source)
        let prepared = try await prepare(backup(source))
        let target = try store(key: 0x62, fault: { point in if point == .beforeCommit { throw ReceiptStoreError.injectedFailure } })
        let preview = try await target.previewBackup(prepared, permit: ReceiptOperationPermit())
        do { _ = try await target.mergeBackup(prepared, expected: preview, permit: ReceiptOperationPermit()); XCTFail("Failed commit survived") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .injectedFailure) }
        let all = try await target.receipts(); XCTAssertTrue(all.isEmpty)
        try await target.close()
        let targetDirectory = await target.directory
        let db = try ReceiptSQLiteDatabase(url: targetDirectory.appendingPathComponent("receipts.sqlite"), create: false)
        XCTAssertEqual(try db.integer("SELECT count(*) FROM assets"), 0); try db.close()
        let other = try store(key: 0x64)
        _ = try await other.mergeBackup(prepared, expected: preview, permit: ReceiptOperationPermit())
        do { _ = try await other.mergeBackup(prepared, expected: preview, permit: ReceiptOperationPermit()); XCTFail("Stale preview accepted") }
        catch { XCTAssertEqual(error as? ReceiptBackupError, .changedPreview) }
        try await source.close(); try await other.close()
    }
    func testCancellationDuringMergeRollsBackAndRevokedExportDoesNotWrite() async throws {
        let source = try store(); _ = try await record(source); _ = try await record(source)
        let prepared = try await prepare(backup(source)), lease = ReceiptOperationPermit()
        let target = try store(key: 0x63, fault: { point in if point == .afterReceiptWrite { lease.revoke() } })
        let preview = try await target.previewBackup(prepared, permit: ReceiptOperationPermit())
        do { _ = try await target.mergeBackup(prepared, expected: preview, permit: lease); XCTFail("Revoked restore committed") }
        catch { XCTAssertTrue(error is CancellationError) }
        let all = try await target.receipts(); XCTAssertTrue(all.isEmpty)
        let output = try directory().appendingPathComponent("cancelled.slipletbackup")
        do { try await source.exportBackup(to: output, password: password, permit: lease); XCTFail("Revoked export wrote") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        try await source.close(); try await target.close()
    }
    func testEmptyLegacyNilDraftAndRandomizedExports() async throws {
        let source = try store(), empty = try await prepare(backup(source)); XCTAssertEqual(empty.manifest.receiptCount, 0)
        let fixture = SplitFixture.record(amounts: [101], adjustments: [])
        let legacy = try await source.create(extraction: fixture.original, originalImage: SyntheticFixture.imageData(), mediaType: "image/png")
        XCTAssertNil(legacy.current.reviewInput)
        let a = try await backup(source), b = try await backup(source)
        XCTAssertNotEqual(try Data(contentsOf: a), try Data(contentsOf: b))
        let prepared = try await prepare(a), target = try store(key: 0x65)
        let preview = try await target.previewBackup(prepared, permit: ReceiptOperationPermit())
        _ = try await target.mergeBackup(prepared, expected: preview, permit: ReceiptOperationPermit())
        let loaded = try await target.receipt(id: legacy.id); XCTAssertEqual(loaded, legacy)
        XCTAssertFalse(ReceiptCompletion.isComplete(try XCTUnwrap(loaded)))
        try await source.close(); try await target.close()
    }
    func testWorkspaceConfirmedRestoreCancellationReleasesSavingAndRefreshesWallet() async throws {
        let source = try store(); _ = try await record(source)
        let archive = try await backup(source), url = try directory()
        let provider = ReceiptBackupTemporaryKey(bytes: Data(repeating: 0x68, count: 32))
        let workspace = ReceiptWorkspace(directory: url, keyProvider: provider)
        workspace.activate(protectedDataAvailable: true)
        for _ in 0..<100 { if workspace.availability == .ready { break }; try await Task.sleep(for: .milliseconds(20)) }
        workspace.prepareBackupRestore(url: archive, password: password)
        for _ in 0..<200 { if workspace.backupPreview != nil { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertNotNil(workspace.backupPreview)
        workspace.confirmBackupRestore(); XCTAssertTrue(workspace.saving)
        workspace.cancelBackup(); XCTAssertFalse(workspace.saving); XCTAssertFalse(workspace.backupBusy)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(workspace.active); XCTAssertEqual(workspace.availability, .ready)
        let observed = try ReceiptStore(directory: url, keyProvider: provider)
        let records = try await observed.receipts(); XCTAssertEqual(workspace.receipts, records)
        try await observed.close(); workspace.suspend(); try await source.close()
    }
    func testWorkspaceCancellationAndSuspensionClearBackupStateWithoutWalletLoss() async throws {
        let url = try directory(), provider = ReceiptBackupTemporaryKey(bytes: Data(repeating: 0x66, count: 32))
        let workspace = ReceiptWorkspace(directory: url, keyProvider: provider)
        workspace.activate(protectedDataAvailable: true)
        for _ in 0..<100 { if workspace.availability == .ready { break }; try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(workspace.availability, .ready)
        workspace.beginBackupExport(password: password); workspace.cancelBackup()
        XCTAssertNil(workspace.backupExportURL); XCTAssertFalse(workspace.backupBusy); XCTAssertTrue(workspace.active)
        workspace.beginBackupExport(password: password); workspace.suspend()
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertNil(workspace.backupExportURL); XCTAssertNil(workspace.backupPreview); XCTAssertNil(workspace.backupMessage)
        XCTAssertFalse(workspace.backupBusy); XCTAssertFalse(workspace.saving)
    }
}
