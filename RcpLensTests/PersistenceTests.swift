import XCTest
import Foundation
import CryptoKit
import Security
@testable import RcpLens

/// Fictional inputs only. Never point this suite at the application store or a private corpus.
@MainActor
final class PersistenceTests: XCTestCase {
    private struct FixedKey: ReceiptStoreKeyProvider {
        let bytes: Data?
        var creationAllowed = true
        func loadKey() throws -> Data? { bytes }
        func createKey() throws -> Data {
            guard creationAllowed else { throw ReceiptStoreError.injectedFailure }
            return Data(repeating: 0x5A, count: 32)
        }
    }
    private let key = Data(repeating: 0x5A, count: 32)
    private let time = Date(timeIntervalSince1970: 1_700_000_000)

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RcpLens-T04-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func clean(_ url: URL) { try? FileManager.default.removeItem(at: url) }
    private func image() throws -> Data { try SyntheticFixture.imageData() }
    private func extraction() -> ReceiptExtraction {
        let lineID = UUID()
        return ReceiptExtraction(capturedAt: time, recognizer: "SyntheticVision", recognizerVersion: "1",
            parser: "SyntheticParser", parserVersion: "1",
            rawOCR: [ReceiptOCRLine(id: lineID, text: "FICTIONAL ORIGINAL ITEM ??.??", engineConfidence: 0.5)],
            rawParserOutput: Data("{\"amount\":null,\"uncertain\":true}".utf8),
            fields: ReceiptFields(merchant: "FICTIONAL ORIGINAL STORE", purchaseDate: nil, currency: .cad,
                items: [ReceiptLine(id: UUID(), description: "FICTIONAL ORIGINAL ITEM", sku: nil,
                    quantity: try! ReceiptDecimal(coefficient: 1250, scale: 3), unitPrice: nil, amount: nil,
                    taxMarker: nil, sourceLineIDs: [lineID])], adjustments: [], subtotal: nil, total: nil),
            issues: [ReceiptExtractionIssue(code: "unknown-amount", sourceLineIDs: [lineID], detail: nil)])
    }
    private func assertError<T>(_ expected: ReceiptStoreError, _ action: () throws -> T,
                                file: StaticString = #filePath, line: UInt = #line) {
        do { _ = try action(); XCTFail("Expected safe store failure", file: file, line: line) }
        catch { XCTAssertEqual(error as? ReceiptStoreError, expected, file: file, line: line) }
    }
    private func rawDatabase(_ url: URL) throws -> ReceiptSQLiteDatabase {
        try ReceiptSQLiteDatabase(url: url.appendingPathComponent("receipts.sqlite"), create: false)
    }

