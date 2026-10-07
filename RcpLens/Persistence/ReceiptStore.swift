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
                now: Date = Date()) throws -> ReceiptRecord {
        guard !originalImage.isEmpty, ["image/png", "image/jpeg", "image/heic", "image/heif"].contains(mediaType) else {
            throw ReceiptStoreError.invalidAsset
        }
        guard originalImage.count <= Self.maximumAssetBytes else { throw ReceiptStoreError.sizeLimit }
        try extraction.validate()
        let id = UUID(), assetID = UUID()
        let record = ReceiptRecord(id: id, createdAt: now, updatedAt: now, original: extraction,
            asset: ReceiptAsset(id: assetID, mediaType: mediaType, byteCount: originalImage.count,
                                sha256: Data(SHA256.hash(data: originalImage))),
            revisions: [ReceiptRevision(id: UUID(), createdAt: now, fields: extraction.fields, review: .draft)])
        let payload = try encode(record)
        let image = try cipher.seal(originalImage, context: ReceiptStoreCipher.assetContext(assetID, owner: id))
        try database.transaction {
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
        }
        return record
    }

    /// Append-only corrections. expectedRevision rejects stale editors instead of overwriting work.
    @discardableResult
    func revise(id: UUID, expectedRevision: UUID, fields: ReceiptFields,
                review: ReceiptRevision.Review = .draft, now: Date = Date()) throws -> ReceiptRecord {
        try database.transaction {
            guard let old = try load(id) else { throw ReceiptStoreError.notFound }
            guard old.current.id == expectedRevision else { throw ReceiptStoreError.editConflict }
            try Self.verifyAsset(old, db: database, cipher: cipher)
            let next = ReceiptRecord(id: old.id, createdAt: old.createdAt, updatedAt: now,
                original: old.original, asset: old.asset,
                revisions: old.revisions + [ReceiptRevision(id: UUID(), createdAt: now, fields: fields, review: review)])
            try database.run("UPDATE receipts SET payload = ?, updated_at = ? WHERE id = ?",
                             [.blob(try encode(next)), .integer(try Self.milliseconds(now)), .text(id.uuidString)])
            #if DEBUG
            try fault?(.beforeCommit)
            #endif
            return next
        }
    }

    /// Hard local user deletion, never a sync tombstone. Cascade removes the owned original asset.
    /// Idempotent so retrying after interrupted UI feedback is safe.
    func delete(id: UUID) throws {
        try database.transaction {
            _ = try database.run("DELETE FROM receipts WHERE id = ?", [.text(id.uuidString)])
            #if DEBUG
            try fault?(.afterDelete)
            try fault?(.beforeCommit)
            #endif
        }
    }

    /// Explicit in-store local purge. Key is retained; no implicit recovery/reset is performed.
    func purgeAllReceipts() throws {
        try database.transaction { _ = try database.run("DELETE FROM receipts") }
    }

    func close() throws { try database.close() }
}
