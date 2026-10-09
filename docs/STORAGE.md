# T04 storage implementation and verification

Verified 2026-10-07 on Xcode 27.0 / Swift 6.4, iOS 27.0 (24A434), iPhone 18 Pro arm64 simulator `50661E83-1F58-466B-99F0-9DC517D8EC82`. All inputs were fictional. This task did not read the private receipt corpus, modify extraction/design artifacts, install software, start T05, commit or push. Coordinator registry changes belong to the main chat.

## Implemented boundary

- `Sliplet/Domain/Receipt.swift`: validated currency and Int64 minor-unit money, overflow-checked addition/subtraction, exact coefficient/scale quantities and rates, civil purchase dates, optional financial fields, original OCR/confidence/normalized geometry, exact parser bytes/issues, immutable evidence metadata, UUIDs and append-only correction snapshots.
- `Sliplet/Persistence/ReceiptStore.swift`: actor, transactional create/read/revise/delete/purge, optimistic revision guard, encrypted image ownership, closed-store errors, schema v1→v2 migration, future-version rejection and empty-bootstrap recovery.
- `StoreCipher.swift`: CryptoKit AES-256-GCM with fresh nonce and authenticated receipt/asset/owner/purpose identity; manifest key authentication.
- `StoreKey.swift`: system Keychain creation/read with explicit non-sync and WhenUnlockedThisDeviceOnly accessibility; no replacement for an unreadable key.
- `SQLiteDatabase.swift`: bound statements, sanitized numeric database failures and atomic transactions. No OCR/content/key logging or network calls.
- `SlipletTests/PersistenceTests.swift`: synthetic failure/reopen/migration/key/cleanup/protection/precision tests.
- `SyntheticStorageDiagnostics.swift` and Debug app task: isolated fictional process-relaunch/crash/delete evidence. Neither diagnostic nor fault injection compiles into Release. The foundation screen and its original model/OCR diagnostic remain intact.
- `Configuration/Simulator.entitlements` and simulator-only app build settings: local ad-hoc identity needed by Simulator Keychain. No Apple account/team/provisioning or device signing settings were configured. Device builds continue to derive identity from normal provisioning later.

The selected approach and protection/backup tradeoffs are in [ADR 003](adr/003-local-receipt-storage.md). Receipt documents and image BLOBs are encrypted; database structural metadata is visible. No production store is opened by the current foundation UI.

## Actual validation

| Check | Result |
| --- | --- |
| Final Debug simulator build/test | Succeeded; **27 passed, 0 failed, 1 skipped** out of 28. Includes the three original T01 checks, 23 persistence checks (one hardware skip) and two domain checks. XCTest suite 2.024 s. |
| Final Release simulator build | BUILD SUCCEEDED; no source warnings. Existing App Intents metadata warning remains because the app has no App Intents dependency. |
| Real Keychain | Random 32-byte key persisted across reopen; attribute query confirmed WhenUnlockedThisDeviceOnly and non-sync; duplicate create returned the existing key. Deleting that test key produced missingKey and did not modify the existing database bytes. Test uses unique accounts and cleans them up. |
| Wrong/malformed/missing key | Authentication/invalidKey/missingKey failures, unchanged steady-state database bytes, original receipt still readable with correct key. Simulated locked-Keychain error remained a Keychain status, not a replacement key. |
| Content and image confidentiality | Exact encrypted BLOBs decrypted to original fictional payload/image. Live database contained no synthetic merchant/OCR marker, exact raw parser bytes, original PNG or key bytes. SQLite header intentionally remains readable. Receipt/purpose/asset-owner substitutions and tampering failed authentication. |
| Atomic failures | Injected failure after receipt insert and after asset insert rolled back both rows; edit failure preserved prior revisions; delete failure retained receipt/image. Reopen checks passed. |
| Migrations | Real v1 schema fixture with two revisions/image migrated to v2 with identical receipt and image. Damaged asset aborted migration without advancing version or altering bytes. Future version 999 rejected unchanged. Empty interrupted bootstrap resumed only with an existing key; unversioned nonempty store was not reset. |
| Provenance | Original OCR/parser bytes, uncertainty, optional geometry and initial revision survived correction/reopen. Invalid correction source IDs failed. Manually added lines with no source IDs succeeded. Unknown amounts remained nil. A matching edited total remained draft. |
| Deletion/purge | Live queries contained no receipt or asset after hard deletion; original image became unavailable; deleting again was safe. Deleted ciphertext was absent from the live DB, rollback journal gone. Bulk local purge removed both ownership sides. |
| Directory/database/journal | Directory 0700, DB and live journal 0600. Directory/database backup exclusion flags true. Live journal contained no synthetic receipt or PNG marker. |
| Physical file protection | **Unverified.** This simulator returned nil NSFileProtection attributes; dedicated hardware test explicitly skipped. Complete protection is requested by code/SQLite flags and verified by production-device open, but lock/unlock enforcement requires the later phone phase. |