    func testWalletOrganizationAndSettingsSurviveEditsAndReopen() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let original = extraction(), bytes = try image()
        let record = try await store.create(extraction: original, originalImage: bytes, mediaType: "image/png", now: time)
        // A historical document without organization remains readable with the same evidence.
        var document = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        document.removeValue(forKey: "organization")
        let legacy = try JSONDecoder().decode(ReceiptRecord.self, from: JSONSerialization.data(withJSONObject: document))
        XCTAssertFalse(legacy.isStarred); XCTAssertFalse(legacy.isArchived); XCTAssertEqual(legacy.original, original)
        let starred = try await store.organize(id: record.id, expectedRevision: record.current.id, action: .star)
        let archived = try await store.organize(id: record.id, expectedRevision: record.current.id, action: .archive)
        XCTAssertTrue(starred.isStarred); XCTAssertTrue(archived.isStarred); XCTAssertTrue(archived.isArchived)
        XCTAssertEqual(archived.revisions, record.revisions); XCTAssertEqual(archived.updatedAt, record.updatedAt)
        let edited = try await store.revise(id: record.id, expectedRevision: record.current.id, fields: record.current.fields, now: time.addingTimeInterval(1))
        XCTAssertTrue(edited.isArchived); XCTAssertTrue(edited.isStarred)
        let settings = ReceiptWalletSettings(leftSwipe: .delete, rightSwipe: .none, paperAppearance: .alwaysWhite)
        try await store.saveWalletSettings(settings)
        try await store.close()
        let reopened = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let loaded = try await reopened.receipt(id: record.id)
        let restored = try XCTUnwrap(loaded)
        let preferences = try await reopened.walletSettings()
        let asset = try await reopened.originalImage(receiptID: record.id)
        XCTAssertEqual(restored, edited); XCTAssertEqual(preferences, settings); XCTAssertEqual(asset, bytes)
        let unarchived = try await reopened.organize(id: record.id, expectedRevision: edited.current.id, action: .archive)
        XCTAssertFalse(unarchived.isArchived); XCTAssertTrue(unarchived.isStarred)
        let dbBytes = try Data(contentsOf: url.appendingPathComponent("receipts.sqlite"))
        XCTAssertNil(dbBytes.range(of: Data("leftSwipe".utf8)))
        XCTAssertNil(dbBytes.range(of: Data("alwaysWhite".utf8)))
        XCTAssertNil(dbBytes.range(of: Data("starred".utf8)))
        try await reopened.close()
    }

    func testExistingWalletPreferencesKeepSwipeActionsAndDefaultPaperAppearance() throws {
        let legacy = Data(#"{"leftSwipe":"delete","rightSwipe":"none"}"#.utf8)
        let decoded = try JSONDecoder().decode(ReceiptWalletSettings.self, from: legacy)
        XCTAssertEqual(decoded, ReceiptWalletSettings(leftSwipe: .delete, rightSwipe: .none))
        for appearance in ReceiptPaperAppearance.allCases {
            let preferences = ReceiptWalletSettings(leftSwipe: .none, rightSwipe: .archive, paperAppearance: appearance)
            XCTAssertEqual(try JSONDecoder().decode(ReceiptWalletSettings.self, from: JSONEncoder().encode(preferences)), preferences)
        }
        // Unknown values indicate corruption or a future format, rather than silently replacing a choice.
        XCTAssertThrowsError(try JSONDecoder().decode(ReceiptWalletSettings.self,
            from: Data(#"{"leftSwipe":"archive","rightSwipe":"star","paperAppearance":"invalid"}"#.utf8)))
    }

    func testWalletActionsRejectStaleEditsAndRevokedWrites() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let record = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        let edited = try await store.revise(id: record.id, expectedRevision: record.current.id, fields: record.current.fields, now: time.addingTimeInterval(1))
        do {
            _ = try await store.organize(id: record.id, expectedRevision: record.current.id, action: .archive)
            XCTFail("Stale receipt must not be organized")
        } catch { XCTAssertEqual(error as? ReceiptStoreError, .editConflict) }
        let permit = ReceiptOperationPermit(); permit.revoke()
        do { _ = try await store.organize(id: record.id, expectedRevision: edited.current.id, action: .star, permit: permit); XCTFail("Revoked write") }
        catch { XCTAssertTrue(error is CancellationError) }
        do { try await store.saveWalletSettings(.init(leftSwipe: .delete, rightSwipe: .delete), permit: permit); XCTFail("Revoked settings") }
        catch { XCTAssertTrue(error is CancellationError) }
        let current = try await store.receipt(id: record.id), settings = try await store.walletSettings()
        XCTAssertEqual(current, edited); XCTAssertEqual(settings, ReceiptWalletSettings())
        try await store.close()
    }

    func testWalletActionsRollbackAtCommitBoundary() async throws {
        let url = try directory(); defer { clean(url) }
        let initial = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let record = try await initial.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        try await initial.close()
        let failing = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key), fault: { if $0 == .beforeCommit { throw ReceiptStoreError.injectedFailure } })
        do { _ = try await failing.organize(id: record.id, expectedRevision: record.current.id, action: .star); XCTFail("Injected failure") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .injectedFailure) }
        do { try await failing.saveWalletSettings(.init(leftSwipe: .delete, rightSwipe: .none)); XCTFail("Injected failure") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .injectedFailure) }
        try await failing.close()
        let reopened = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let restored = try await reopened.receipt(id: record.id), settings = try await reopened.walletSettings()
        XCTAssertEqual(restored, record); XCTAssertEqual(settings, ReceiptWalletSettings())
        try await reopened.close()
    }

    func testCreateEditCloseReopenPreservesOriginalAndUnknowns() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let original = extraction(), bytes = try image()
        let record = try await store.create(extraction: original, originalImage: bytes, mediaType: "image/png", now: time)
        XCTAssertNil(record.current.fields.total)
        XCTAssertNil(record.current.fields.items[0].amount)
        XCTAssertEqual(record.current.review, .draft)
        var corrected = record.current.fields
        corrected.merchant = "FICTIONAL CORRECTED STORE"
        corrected.items[0].amount = ReceiptMoney(minorUnits: 1234, currency: .cad)
        corrected.total = ReceiptMoney(minorUnits: 1234, currency: .cad)
        let edited = try await store.revise(id: record.id, expectedRevision: record.current.id, fields: corrected,
                                            now: time.addingTimeInterval(1))
        XCTAssertEqual(edited.original, original)
        XCTAssertEqual(edited.revisions.count, 2)
        XCTAssertEqual(edited.revisions.first, record.current)
        XCTAssertEqual(edited.current.review, .draft) // Matching total never auto-verifies.
        try await store.close()
        let reopened = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let fetched = try await reopened.receipt(id: record.id)
        let retrievedImage = try await reopened.originalImage(receiptID: record.id)
        let listed = try await reopened.receipts()
        XCTAssertEqual(fetched, edited)
        XCTAssertEqual(retrievedImage, bytes)
        XCTAssertEqual(listed, [edited])
        try await reopened.close()
    }

    func testStaleEditorCannotOverwriteAnotherRevision() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let record = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        let secondConnection = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let next = try await store.revise(id: record.id, expectedRevision: record.current.id,
                                          fields: record.current.fields, now: time.addingTimeInterval(1))
        do {
            _ = try await secondConnection.revise(id: record.id, expectedRevision: record.current.id,
                fields: record.current.fields, now: time.addingTimeInterval(2))
            XCTFail("A stale editor must fail")
        } catch { XCTAssertEqual(error as? ReceiptStoreError, .editConflict) }
        let fetched = try await secondConnection.receipt(id: record.id)
        XCTAssertEqual(fetched, next)
        try await store.close(); try await secondConnection.close()
    }

    func testCreateFailureRollsBackReceiptAndAssetAtBothBoundaries() async throws {
        for boundary in [ReceiptStore.FaultPoint.afterReceiptWrite, .beforeCommit] {
            let url = try directory(); defer { clean(url) }
            let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key), fault: {
                if $0 == boundary { throw ReceiptStoreError.injectedFailure }
            })
            do {
                _ = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
                XCTFail("Injected atomic failure must throw")
            } catch { XCTAssertEqual(error as? ReceiptStoreError, .injectedFailure) }
            try await store.close()
            let reopened = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
            let receipts = try await reopened.receipts()
            XCTAssertTrue(receipts.isEmpty)
            let db = try rawDatabase(url)
            XCTAssertEqual(try db.integer("SELECT count(*) FROM assets"), 0)
            XCTAssertTrue(try db.run("PRAGMA foreign_key_check").isEmpty)
            try db.close(); try await reopened.close()
        }
    }

    func testRevisionFailurePreservesPreviouslyCommittedSnapshot() async throws {
        let url = try directory(); defer { clean(url) }
        let initial = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let record = try await initial.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        try await initial.close()
        let failing = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key), fault: {
            if $0 == .beforeCommit { throw ReceiptStoreError.injectedFailure }
        })
        var fields = record.current.fields; fields.merchant = "UNCOMMITTED FICTIONAL EDIT"
        do {
            _ = try await failing.revise(id: record.id, expectedRevision: record.current.id, fields: fields,
                                         now: time.addingTimeInterval(1))
            XCTFail("Injected revision failure must throw")
        } catch { XCTAssertEqual(error as? ReceiptStoreError, .injectedFailure) }
        try await failing.close()
        let reopened = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let fetched = try await reopened.receipt(id: record.id)
        XCTAssertEqual(fetched, record)
        try await reopened.close()
    }

    func testDeleteCascadesAssetAndRemovesCiphertextFromLiveFile() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let record = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        let db = try rawDatabase(url)
        guard case .blob(let payload) = try db.run("SELECT payload FROM receipts")[0][0],
              case .blob(let asset) = try db.run("SELECT payload FROM assets")[0][0] else { return XCTFail("Expected encrypted blobs") }
        try db.close()
        try await store.delete(id: record.id)
        try await store.delete(id: record.id) // Retry is idempotent.
        try await store.close()
        let reopened = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let fetched = try await reopened.receipt(id: record.id), listed = try await reopened.receipts()
        XCTAssertNil(fetched); XCTAssertTrue(listed.isEmpty)
        do { _ = try await reopened.originalImage(receiptID: record.id); XCTFail("Deleted asset must be unavailable") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .notFound) }
        let inspection = try rawDatabase(url)
        XCTAssertEqual(try inspection.integer("SELECT count(*) FROM assets"), 0)
        try inspection.close(); try await reopened.close()
        let databaseBytes = try Data(contentsOf: url.appendingPathComponent("receipts.sqlite"))
        XCTAssertNil(databaseBytes.range(of: payload)); XCTAssertNil(databaseBytes.range(of: asset))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathComponent("receipts.sqlite-journal").path))
    }

    func testFailedDeletionRetainsReceiptAndAssetOnReopen() async throws {
        let url = try directory(); defer { clean(url) }
        let initial = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let bytes = try image()
        let record = try await initial.create(extraction: extraction(), originalImage: bytes, mediaType: "image/png", now: time)
        try await initial.close()
        let failing = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key), fault: {
            if $0 == .afterDelete { throw ReceiptStoreError.injectedFailure }
        })
        do { try await failing.delete(id: record.id); XCTFail("Deletion must roll back") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .injectedFailure) }
        try await failing.close()
        let reopened = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let fetched = try await reopened.receipt(id: record.id), asset = try await reopened.originalImage(receiptID: record.id)
        XCTAssertEqual(fetched, record); XCTAssertEqual(asset, bytes)
        try await reopened.close()
    }

    func testMissingWrongAndMalformedKeyNeverReplaceExistingStore() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let record = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        try await store.close()
        let file = url.appendingPathComponent("receipts.sqlite"), before = try Data(contentsOf: file)
        assertError(.missingKey) { try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: nil, creationAllowed: false)) }
        XCTAssertEqual(try Data(contentsOf: file), before)
        assertError(.authenticationFailed) { try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: Data(repeating: 9, count: 32))) }
        XCTAssertEqual(try Data(contentsOf: file), before)
        assertError(.invalidKey) { try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: Data([1]))) }
        XCTAssertEqual(try Data(contentsOf: file), before)
        let reopened = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let fetched = try await reopened.receipt(id: record.id)
        XCTAssertEqual(fetched, record)
        try await reopened.close()
    }

    func testUnavailableKeychainErrorDoesNotBecomeMissingKeyOrReset() async throws {
        struct LockedKey: ReceiptStoreKeyProvider {
            func loadKey() throws -> Data? { throw ReceiptStoreError.keychain(errSecInteractionNotAllowed) }
            func createKey() throws -> Data { throw ReceiptStoreError.injectedFailure }
        }
        let url = try directory(); defer { clean(url) }
        assertError(.keychain(errSecInteractionNotAllowed)) { try ReceiptStore(directory: url, keyProvider: LockedKey()) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.appendingPathComponent("receipts.sqlite").path))
    }

    private func versionOneFixture(_ url: URL, corruptAsset: Bool = false) async throws -> ReceiptRecord {
        let temporary = try directory(); defer { clean(temporary) }
        let store = try ReceiptStore(directory: temporary, keyProvider: FixedKey(bytes: key))
        let bytes = try image()
        let initial = try await store.create(extraction: extraction(), originalImage: bytes, mediaType: "image/png", now: time)
        let record = try await store.revise(id: initial.id, expectedRevision: initial.current.id,
                                            fields: initial.current.fields, now: time.addingTimeInterval(10))
        try await store.close()
        let cipher = try ReceiptStoreCipher(key: key)
        let db = try ReceiptSQLiteDatabase(url: url.appendingPathComponent("receipts.sqlite"), create: true)
        try db.run("PRAGMA foreign_keys = ON")
        try db.transaction {
            try ReceiptStore.createVersionOne(db, cipher)
            try db.run("INSERT INTO receipts VALUES (?, ?)", [.text(record.id.uuidString),
                .blob(cipher.seal(JSONEncoder().encode(record), context: ReceiptStoreCipher.receiptContext(record.id)))])
            try db.run("INSERT INTO assets VALUES (?, ?, ?)", [.text(record.asset.id.uuidString), .text(record.id.uuidString),
                .blob(corruptAsset ? Data([1, 2, 3]) : cipher.seal(bytes, context: ReceiptStoreCipher.assetContext(record.asset.id, owner: record.id)))])
        }
        try db.close()
        return record
    }

    func testVersionOneMigrationPreservesOriginalRevisionsAndImage() async throws {
        let url = try directory(); defer { clean(url) }
        let expected = try await versionOneFixture(url)
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let fetched = try await store.receipt(id: expected.id), bytes = try await store.originalImage(receiptID: expected.id)
        XCTAssertEqual(fetched, expected); XCTAssertEqual(bytes, try image())
        let db = try rawDatabase(url)
        XCTAssertEqual(try db.integer("PRAGMA user_version"), 2)
        XCTAssertEqual(try db.integer("SELECT updated_at FROM receipts"), 1_700_000_010_000)
        try db.close(); try await store.close()
        let reopened = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let again = try await reopened.receipt(id: expected.id)
        XCTAssertEqual(again, expected)
        try await reopened.close()
    }

    func testFailedMigrationRollsBackAndKeepsVersionOne() async throws {
        let url = try directory(); defer { clean(url) }
        _ = try await versionOneFixture(url, corruptAsset: true)
        let before = try Data(contentsOf: url.appendingPathComponent("receipts.sqlite"))
        assertError(.authenticationFailed) { try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key)) }
        let db = try rawDatabase(url)
        XCTAssertEqual(try db.integer("PRAGMA user_version"), 1)
        XCTAssertEqual(try db.run("PRAGMA table_info(receipts)").count, 2)
        try db.close()
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("receipts.sqlite")), before)
    }

    func testUnknownFutureVersionFailsWithoutModifyingBytes() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        _ = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        try await store.close()
        let db = try rawDatabase(url); try db.run("PRAGMA user_version = 999"); try db.close()
        let before = try Data(contentsOf: url.appendingPathComponent("receipts.sqlite"))
        assertError(.unsupportedSchema(999)) { try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key)) }
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("receipts.sqlite")), before)
    }

    func testEmptyInterruptedBootstrapResumesOnlyWithExistingKey() async throws {
        let url = try directory(); defer { clean(url) }
        let db = try ReceiptSQLiteDatabase(url: url.appendingPathComponent("receipts.sqlite"), create: true)
        try db.close()
        assertError(.missingKey) { try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: nil, creationAllowed: false)) }
        let resumed = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let receipts = try await resumed.receipts(); XCTAssertTrue(receipts.isEmpty)
        try await resumed.close()
        let inspected = try rawDatabase(url); XCTAssertEqual(try inspected.integer("PRAGMA user_version"), 2); try inspected.close()
    }

    func testUnversionedNonemptyDatabaseIsNeverReset() throws {
        let url = try directory(); defer { clean(url) }
        let db = try ReceiptSQLiteDatabase(url: url.appendingPathComponent("receipts.sqlite"), create: true)
        try db.run("CREATE TABLE unexpected (id INTEGER)"); try db.run("INSERT INTO unexpected VALUES (42)"); try db.close()
        let before = try Data(contentsOf: url.appendingPathComponent("receipts.sqlite"))
        assertError(.corruptStore) { try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key)) }
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("receipts.sqlite")), before)
    }

    func testCiphertextBindsPurposeReceiptAndAssetOwnerAndDetectsTampering() throws {
        let cipher = try ReceiptStoreCipher(key: key), id = UUID(), owner = UUID()
        let plaintext = Data("FICTIONAL PAYLOAD".utf8)
        let first = try cipher.seal(plaintext, context: ReceiptStoreCipher.receiptContext(id))
        let second = try cipher.seal(plaintext, context: ReceiptStoreCipher.receiptContext(id))
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try cipher.open(first, context: ReceiptStoreCipher.receiptContext(id)), plaintext)
        assertError(.authenticationFailed) { try cipher.open(first, context: ReceiptStoreCipher.receiptContext(UUID())) }
        assertError(.authenticationFailed) { try cipher.open(first, context: ReceiptStoreCipher.assetContext(id, owner: owner)) }
        let asset = try cipher.seal(plaintext, context: ReceiptStoreCipher.assetContext(id, owner: owner))
        assertError(.authenticationFailed) { try cipher.open(asset, context: ReceiptStoreCipher.assetContext(id, owner: UUID())) }
        var tampered = first; tampered[tampered.count - 1] ^= 1
        assertError(.authenticationFailed) { try cipher.open(tampered, context: ReceiptStoreCipher.receiptContext(id)) }
    }

    func testSwappedDatabasePayloadsAreRejected() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let first = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        let second = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        let db = try rawDatabase(url)
        guard case .blob(let payload) = try db.run("SELECT payload FROM receipts WHERE id = ?", [.text(second.id.uuidString)])[0][0] else {
            return XCTFail("Expected ciphertext")
        }
        try db.run("UPDATE receipts SET payload = ? WHERE id = ?", [.blob(payload), .text(first.id.uuidString)])
        try db.close()
        do { _ = try await store.receipt(id: first.id); XCTFail("Substitution must fail") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .authenticationFailed) }
        try await store.close()
    }

    func testSQLiteContainsOnlyCiphertextForReceiptContentAndImage() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let bytes = try image()
        let record = try await store.create(extraction: extraction(), originalImage: bytes, mediaType: "image/png", now: time)
        let db = try rawDatabase(url)
        guard case .blob(let payload) = try db.run("SELECT payload FROM receipts")[0][0],
              case .blob(let asset) = try db.run("SELECT payload FROM assets")[0][0] else { return XCTFail("Expected blobs") }
        let cipher = try ReceiptStoreCipher(key: key)
        let decoded = try JSONDecoder().decode(ReceiptRecord.self,
            from: cipher.open(payload, context: ReceiptStoreCipher.receiptContext(record.id)))
        XCTAssertEqual(decoded, record)
        XCTAssertEqual(try cipher.open(asset, context: ReceiptStoreCipher.assetContext(record.asset.id, owner: record.id)), bytes)
        XCTAssertEqual(try db.integer("PRAGMA user_version"), 2)
        try db.close(); try await store.close()
        let disk = try Data(contentsOf: url.appendingPathComponent("receipts.sqlite"))
        XCTAssertTrue(disk.starts(with: Data("SQLite format 3".utf8))) // No whole-database-encryption claim.
        XCTAssertNil(disk.range(of: Data("FICTIONAL ORIGINAL".utf8)))
        XCTAssertNil(disk.range(of: extraction().rawParserOutput))
        XCTAssertNil(disk.range(of: bytes))
        XCTAssertNil(disk.range(of: key))
        XCTAssertNil(disk.range(of: Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])))
    }

    func testDatabaseDirectoryAndLiveJournalProtectionAndBackupExclusion() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key), fault: { point in
            if point == .beforeCommit {
                let journal = url.appendingPathComponent("receipts.sqlite-journal")
                let attributes = try FileManager.default.attributesOfItem(atPath: journal.path)
                #if !targetEnvironment(simulator)
                XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
                #endif
                XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
                let contents = try Data(contentsOf: journal)
                XCTAssertNil(contents.range(of: Data("FICTIONAL ORIGINAL".utf8)))
                XCTAssertNil(contents.range(of: Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])))
            }
        })
        _ = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        for path in [url, url.appendingPathComponent("receipts.sqlite")] {
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            #if !targetEnvironment(simulator)
            XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
            #endif
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, path == url ? 0o700 : 0o600)
            XCTAssertEqual(try path.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        }
        try await store.close()
    }

    func testHardwareFileProtectionRequiresDeviceVerification() async throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("iOS Simulator returns no NSFileProtection attribute; device lock protection is unverified.")
        #else
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.appendingPathComponent("receipts.sqlite").path)
        XCTAssertEqual(attributes[.protectionKey] as? FileProtectionType, .complete)
        try await store.close()
        #endif
    }

    func testGeometryAndRevisionReferencesPreserveProvenance() async throws {
        let url = try directory(); defer { clean(url) }
        let base = extraction(), box = try ReceiptOCRBox(x: 0.1, y: 0.2, width: 0.7, height: 0.05)
        let original = ReceiptExtraction(capturedAt: base.capturedAt, recognizer: base.recognizer,
            recognizerVersion: base.recognizerVersion, parser: base.parser, parserVersion: base.parserVersion,
            rawOCR: [ReceiptOCRLine(id: base.rawOCR[0].id, text: base.rawOCR[0].text,
                                   engineConfidence: base.rawOCR[0].engineConfidence, boundingBox: box)],
            rawParserOutput: base.rawParserOutput, fields: base.fields, issues: base.issues)
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let record = try await store.create(extraction: original, originalImage: image(), mediaType: "image/png", now: time)
        var invalid = record.current.fields; invalid.items[0].sourceLineIDs = [UUID()]
        do {
            _ = try await store.revise(id: record.id, expectedRevision: record.current.id, fields: invalid,
                                       now: time.addingTimeInterval(1))
            XCTFail("Revision must not invent source identities")
        } catch { XCTAssertEqual(error as? ReceiptValidationError, .invalidEvidence) }
        var manual = record.current.fields
        manual.items.append(ReceiptLine(id: UUID(), description: "FICTIONAL MANUAL ITEM", sku: nil,
            quantity: nil, unitPrice: nil, amount: nil, taxMarker: nil, sourceLineIDs: []))
        let revised = try await store.revise(id: record.id, expectedRevision: record.current.id,
                                             fields: manual, now: time.addingTimeInterval(1))
        XCTAssertEqual(revised.original.rawOCR[0].boundingBox, box)
        try await store.close()
        let reopened = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let fetched = try await reopened.receipt(id: record.id); XCTAssertEqual(fetched, revised)
        try await reopened.close()
        XCTAssertThrowsError(try ReceiptOCRBox(x: .nan, y: 0, width: 1, height: 1))
        XCTAssertThrowsError(try ReceiptOCRBox(x: 0.5, y: 0, width: 0.6, height: 1))
    }

    func testMissingAssetFailsListAndDetailWithoutSilentlySkipping() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        let record = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        let db = try rawDatabase(url); try db.run("DELETE FROM assets"); try db.close()
        do { _ = try await store.receipts(); XCTFail("Missing owned evidence must surface") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .corruptStore) }
        do { _ = try await store.receipt(id: record.id); XCTFail("Missing owned evidence must surface") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .corruptStore) }
        try await store.close()
    }

    func testRealKeychainPersistenceAttributesAndDeletionFailure() async throws {
        let url = try directory(); defer { clean(url) }
        let service = "com.mobyyyc.RcpLens.T04-tests", account = UUID().uuidString
        let provider = KeychainReceiptStoreKey(service: service, account: account)
        let identity: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: account]
        defer { SecItemDelete(identity as CFDictionary) }
        XCTAssertNil(try provider.loadKey())
        let store = try ReceiptStore(directory: url, keyProvider: provider)
        let generated = try XCTUnwrap(provider.loadKey())
        XCTAssertEqual(generated.count, 32)
        XCTAssertEqual(try provider.createKey(), generated) // Duplicate must return, never replace.
        var attributesQuery = identity
        attributesQuery[kSecReturnAttributes as String] = true
        var returned: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(attributesQuery as CFDictionary, &returned), errSecSuccess)
        let attributes = try XCTUnwrap(returned as? [String: Any])
        XCTAssertEqual(attributes[kSecAttrAccessible as String] as? String, kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        XCTAssertEqual(attributes[kSecAttrSynchronizable as String] as? Bool ?? false, false)
        let record = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        try await store.close()
        let reopened = try ReceiptStore(directory: url, keyProvider: provider)
        let fetched = try await reopened.receipt(id: record.id)
        XCTAssertEqual(fetched, record); try await reopened.close()
        XCTAssertEqual(SecItemDelete(identity as CFDictionary), errSecSuccess)
        let before = try Data(contentsOf: url.appendingPathComponent("receipts.sqlite"))
        assertError(.missingKey) { try ReceiptStore(directory: url, keyProvider: provider) }
        XCTAssertEqual(try Data(contentsOf: url.appendingPathComponent("receipts.sqlite")), before)
        XCTAssertNil(try provider.loadKey())
    }

    func testExplicitLocalPurgeAndClosedStore() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        _ = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        _ = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        try await store.purgeAllReceipts()
        let receipts = try await store.receipts(); XCTAssertTrue(receipts.isEmpty)
        let db = try rawDatabase(url); XCTAssertEqual(try db.integer("SELECT count(*) FROM assets"), 0); try db.close()
        try await store.close()
        do { _ = try await store.receipts(); XCTFail("Closed store must fail") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .closed) }
    }

    func testValidationRejectsBadAssetsCurrencyAndClockRollback() async throws {
        let url = try directory(); defer { clean(url) }
        let store = try ReceiptStore(directory: url, keyProvider: FixedKey(bytes: key))
        do { _ = try await store.create(extraction: extraction(), originalImage: Data(), mediaType: "image/png"); XCTFail("Empty evidence") }
        catch { XCTAssertEqual(error as? ReceiptStoreError, .invalidAsset) }
        let record = try await store.create(extraction: extraction(), originalImage: image(), mediaType: "image/png", now: time)
        do {
            _ = try await store.revise(id: record.id, expectedRevision: record.current.id, fields: record.current.fields,
                                       now: time.addingTimeInterval(-1))
            XCTFail("A regressing timestamp must be explicit")
        } catch { XCTAssertEqual(error as? ReceiptValidationError, .invalidTimestamp) }
        var fields = record.current.fields
        fields.currency = nil; fields.total = ReceiptMoney(minorUnits: 1, currency: .cad)
        do { try fields.validate(); XCTFail("Money with unknown/mismatched currency must be rejected") }
        catch { XCTAssertEqual(error as? ReceiptValidationError, .currencyMismatch) }
        let fetched = try await store.receipt(id: record.id); XCTAssertEqual(fetched, record)
        try await store.close()
    }
}

