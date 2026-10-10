import Foundation
import CryptoKit

/// One actor per application store. Multiple connections are also serialized by SQLite transactions.
/// The app must close this store on backgrounding and open it again after protected data is available.
actor ReceiptStore {
    static let schemaVersion: Int64 = 2
    static let maximumAssetBytes = 32 * 1024 * 1024
    static let maximumRecordBytes = 8 * 1024 * 1024
    let directory: URL
    private let database: ReceiptSQLiteDatabase
    private let cipher: ReceiptStoreCipher
    #if DEBUG
    enum FaultPoint: Sendable { case afterReceiptWrite, beforeCommit, afterDelete }
    private let fault: (@Sendable (FaultPoint) throws -> Void)?
    #endif

    static func applicationDirectory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true).appendingPathComponent("ReceiptStore", isDirectory: true)
    }

    #if DEBUG
    init(directory: URL, keyProvider: any ReceiptStoreKeyProvider = KeychainReceiptStoreKey(),
         fault: (@Sendable (FaultPoint) throws -> Void)? = nil) throws {
        let opened = try Self.open(directory: directory, keyProvider: keyProvider)
        self.directory = directory; self.database = opened.0; self.cipher = opened.1; self.fault = fault
    }
    #else
    init(directory: URL, keyProvider: any ReceiptStoreKeyProvider = KeychainReceiptStoreKey()) throws {
        let opened = try Self.open(directory: directory, keyProvider: keyProvider)
        self.directory = directory; self.database = opened.0; self.cipher = opened.1
    }
    #endif

    private static func open(directory: URL, keyProvider: any ReceiptStoreKeyProvider) throws
        -> (ReceiptSQLiteDatabase, ReceiptStoreCipher) {
        let fm = FileManager.default
        let url = directory.appendingPathComponent("receipts.sqlite")
        let existed = fm.fileExists(atPath: url.path)
        // Key lookup precedes file creation/protection changes. Locked/denied is distinct from absent.
        let existingKey = try keyProvider.loadKey()
        if existed && existingKey == nil { throw ReceiptStoreError.missingKey }
        let key: Data
        if let existingKey { key = existingKey }
        else { key = try keyProvider.createKey() }
        let cipher = try ReceiptStoreCipher(key: key)
        if !existed {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.protectionKey: FileProtectionType.complete, .posixPermissions: 0o700])
            try protect(directory, directory: true)
        }
        let db = try ReceiptSQLiteDatabase(url: url, create: !existed)
        do {
            let version = try db.integer("PRAGMA user_version")
            guard (0...schemaVersion).contains(version) else { throw ReceiptStoreError.unsupportedSchema(version) }
            if version == 0 {
                // A crash during first-open may leave an empty SQLite file, but never a committed receipt.
                guard try db.integer("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0 else {
                    throw ReceiptStoreError.corruptStore
                }
            } else {
                try verifyManifest(db, cipher)
            }
            try protect(directory, directory: true)
            try protect(url, directory: false)
            try configure(db)
            try db.transaction {
                // Recheck under the write lock for overlapping first opens.
                let lockedVersion = try db.integer("PRAGMA user_version")
                if lockedVersion == 0 {
                    guard try db.integer("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0 else {
                        throw ReceiptStoreError.corruptStore
                    }
                    try createVersionOne(db, cipher)
                } else { try verifyManifest(db, cipher) }
                try migrate(db, cipher)
            }
            let check = try db.run("PRAGMA quick_check")
            guard check.count == 1,
                  case .text("ok") = check[0][0],
                  try db.run("PRAGMA foreign_key_check").isEmpty else { throw ReceiptStoreError.corruptStore }
            return (db, cipher)
        } catch {
            try? db.close()
            throw error
        }
    }

    private static func protect(_ url: URL, directory: Bool) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete,
                                               .posixPermissions: directory ? 0o700 : 0o600], ofItemAtPath: url.path)
        var mutableURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try mutableURL.setResourceValues(values)
        guard try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
            throw ReceiptStoreError.protectionUnavailable
        }
        #if !targetEnvironment(simulator)
        guard try FileManager.default.attributesOfItem(atPath: url.path)[.protectionKey] as? FileProtectionType == .complete else {
            throw ReceiptStoreError.protectionUnavailable
        }
        #endif
    }

    private static func configure(_ db: ReceiptSQLiteDatabase) throws {
        try db.run("PRAGMA foreign_keys = ON")
        try db.run("PRAGMA journal_mode = DELETE")
        try db.run("PRAGMA synchronous = FULL")
        try db.run("PRAGMA fullfsync = ON")
        try db.run("PRAGMA secure_delete = ON")
        try db.run("PRAGMA temp_store = MEMORY")
        try db.run("PRAGMA cache_size = -2048")
        try db.run("PRAGMA cache_spill = ON")
        guard try db.integer("PRAGMA foreign_keys") == 1,
              try db.integer("PRAGMA synchronous") == 2,
              try db.integer("PRAGMA secure_delete") == 1,
              try db.integer("PRAGMA temp_store") == 2 else { throw ReceiptStoreError.corruptStore }
    }

    /// v1 is retained as a real historical migration contract and used by synthetic migration fixtures.
    static func createVersionOne(_ db: ReceiptSQLiteDatabase, _ cipher: ReceiptStoreCipher) throws {
        try db.run("CREATE TABLE metadata (name TEXT PRIMARY KEY NOT NULL, value BLOB NOT NULL)")
        try db.run("CREATE TABLE receipts (id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL)")
        try db.run("CREATE TABLE assets (id TEXT PRIMARY KEY NOT NULL, receipt_id TEXT NOT NULL UNIQUE REFERENCES receipts(id) ON DELETE CASCADE, payload BLOB NOT NULL)")
        try db.run("INSERT INTO metadata VALUES ('key-check', ?)",
                   [.blob(cipher.seal(ReceiptStoreCipher.manifest, context: ReceiptStoreCipher.manifestContext))])
        try db.run("PRAGMA user_version = 1")
    }

    private static func verifyManifest(_ db: ReceiptSQLiteDatabase, _ cipher: ReceiptStoreCipher) throws {
        let rows = try db.run("SELECT value FROM metadata WHERE name = 'key-check'")
        guard rows.count == 1, case .blob(let sealed) = rows[0][0] else { throw ReceiptStoreError.corruptStore }
        guard try cipher.open(sealed, context: ReceiptStoreCipher.manifestContext) == ReceiptStoreCipher.manifest else {
            throw ReceiptStoreError.authenticationFailed
        }
    }

    private static func migrate(_ db: ReceiptSQLiteDatabase, _ cipher: ReceiptStoreCipher) throws {
        let version = try db.integer("PRAGMA user_version")
        guard (1...schemaVersion).contains(version) else { throw ReceiptStoreError.unsupportedSchema(version) }
        if version == 1 {
            let rows = try db.run("SELECT id, payload FROM receipts")
            // Decode/authenticate/validate all old records and ownership before changing the schema.
            let records = try rows.map { row -> ReceiptRecord in
                guard case .text(let text) = row[0], let id = UUID(uuidString: text),
                      case .blob(let data) = row[1] else { throw ReceiptStoreError.corruptStore }
                let record = try decode(data, id: id, cipher: cipher)
                try verifyAsset(record, db: db, cipher: cipher)
                return record
            }
            guard try db.integer("SELECT count(*) FROM assets") == records.count else { throw ReceiptStoreError.corruptStore }
            try db.run("ALTER TABLE receipts ADD COLUMN updated_at INTEGER NOT NULL DEFAULT 0")
            for record in records {
                try db.run("UPDATE receipts SET updated_at = ? WHERE id = ?",
                           [.integer(try milliseconds(record.updatedAt)), .text(record.id.uuidString)])
            }
            try db.run("CREATE INDEX receipts_updated ON receipts(updated_at DESC, id)")
            try db.run("PRAGMA user_version = 2")
        }
    }

    private static func milliseconds(_ date: Date) throws -> Int64 {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, (-62_135_596_800...253_402_300_799).contains(seconds) else {
            throw ReceiptValidationError.invalidTimestamp
        }
        return Int64((seconds * 1_000).rounded(.towardZero))
    }

    private static func decode(_ sealed: Data, id: UUID, cipher: ReceiptStoreCipher) throws -> ReceiptRecord {
        let bytes = try cipher.open(sealed, context: ReceiptStoreCipher.receiptContext(id))
        guard bytes.count <= maximumRecordBytes else { throw ReceiptStoreError.sizeLimit }
        let record: ReceiptRecord
        do { record = try JSONDecoder().decode(ReceiptRecord.self, from: bytes) }
        catch { throw ReceiptStoreError.corruptStore }
        guard record.id == id else { throw ReceiptStoreError.corruptStore }
        try record.validate()
        return record
    }

    private func encode(_ record: ReceiptRecord) throws -> Data {
        try record.validate()
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count <= Self.maximumRecordBytes else { throw ReceiptStoreError.sizeLimit }
        return try cipher.seal(bytes, context: ReceiptStoreCipher.receiptContext(record.id))
    }

    private static func verifyAsset(_ record: ReceiptRecord, db: ReceiptSQLiteDatabase,
                                    cipher: ReceiptStoreCipher) throws {
        let bytes = try asset(record, db: db, cipher: cipher)
        guard bytes.count == record.asset.byteCount, Data(SHA256.hash(data: bytes)) == record.asset.sha256 else {
            throw ReceiptStoreError.corruptStore
        }
    }

    private static func asset(_ record: ReceiptRecord, db: ReceiptSQLiteDatabase,
                              cipher: ReceiptStoreCipher) throws -> Data {
        let rows = try db.run("SELECT id, payload FROM assets WHERE receipt_id = ?", [.text(record.id.uuidString)])
        guard rows.count == 1, case .text(let id) = rows[0][0], id == record.asset.id.uuidString,
              case .blob(let data) = rows[0][1] else { throw ReceiptStoreError.corruptStore }
        return try cipher.open(data, context: ReceiptStoreCipher.assetContext(record.asset.id, owner: record.id))
    }

    private func load(_ id: UUID) throws -> ReceiptRecord? {
        let rows = try database.run("SELECT payload FROM receipts WHERE id = ?", [.text(id.uuidString)])
        guard let row = rows.first else { return nil }
        guard case .blob(let data) = row[0] else { throw ReceiptStoreError.corruptStore }
        return try Self.decode(data, id: id, cipher: cipher)
    }

    func receipt(id: UUID) throws -> ReceiptRecord? {
        try database.transaction {
            guard let record = try load(id) else { return nil }
            // Ensure a record never appears valid while its evidence is missing or damaged.
            try Self.verifyAsset(record, db: database, cipher: cipher)
            return record
        }
    }

    /// Decrypted snapshots for later local history/search. No plaintext index is created here.
    func receipts() throws -> [ReceiptRecord] {
        try database.transaction {
            try database.run("SELECT id, payload FROM receipts ORDER BY updated_at DESC, id").map { row in
                guard case .text(let text) = row[0], let id = UUID(uuidString: text),
                      case .blob(let data) = row[1] else { throw ReceiptStoreError.corruptStore }
                let record = try Self.decode(data, id: id, cipher: cipher)
                let owners = try database.run("SELECT id FROM assets WHERE receipt_id = ?", [.text(id.uuidString)])
                guard owners.count == 1, case .text(let assetID) = owners[0][0], assetID == record.asset.id.uuidString else {
                    throw ReceiptStoreError.corruptStore
                }
                return record
            }
        }
    }

    func originalImage(receiptID: UUID) throws -> Data {
        try database.transaction {
            guard let record = try load(receiptID) else { throw ReceiptStoreError.notFound }
            let bytes = try Self.asset(record, db: database, cipher: cipher)
            guard bytes.count == record.asset.byteCount, Data(SHA256.hash(data: bytes)) == record.asset.sha256 else {
                throw ReceiptStoreError.corruptStore
            }
            return bytes
        }
    }

    @discardableResult
    func create(extraction: ReceiptExtraction, originalImage: Data, mediaType: String,
                now: Date = Date(), correction: ReceiptFields? = nil,
                review: ReceiptRevision.Review = .draft, reviewInput: Data? = nil, permit: ReceiptOperationPermit? = nil) throws -> ReceiptRecord {
        try permit?.check()
        guard !originalImage.isEmpty, ["image/png", "image/jpeg", "image/heic", "image/heif"].contains(mediaType) else {
            throw ReceiptStoreError.invalidAsset
        }
        guard originalImage.count <= Self.maximumAssetBytes else { throw ReceiptStoreError.sizeLimit }
        try extraction.validate()
        let id = UUID(), assetID = UUID()
        let record = ReceiptRecord(id: id, createdAt: now, updatedAt: now, original: extraction,
            asset: ReceiptAsset(id: assetID, mediaType: mediaType, byteCount: originalImage.count,
                                sha256: Data(SHA256.hash(data: originalImage))),
            revisions: [ReceiptRevision(id: UUID(), createdAt: now, fields: extraction.fields, review: .draft)]
                + (correction.map { [ReceiptRevision(id: UUID(), createdAt: now, fields: $0, review: review, reviewInput: reviewInput)] } ?? []))
        let payload = try encode(record)
        let image = try cipher.seal(originalImage, context: ReceiptStoreCipher.assetContext(assetID, owner: id))
        try database.transaction(permit: permit) {
            try permit?.check()
            try database.run("INSERT INTO receipts (id, payload, updated_at) VALUES (?, ?, ?)",
                             [.text(id.uuidString), .blob(payload), .integer(try Self.milliseconds(now))])
            #if DEBUG
            try fault?(.afterReceiptWrite)
            #endif
            try database.run("INSERT INTO assets (id, receipt_id, payload) VALUES (?, ?, ?)",
                             [.text(assetID.uuidString), .text(id.uuidString), .blob(image)])
            #if DEBUG
            try fault?(.beforeCommit)
            #endif
            try permit?.check()
        }
        return record
    }

    /// Append-only corrections. expectedRevision rejects stale editors instead of overwriting work.
    @discardableResult
    func revise(id: UUID, expectedRevision: UUID, fields: ReceiptFields,
                review: ReceiptRevision.Review = .draft, now: Date = Date(), reviewInput: Data? = nil,
                permit: ReceiptOperationPermit? = nil) throws -> ReceiptRecord {
        try permit?.check()
        return try database.transaction(permit: permit) {
            try permit?.check()
            guard let old = try load(id) else { throw ReceiptStoreError.notFound }
            guard old.current.id == expectedRevision else { throw ReceiptStoreError.editConflict }
            try Self.verifyAsset(old, db: database, cipher: cipher)
            let next = ReceiptRecord(id: old.id, createdAt: old.createdAt, updatedAt: now,
                original: old.original, asset: old.asset,
                revisions: old.revisions + [ReceiptRevision(id: UUID(), createdAt: now, fields: fields, review: review, reviewInput: reviewInput)],
                organization: old.organization, splitPlan: old.splitPlan?.rebased(to: fields))
            try database.run("UPDATE receipts SET payload = ?, updated_at = ? WHERE id = ?",
                             [.blob(try encode(next)), .integer(try Self.milliseconds(now)), .text(id.uuidString)])
            #if DEBUG
            try fault?(.beforeCommit)
            #endif
            try permit?.check()
            return next
        }
    }

    /// Organization does not rewrite purchase evidence or invent a correction revision.
    @discardableResult
    func organize(id: UUID, expectedRevision: UUID, action: ReceiptWalletAction,
                  permit: ReceiptOperationPermit? = nil) throws -> ReceiptRecord {
        try permit?.check()
        guard action == .archive || action == .star else { throw ReceiptStoreError.corruptStore }
        return try database.transaction(permit: permit) {
            guard var record = try load(id) else { throw ReceiptStoreError.notFound }
            guard record.current.id == expectedRevision else { throw ReceiptStoreError.editConflict }
            var organization = record.organization ?? ReceiptOrganization()
            if action == .archive { organization.archived.toggle() } else { organization.starred.toggle() }
            record.organization = organization
            try database.run("UPDATE receipts SET payload = ? WHERE id = ?", [.blob(try encode(record)), .text(id.uuidString)])
            #if DEBUG
            try fault?(.beforeCommit)
            #endif
            try permit?.check()
            return record
        }
    }

    /// Split choices live in the same authenticated payload as the receipt; no plaintext participant table.
    /// Compare both purchase revision and split token so two editors cannot silently overwrite each other.
    @discardableResult
    func saveSplit(id: UUID, expectedRevision: UUID, expectedPlan: UUID?, plan: ReceiptSplitPlan,
                   finalize: Bool, permit: ReceiptOperationPermit? = nil) throws -> ReceiptRecord {
        try permit?.check()
        try plan.validateStructure()
        return try database.transaction(permit: permit) {
            guard var record = try load(id) else { throw ReceiptStoreError.notFound }
            guard record.current.id == expectedRevision, record.splitPlan?.id == expectedPlan else { throw ReceiptStoreError.editConflict }
            try Self.verifyAsset(record, db: database, cipher: cipher)
            var next = plan
            next.id = UUID(); next.finalizedRevision = nil
            if finalize {
                _ = try ReceiptSplitEngine.compute(record, plan: next)
                next.finalizedRevision = record.current.id
            }
            record.splitPlan = next
            try database.run("UPDATE receipts SET payload = ? WHERE id = ?", [.blob(try encode(record)), .text(id.uuidString)])
            #if DEBUG
            try fault?(.beforeCommit)
            #endif
            try permit?.check()
            return record
        }
    }

    func walletSettings() throws -> ReceiptWalletSettings {
        let rows = try database.run("SELECT value FROM metadata WHERE name = 'wallet-settings'")
        guard let row = rows.first else { return ReceiptWalletSettings() }
        guard case .blob(let sealed) = row[0] else { throw ReceiptStoreError.corruptStore }
        let bytes = try cipher.open(sealed, context: "RcpLens/wallet-settings/v1")
        do { return try JSONDecoder().decode(ReceiptWalletSettings.self, from: bytes) }
        catch { throw ReceiptStoreError.corruptStore }
    }

    func saveWalletSettings(_ settings: ReceiptWalletSettings, permit: ReceiptOperationPermit? = nil) throws {
        try permit?.check()
        let payload = try cipher.seal(JSONEncoder().encode(settings), context: "RcpLens/wallet-settings/v1")
        try database.transaction(permit: permit) {
            try database.run("INSERT INTO metadata(name, value) VALUES ('wallet-settings', ?) ON CONFLICT(name) DO UPDATE SET value = excluded.value", [.blob(payload)])
            #if DEBUG
            try fault?(.beforeCommit)
            #endif
            try permit?.check()
        }
    }

    /// Hard local user deletion, never a sync tombstone. Cascade removes the owned original asset.
    /// Idempotent so retrying after interrupted UI feedback is safe.
    func delete(id: UUID, permit: ReceiptOperationPermit? = nil) throws {
        try permit?.check()
        try database.transaction(permit: permit) {
            try permit?.check()
            _ = try database.run("DELETE FROM receipts WHERE id = ?", [.text(id.uuidString)])
            #if DEBUG
            try fault?(.afterDelete)
            try fault?(.beforeCommit)
            #endif
            try permit?.check()
        }
    }

    /// Explicit in-store local purge. Key is retained; no implicit recovery/reset is performed.
    func purgeAllReceipts() throws {
        try database.transaction { _ = try database.run("DELETE FROM receipts") }
    }


    /// Snapshot records and encoded originals under one database lock; only encrypted frames touch disk.
    func exportBackup(to url: URL, password: String, permit: ReceiptOperationPermit) throws {
        try permit.check()
        guard !FileManager.default.fileExists(atPath: url.path) else { throw ReceiptBackupError.unavailable }
        do {
            try database.transaction(permit: permit) {
                let count = try database.integer("SELECT count(*) FROM receipts")
                guard count <= ReceiptBackupArchive.maximumReceipts else { throw ReceiptBackupError.limit }
                let writer = try ReceiptBackupArchive.Writer(url: url, password: password)
                let manifest = ReceiptBackupManifest(version: 1, storeSchema: Self.schemaVersion, createdAt: Date(),
                    receiptCount: Int(count), walletSettings: try walletSettings())
                try writer.write(JSONEncoder().encode(manifest), maximum: 16_384, permit: permit)
                // Query identities only. Never load every encrypted image into memory at once.
                for row in try database.run("SELECT id FROM receipts ORDER BY id") {
                    try permit.check()
                    guard case .text(let text) = row[0], let id = UUID(uuidString: text), let record = try load(id) else {
                        throw ReceiptStoreError.corruptStore
                    }
                    let bytes = try Self.asset(record, db: database, cipher: cipher)
                    try Self.validateBackupEntry(record, bytes: bytes)
                    try writer.write(JSONEncoder().encode(record), maximum: Self.maximumRecordBytes, permit: permit)
                    try writer.write(bytes, maximum: Self.maximumAssetBytes, permit: permit)
                }
                try writer.finish()
            }
        } catch { try? FileManager.default.removeItem(at: url); throw error }
    }

    private static func validateBackupEntry(_ record: ReceiptRecord, bytes: Data) throws {
        try record.validate()
        guard bytes.count <= maximumAssetBytes, bytes.count == record.asset.byteCount,
              Data(SHA256.hash(data: bytes)) == record.asset.sha256,
              ["image/png", "image/jpeg", "image/heic", "image/heif"].contains(record.asset.mediaType) else {
            throw ReceiptBackupError.invalidArchive
        }
        // Validate encoded originals, retaining the exact bytes/metadata; never re-encode or OCR them.
        let decoded = try ReceiptImage.decode(bytes)
        guard decoded.mediaType == record.asset.mediaType else { throw ReceiptBackupError.invalidArchive }
        guard record.original.rawOCR.count <= 10_000, record.original.issues.count <= 10_000,
              record.original.rawParserOutput.count <= 2 * 1024 * 1024, record.revisions.count <= 1_000 else {
            throw ReceiptBackupError.limit
        }
        _ = try milliseconds(record.createdAt); _ = try milliseconds(record.updatedAt)
        _ = try milliseconds(record.original.capturedAt)
        for revision in record.revisions {
            _ = try milliseconds(revision.createdAt)
            guard revision.fields.items.count + revision.fields.adjustments.count <= 10_000 else { throw ReceiptBackupError.limit }
            if let input = revision.reviewInput {
                guard input.count <= 2 * 1024 * 1024 else { throw ReceiptBackupError.limit }
                let draft: ReceiptReviewDraft
                do { draft = try JSONDecoder().decode(ReceiptReviewDraft.self, from: input) }
                catch { throw ReceiptBackupError.invalidArchive }
                guard draft.lines.count <= 10_000, (draft.guidanceChecks?.count ?? 0) <= 10_000,
                      draft.guidanceChecks?.allSatisfy({ $0.key.utf8.count <= 1_024 && $0.value.utf8.count <= 1_024 }) ?? true else {
                    throw ReceiptBackupError.limit
                }
                guard draft.fields == revision.fields, draft.canSaveDraft,
                      revision.review != .sourceReviewed || draft.canFinalize else { throw ReceiptBackupError.invalidArchive }
            }
        }
        if let plan = record.splitPlan, let finalized = plan.finalizedRevision {
            guard finalized == record.current.id else { throw ReceiptBackupError.invalidArchive }
            _ = try ReceiptSplitEngine.compute(record, plan: plan)
        }
    }

    /// Import into a task-owned empty encrypted store. The caller closes it before preview/merge.
    func stageBackup(from url: URL, password: String, permit: ReceiptOperationPermit) throws -> ReceiptBackupManifest {
        try permit.check()
        guard try database.integer("SELECT count(*) FROM receipts") == 0 else { throw ReceiptBackupError.invalidArchive }
        let reader = try ReceiptBackupArchive.Reader(url: url, password: password)
        let manifest: ReceiptBackupManifest
        do { manifest = try JSONDecoder().decode(ReceiptBackupManifest.self, from: reader.read(maximum: 16_384, permit: permit)) }
        catch let error as ReceiptBackupError { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw ReceiptBackupError.invalidArchive }
        guard manifest.version == 1, manifest.storeSchema == Self.schemaVersion else { throw ReceiptBackupError.unsupported }
        guard (0...ReceiptBackupArchive.maximumReceipts).contains(manifest.receiptCount),
              manifest.createdAt.timeIntervalSince1970.isFinite else { throw ReceiptBackupError.limit }
        try database.transaction(permit: permit) {
            var ids = Set<UUID>(), assets = Set<UUID>()
            for _ in 0..<manifest.receiptCount {
                try permit.check()
                let record: ReceiptRecord
                do { record = try JSONDecoder().decode(ReceiptRecord.self, from: reader.read(maximum: Self.maximumRecordBytes, permit: permit)) }
                catch let error as ReceiptBackupError { throw error }
                catch is CancellationError { throw CancellationError() }
                catch { throw ReceiptBackupError.invalidArchive }
                let bytes = try reader.read(maximum: Self.maximumAssetBytes, permit: permit)
                guard ids.insert(record.id).inserted, assets.insert(record.asset.id).inserted else { throw ReceiptBackupError.invalidArchive }
                try Self.validateBackupEntry(record, bytes: bytes)
                try insertBackupEntry(record, bytes: bytes)
            }
            try reader.finish()
            let payload = try cipher.seal(JSONEncoder().encode(manifest.walletSettings), context: "RcpLens/wallet-settings/v1")
            try database.run("INSERT INTO metadata(name, value) VALUES ('wallet-settings', ?)", [.blob(payload)])
            try permit.check()
        }
        return manifest
    }
    private func insertBackupEntry(_ record: ReceiptRecord, bytes: Data) throws {
        try database.run("INSERT INTO receipts (id, payload, updated_at) VALUES (?, ?, ?)",
            [.text(record.id.uuidString), .blob(try encode(record)), .integer(try Self.milliseconds(record.updatedAt))])
        #if DEBUG
        try fault?(.afterReceiptWrite)
        #endif
        let image = try cipher.seal(bytes, context: ReceiptStoreCipher.assetContext(record.asset.id, owner: record.id))
        try database.run("INSERT INTO assets (id, receipt_id, payload) VALUES (?, ?, ?)",
            [.text(record.asset.id.uuidString), .text(record.id.uuidString), .blob(image)])
    }
    private func withPrepared<T>(_ prepared: ReceiptPreparedBackup, _ body: (ReceiptSQLiteDatabase, ReceiptStoreCipher) throws -> T) throws -> T {
        let staged = try ReceiptSQLiteDatabase(url: prepared.directory.appendingPathComponent("receipts.sqlite"), create: false)
        defer { try? staged.close() }
        let stagingCipher = try ReceiptStoreCipher(key: prepared.key)
        try Self.verifyManifest(staged, stagingCipher)
        return try staged.transaction { try body(staged, stagingCipher) }
    }
    private func backupPreview(_ prepared: ReceiptPreparedBackup, staged: ReceiptSQLiteDatabase,
                               stagingCipher: ReceiptStoreCipher, permit: ReceiptOperationPermit) throws -> ReceiptBackupPreview {
        let rows = try staged.run("SELECT id FROM receipts ORDER BY id")
        guard rows.count == prepared.manifest.receiptCount else { throw ReceiptBackupError.invalidArchive }
        var added = 0, skipped = 0, conflicts = 0
        for row in rows {
            try permit.check()
            guard case .text(let text) = row[0], let id = UUID(uuidString: text),
                  let payloadRow = try staged.run("SELECT payload FROM receipts WHERE id = ?", [.text(text)]).first,
                  case .blob(let payload) = payloadRow[0] else { throw ReceiptBackupError.invalidArchive }
            let incoming = try Self.decode(payload, id: id, cipher: stagingCipher)
            if let existing = try load(id) {
                skipped += 1
                if incoming != existing { conflicts += 1 }
            } else {
                guard try database.run("SELECT id FROM assets WHERE id = ?", [.text(incoming.asset.id.uuidString)]).isEmpty else {
                    throw ReceiptBackupError.assetCollision
                }
                added += 1
            }
        }
        return ReceiptBackupPreview(total: rows.count, added: added, skipped: skipped, conflicts: conflicts)
    }
    func previewBackup(_ prepared: ReceiptPreparedBackup, permit: ReceiptOperationPermit) throws -> ReceiptBackupPreview {
        try withPrepared(prepared) { staged, stagingCipher in
            try database.transaction(permit: permit) { try backupPreview(prepared, staged: staged, stagingCipher: stagingCipher, permit: permit) }
        }
    }
    /// Merge only. Existing records always win, including divergent revisions. Preferences stay local.
    /// Every new record/asset is re-encrypted with this device's key in one atomic transaction.
    func mergeBackup(_ prepared: ReceiptPreparedBackup, expected: ReceiptBackupPreview,
                     permit: ReceiptOperationPermit) throws -> ReceiptBackupPreview {
        try permit.check()
        return try withPrepared(prepared) { staged, stagingCipher in
            try database.transaction(permit: permit) {
                let preview = try backupPreview(prepared, staged: staged, stagingCipher: stagingCipher, permit: permit)
                guard preview == expected else { throw ReceiptBackupError.changedPreview }
                for row in try staged.run("SELECT id FROM receipts ORDER BY id") {
                    try permit.check()
                    guard case .text(let text) = row[0], let id = UUID(uuidString: text) else { throw ReceiptBackupError.invalidArchive }
                    if try load(id) != nil { continue }
                    guard let payloadRow = try staged.run("SELECT payload FROM receipts WHERE id = ?", [.text(text)]).first,
                          case .blob(let payload) = payloadRow[0] else { throw ReceiptBackupError.invalidArchive }
                    let record = try Self.decode(payload, id: id, cipher: stagingCipher)
                    let bytes = try Self.asset(record, db: staged, cipher: stagingCipher)
                    try Self.validateBackupEntry(record, bytes: bytes)
                    try insertBackupEntry(record, bytes: bytes)
                }
                #if DEBUG
                try fault?(.beforeCommit)
                #endif
                try permit.check()
                return preview
            }
        }
    }

    func close() throws { try database.close() }
}
