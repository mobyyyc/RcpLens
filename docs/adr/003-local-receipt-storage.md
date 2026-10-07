# ADR 003 — Transactional SQLite with encrypted receipt and image payloads

Accepted implementation for T04, 2026-10-07. Scope is one local iOS store, with no sync, account or cloud service. Physical-device validation remains deferred.

## Decision

Use the installed system SQLite through Swift's `SQLite3` module. Encrypt the complete Codable receipt document (original extraction plus append-only revisions) and exact original image bytes with CryptoKit AES-256-GCM **before** binding them to SQLite. Store the image as an owned BLOB in the same database transaction as the receipt. A random 32-byte Keychain key uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, with synchronization explicitly false. The application uses `Library/Application Support/ReceiptStore/receipts.sqlite` when T05 integrates it.

This is **payload encryption, not whole-database encryption**. SQLite's file header, schema, receipt/asset UUIDs, ownership links, update timestamps, row counts, ciphertext lengths and access patterns remain observable. No merchant, item description, original OCR, parser output, correction, amount, original image or plaintext search index is stored outside ciphertext by this module.

Each ciphertext uses a fresh CryptoKit nonce, and authenticated additional data binds it to a payload format/purpose (`receipt/v1`, `asset/v1`, `manifest/v1`) and receipt/asset identities. Assets also bind to their owner. A manifest authenticates the key on open. Format version in this context is independent of SQL schema version; a future payload-format change must add an explicit reader/migration, never reinterpret v1 ciphertext.

## Alternatives evaluated

| Approach | Assessment |
| --- | --- |
| SQLCipher | Mature full-database/page encryption with additional metadata confidentiality. Its codec is not the installed system SQLite; adoption would require a new dependency/build and maintenance path. Not selected for this local simulator demo. Revisit if structural metadata confidentiality becomes a requirement. |
| SwiftData/Core Data | Mature native model/storage choices. SwiftData supports explicit schema migration plans. They would still need an explicit sensitive-content encryption policy and transactional evidence-ownership design. Direct SQLite makes the ownership constraints, migration transaction and recovery settings small and inspectable here. |
| Atomic encrypted JSON plus image files | Simple initially, but separate image ownership, crash recovery and 500-record rewrites would need more application-level machinery. Not selected. |
| System SQLite plus CryptoKit BLOB encryption | Selected: installed libraries, no dependency installation, one atomic image/document transaction, explicit schema migrations, demonstrable content confidentiality and key failure. Accepts visible structural metadata and in-memory search integration costs. |

We do not claim SQLite itself implements encryption, hardware-backed custom keys, E2EE, tamper-proof storage, replay prevention or guaranteed forensic erasure. GCM detects altered/swapped blobs, but a complete old authenticated store or payload for the same identity can be replayed by someone who can replace app files. SQLite structural corruption is surfaced, not automatically repaired by replacing the database.

## Transaction, recovery and deletion

Use `BEGIN IMMEDIATE`, foreign keys, an asset owner uniqueness constraint and `ON DELETE CASCADE`. Use DELETE-mode rollback journals, FULL synchronous writes, fullfsync, secure_delete, memory temporary storage, a bounded 2 MiB page cache and cache spill. Every receipt/image binding is already ciphertext; journals contain ciphertext and structural metadata. SQLite handles hot-journal rollback on reopen. The app never deletes a journal to recover a store. Operations contain no `await` between BEGIN and COMMIT. Stale revision IDs fail inside the same write transaction, including across two connections.

The current SQL schema is v2. v1 stores the encrypted documents/assets and manifest; v2 authenticates and validates all existing records and their owned assets, adds a chronological update timestamp/index derived from encrypted revision data, and sets `user_version` in the same transaction. A failed migration remains v1 with its original data. Unknown future versions fail without reset. An empty interrupted bootstrap can resume with an existing key; an unversioned database containing any application table cannot be replaced.

User deletion is a hard local DELETE with cascading evidence removal, no tombstone or retained searchable document. `purgeAllReceipts` is an explicit bulk local deletion; it retains schema and key. Sync tombstones are a different future protocol and are not implemented. secure_delete clears deleted BLOB storage in the live file, verified with synthetic ciphertext; filesystem snapshots, flash remapping and previously copied files prevent a physical-erasure guarantee.

## Protection and key failure

Apply Complete file protection with the installed Apple SQLite open flag and Foundation directory/file attributes; verify the returned file-protection attribute on physical iOS, failing open if it differs. Directory mode is 0700, database mode 0600. Exclude the dedicated directory and database from system backup and verify the URL resource flag. Journals are covered by the directory's backup exclusion. These settings add to payload encryption; they do not substitute for it.

Key lookup happens before database creation. Existing database + absent key fails as `missingKey`; an inaccessible Keychain returns its numeric status; malformed keys fail as `invalidKey`; wrong keys fail manifest authentication. There is no fallback key in source/UserDefaults/files, key overwrite, database reset or automatic destructive recovery. Tests compare existing database bytes before/after steady-state missing/wrong-key attempts. SQLite may roll back a hot journal while reading on open; that restores the previous committed state, rather than replacing it. The key remains in memory while the actor exists: **close and release the actor**, drop decrypted snapshots/image buffers on background/protected-data loss, and reopen with Keychain after unlock. `close()` alone closes SQLite but does not zero or remove the retained cipher/key. T05 must wire this lifecycle; T04 has no production UI/store lifecycle yet.

The iOS 27 simulator returned no `NSFileProtection` attributes even after successful setter calls. Its filesystem and Keychain are Mac-hosted; successful AES-GCM/Keychain and backup-flag checks establish simulator behavior, not physical-device lock enforcement. A hardware-protection XCTest is explicitly skipped in Simulator. Later phone validation must exercise lock/unlock, protected-data callbacks, background release and file/journal protection. No physical security claim is accepted based on this simulator run.

## Backup and data-loss tradeoff

All receipt-store files are excluded from ordinary system backup. No cloud backup, manual export or restore UI exists. ThisDeviceOnly restricts migration of the key to another device; it does not mean this key class is never included in a same-device keychain backup. The database is excluded independently. An uninstall/device loss may lose local receipts; Keychain items may survive an uninstall, but that does not restore a deleted database. Losing the key makes retained ciphertext unreadable. The app must present this as a local-storage limitation when a real saving flow is introduced; never silently reset an unreadable store. Explicit lost-key reset/export/import is future UX, not hidden T04 behavior.

## Primary references and installed evidence

Checked Apple's current documentation and installed iPhoneSimulator 27 SDK, including AES.GCM seal/open/combined, Security accessibility constants, and SQLite `SQLITE_OPEN_FILEPROTECTION_COMPLETE` (0x00100000). See [T04 storage verification](../STORAGE.md).

- [Apple CryptoKit AES.GCM](https://developer.apple.com/documentation/cryptokit/aes/gcm)
- [Apple Keychain WhenUnlockedThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly)
- [Apple Complete file protection](https://developer.apple.com/documentation/foundation/fileprotectiontype/complete)
- [Apple encrypting your app's files and protected-data callbacks](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files)
- [Apple backup exclusion resource value](https://developer.apple.com/documentation/foundation/urlresourcevalues/isexcludedfrombackup)
- [Apple SwiftData SchemaMigrationPlan](https://developer.apple.com/documentation/swiftdata/schemamigrationplan)
- [SQLite atomic commit and hot-journal recovery](https://www.sqlite.org/atomiccommit.html)
- [SQLite secure_delete](https://www.sqlite.org/pragma.html#pragma_secure_delete)
- [SQLCipher design](https://www.zetetic.net/sqlcipher/design/)