Reviewable evidence: [xcresult summary](evidence/t04/test-summary.json), [test suite excerpt](evidence/t04/test-results.txt), [validation summary and source hashes](evidence/t04/validation-summary.json), [generated simulator entitlements](evidence/t04/simulator-entitlements.plist). Xcode embeds these in the executable’s Simulator entitlement section; the ad-hoc signature itself has [empty entitlements](evidence/t04/simulator-signature-entitlements.txt). The emitted XML was verified byte-for-byte in the built executable, and actual Simulator Keychain calls passed. This is not device provisioning evidence.

## Actual separate-process checks

The dedicated database is `Library/Application Support/T04SyntheticStore/receipts.sqlite`, using Keychain service `com.mobyyyc.RcpLens.T04-diagnostics` / account `synthetic-only-v1`. It cannot import private images or access the eventual application receipt store. Reports contain counts and booleans only.

1. Debug process **33890** created one fictional record/image and corrected its unknown amount by appending a second draft revision. [Create report](evidence/t04/process-create.json).
2. Termination and new process **33930** reopened the record through real Keychain, verified original extraction/image plus both revisions. [Reopen report](evidence/t04/process-reopen.json).
3. Final bounded-cache diagnostic process **34200** received SIGKILL before COMMIT while inserting a 24 MiB padded fictional PNG BLOB. The resulting **30,216-byte hot rollback journal** had the SQLite hot header and no synthetic plaintext/PNG marker. [Hot journal proof](evidence/t04/process-crash-journal.json).
4. Fresh process **34237** recovered one committed receipt, one asset, both revisions and original bytes. No interrupted receipt/image remained; journal removed and integrity_check returned ok. [Recovery report](evidence/t04/process-recovery.json).
5. Process **34314** hard-deleted the receipt. Fresh process **34434** verified zero receipts/assets, no foreign-key violations and integrity_check ok. [Delete report](evidence/t04/process-delete.json), [deletion reopen report](evidence/t04/process-deletion-reopen.json).

An earlier 8 MiB abrupt-exit trial left a non-hot journal; it verified reopen but did not establish spilled-page recovery. The final test deliberately bounded the SQLite cache and used 24 MiB to establish the hot-journal condition above. Earlier unsigned tests failed Keychain with -34018, and an overly broad protection assertion failed because Simulator returns no attribute. The simulator-only entitlement, ad-hoc signing and explicit physical-protection skip resolved those test assumptions. These are documented environmental limits, not substituted security passes.

## Reproduce builds and tests

From the repository root, use installed Xcode per command; do not change global xcode-select. **Use ad-hoc signing for Keychain tests**; the old T01 `CODE_SIGNING_ALLOWED=NO` command can build but cannot validate Simulator Keychain.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Sliplet.xcodeproj -scheme Sliplet -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/Sliplet-T04-DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

# Use a new, nonexistent resultBundlePath for each run.
xcodebuild -project Sliplet.xcodeproj -scheme Sliplet -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/Sliplet-T04-DerivedData \
  -resultBundlePath /tmp/Sliplet-T04-tests-verified.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
xcrun xcresulttool get test-results summary --path /tmp/Sliplet-T04-tests-verified.xcresult

xcodebuild -project Sliplet.xcodeproj -scheme Sliplet -configuration Release \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/Sliplet-T04-Release-DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
```

For the separate-process checks, install the signed Debug product, then launch each argument with `--terminate-running-process`. Wait for `Library/Caches/synthetic-storage.json` to reflect the requested phase before proceeding; never use this procedure with a real store. `--synthetic-storage-create` explicitly purges only the diagnostic store.

```sh
xcrun simctl install 50661E83-1F58-466B-99F0-9DC517D8EC82 \
  /tmp/Sliplet-T04-DerivedData/Build/Products/Debug-iphonesimulator/Sliplet.app
xcrun simctl launch --terminate-running-process 50661E83-1F58-466B-99F0-9DC517D8EC82 \
  com.mobyyyc.RcpLens --synthetic-storage-create
xcrun simctl launch --terminate-running-process 50661E83-1F58-466B-99F0-9DC517D8EC82 \
  com.mobyyyc.RcpLens --synthetic-storage-reopen
xcrun simctl launch --terminate-running-process 50661E83-1F58-466B-99F0-9DC517D8EC82 \
  com.mobyyyc.RcpLens --synthetic-storage-crash
# Confirm crashRequested report, process exit and hot-journal header before reopening.
xcrun simctl launch --terminate-running-process 50661E83-1F58-466B-99F0-9DC517D8EC82 \
  com.mobyyyc.RcpLens --synthetic-storage-reopen