final class ReceiptDomainTests: XCTestCase {
    func testMoneyBoundaryArithmeticAndCurrencyMismatch() throws {
        let max = ReceiptMoney(minorUnits: .max, currency: .cad), min = ReceiptMoney(minorUnits: .min, currency: .cad)
        let one = ReceiptMoney(minorUnits: 1, currency: .cad)
        XCTAssertEqual(try one.adding(one).minorUnits, 2)
        XCTAssertEqual(try one.subtracting(one).minorUnits, 0)
        XCTAssertThrowsError(try max.adding(one)) { XCTAssertEqual($0 as? ReceiptValidationError, .arithmeticOverflow) }
        XCTAssertThrowsError(try min.subtracting(one)) { XCTAssertEqual($0 as? ReceiptValidationError, .arithmeticOverflow) }
        let usd = ReceiptMoney(minorUnits: 1, currency: try ReceiptCurrency(code: "USD", minorUnitScale: 2))
        XCTAssertThrowsError(try one.adding(usd)) { XCTAssertEqual($0 as? ReceiptValidationError, .currencyMismatch) }
        XCTAssertEqual(try JSONDecoder().decode(ReceiptMoney.self, from: JSONEncoder().encode(max)), max)
        XCTAssertEqual(try JSONDecoder().decode(ReceiptMoney.self, from: JSONEncoder().encode(min)), min)
    }

    func testExactDecimalsAndDecodedBounds() throws {
        let quantity = try ReceiptDecimal(coefficient: 1250, scale: 3)
        let rate = try ReceiptDecimal(coefficient: 13, scale: 2)
        XCTAssertEqual(try JSONDecoder().decode(ReceiptDecimal.self, from: JSONEncoder().encode(quantity)), quantity)
        XCTAssertEqual(rate.coefficient, 13); XCTAssertEqual(rate.scale, 2)
        XCTAssertThrowsError(try ReceiptDecimal(coefficient: 1, scale: 10))
        XCTAssertThrowsError(try JSONDecoder().decode(ReceiptDecimal.self, from: Data("{\"coefficient\":1,\"scale\":255}".utf8)))
        XCTAssertThrowsError(try ReceiptCurrency(code: "cad", minorUnitScale: 2))
        XCTAssertThrowsError(try ReceiptCurrency(code: "CAD", minorUnitScale: 7))
        XCTAssertThrowsError(try ReceiptDate(year: 2025, month: 2, day: 29))
        XCTAssertNoThrow(try ReceiptDate(year: 2024, month: 2, day: 29))
    }
}