xcrun simctl launch --terminate-running-process 50661E83-1F58-466B-99F0-9DC517D8EC82 \
  com.mobyyyc.RcpLens --synthetic-storage-delete
xcrun simctl launch --terminate-running-process 50661E83-1F58-466B-99F0-9DC517D8EC82 \
  com.mobyyyc.RcpLens --synthetic-storage-verify-deleted
```

The complete xcresults/build logs are outside Git under `/tmp/Sliplet-T04-*`. Public evidence is aggregate and synthetic only. No raw private fixture or database is source-controlled.

## Integration handoff for T05

Open `ReceiptStore(directory: try ReceiptStore.applicationDirectory())` with the default Keychain provider when protected data is available. Keep one actor in the application lifecycle. Call async actor methods and catch enum failures; never display/log arbitrary OCR/parser/database errors. Original image bytes must be copied directly from import, with accurate media type; storage checks nonempty bytes/type/32 MiB size, but image decoding/format acceptance belongs to the import boundary. Do not render decrypted images to persistent caches or create plaintext thumbnails.

Build `ReceiptExtraction` once from recognition/parser output, with stable OCR/item UUIDs, recognizer/parser identifiers and versions, exact raw parser bytes, geometry when available, original optional fields and explicit issues. Geometry uses Vision's lower-left normalized origin. No geometry/date/currency/amount should be invented. Quantity/rate is coefficient divided by 10^scale (e.g. rate 13/100 means 13%); storage performs no rate multiplication or split rounding. A currency is required whenever an amount is present. Store the exact parsed minor units, with signed values for discounts/adjustments. Original item identity/source text lives in `original`; corrections can change labels, remove lines or add manual lines without overwriting it.

Use `create(extraction:originalImage:mediaType:)` to persist once. Use `receipt(id:)`/`originalImage(receiptID:)` for detailed reopen. Use `revise(id:expectedRevision:fields:review:)` to append a correction; on `editConflict`, reload and present the conflict instead of overwriting. Financial reconciliation and finalization remain T05/T06 responsibilities. `.sourceReviewed` records an explicit user source review only; a matching total does not change review status or authorize a finalized split. Timestamp regression fails validation; callers must resolve/retry explicitly rather than silently alter historical revisions.

`receipts()` returns decrypted documents ordered by last update and UUID, checks asset ownership/existence, and never silently skips a corrupt record. It does not decrypt every image during listing. `receipt(id:)` and image access authenticate the owned image and verify digest/length; damaged image bytes fail then. Corruption/key failures must become visible repair/error states, without automatic reset. T07 can sort by purchase civil date/creation time as appropriate and build a privacy-conscious local search implementation; no persistent plaintext index exists in T04.

Hard-delete with `delete(id:)`; it removes document, revisions, OCR and owned image together. Drop any UI snapshots/search caches for that ID. `purgeAllReceipts()` is explicit local bulk deletion; it keeps the key/schema and is not sync tombstoning or lost-key recovery. Deleted live ciphertext is cleared by SQLite, but copied/backed-up files and flash remnants cannot be promised erased.

On backgrounding or protected-data loss, await `close()`, **release the actor**, and drop decrypted receipt/image state; reopen after unlock. T04 exposes the API but does not implement production lifecycle/UI. Device file/journal protection and physical Keychain lock behavior still need the later phone validation. Local backup is excluded; no export/restore exists, so real save UX must explain local data-loss behavior. Do not silently reset missing/wrong-key stores.

Practical limits: 32 MiB per original asset and 8 MiB per encrypted receipt document (including all revisions). Parser/record encoding errors and caps fail before commit. A 500-receipt history/search performance sample remains T07's acceptance scope. There is no camera, UI import/review integration, sync, export, cloud fallback or accounts here.

## Wallet organization and preferences · 2026-10-08

The T05 wallet follow-up adds an optional encrypted `ReceiptRecord.organization` containing archive/star flags. Historical receipt documents omit this field and continue decoding with both flags false. `organize` runs transactionally with an optimistic correction-revision guard and an optional revocable permit. It loads current organization inside the transaction, toggles only the requested flag, and preserves original extraction, asset, timestamps and correction history. `revise` carries existing organization forward.

`walletSettings`/`saveWalletSettings` use the existing metadata table and authenticated AES-GCM context `Sliplet/wallet-settings/v1`. Missing preferences use Archive-left/Star-right; malformed or unauthentic payloads fail rather than silently reset. Writes honor permit revocation and rollback. These changes do not alter schema version 2 or add a plaintext index. Three new fictional persistence tests cover legacy decoding, edits/reopen, evidence preservation, encrypted metadata, stale revisions, revocation and failure before commit.
