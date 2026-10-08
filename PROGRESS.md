# Progress

## Current milestone
M0 — environment, design and extraction validation: complete and accepted. M1 — store purchase records: complete and accepted. M2 — usable imported-image receipt demo: complete and accepted. M3 — exact splits and purchase search: next, awaiting T06 approval.

## Completed
- Full source brief read and empty repository inspected.
- User selected iOS only, No Frills/Costco/T&T and wallet-inspired UI.
- User approved simulator-first, image-import development and task creation.
- Initial Apple documentation research completed; findings remain to be demonstrated locally.
- Xcode 27.0 found at /Applications/Xcode.app.
- Planning documents and seven task chats created, with acceptance criteria and dependencies.
- iOS 27.0 simulator runtime verified installed (build 24A434).
- Local Git repository initialized from the existing GitHub `main` history; original LICENSE preserved. `origin` points to `git@github.com:mobyyyc/RcpLens.git` and local `main` tracks `origin/main`.
- Repository commit identity matches the existing local GitHub profile repository; SSH commit signing remains enabled.
- T01: one native SwiftUI iPhone app and hosted XCTest target; Debug/Release simulator builds and actual launch passed.
- Simulator Foundation Models generated a 39-character synthetic response; Vision recognized expected text from a bundled fictional PNG. Three tests passed with no failures or skips. Commands/evidence: [docs/FOUNDATION.md](docs/FOUNDATION.md).
- T02: two interactive wallet concepts with a shared digital receipt layout; 124 focused browser checks passed. Main-chat review verified final wallet/detail/large-text/dark screenshots and source scope. [Design preview and handoff](docs/design/README.md).
- Paper lift selected, with restrained layer shadows and native Liquid Glass navigation/buttons for the future native interface.
- T03: isolated local extraction harness, five independently human-verified receipts (2 Costco, 2 No Frills, 1 T&T), six fictional image fixtures and a measured recognition decision. Main-chat review passed 14 regression tests, matched final source hashes and independently reproduced the public human-scored aggregate. Runtime and synthetic browser checks passed. [Report](docs/OCR_EVALUATION.md), [ADR 002](docs/adr/002-receipt-recognition.md).
- T04: validated exact-money/evidence models, append-only corrections and transactional encrypted receipt/image storage with real Keychain and schema migrations. Main-chat review matched final source hashes, inspected the actual xcresult (27 passed, 0 failed, 1 hardware skip), verified simulator entitlements and the Release signature. Synthetic process relaunch, hot-journal recovery and complete deletion passed. [Storage report](docs/STORAGE.md), [ADR 003](docs/adr/003-local-receipt-storage.md).
- T05: native image import, local Vision/parser, editable review, drafts and exact finish gate, original-image zoom/linked text, encrypted save/reopen/edit/delete, scene privacy cover and protected-data lifecycle. Paper lift includes shadows and native Glass navigation/buttons; all receipts have month/store browsing. Main-chat review independently checked actual 43-pass/1-hardware-skip unit results, two native workflow passes before the final cosmetic button fix, and three final accessibility/interaction passes with matching source hashes, Release build/signature/Debug-control exclusion, and five private reference-assisted round-trip reports (two finished, three drafts). Synthetic native screenshots reviewed; 14 simulator contrast exceptions individually classified/measured, without device certification. [Demo report](docs/IMPORT_DEMO.md).

## Current task
T05 — import, review and save receipts — complete and accepted on 2026-10-08. T06 — exact item-level bill splitting — is next and awaits approval.

## Task status
T01–T05: complete and accepted. T06/T07: queued, each awaiting its own approval. The main chat handles all task dispatch and handoffs; IDs are recorded in TASKS.md.

## Blockers and pending inputs
- xcode-select points to standalone Command Line Tools; verified build commands use DEVELOPER_DIR to select full Xcode per shell/command.
- Simulator local Foundation Models availability and generation verified; physical-phone availability remains unverified until its later phase.
- Five private HEIC images and independently checked human labels are present, matched to original hashes and Git-ignored. No additional reference-label input is pending.
- Apple's OCRTool image-model path is unavailable in Simulator; the actual comparison ran on the Mac. The selected Vision route and manual review are suitable for the next simulator demo.
- No reference-label input is pending. T05 integrates protected-data lifecycle and explains excluded backup/no restore. Physical file-protection/lock enforcement and device VoiceOver remain later iPhone checks; one hardware XCTest is explicitly skipped in Simulator. Native contrast audit exceptions are documented with synthetic measurements; full material/device certification is unverified.

## Decisions
Native Swift/SwiftUI; Mac/simulator first; Paper lift with layer shadows and native Liquid Glass navigation/controls; one simplified digital receipt layout across stores; original evidence preserved; local processing/storage; deterministic money; Vision plus deterministic parsing with mandatory source correction and reconciliation. Storage uses system SQLite with authenticated encrypted receipt/image payloads and a non-sync Keychain key, with ordinary backup excluded. Local model variants remain evaluation-only; cloud and physical camera deferred.

## Known issues
The app now has a usable imported-image review/save workflow. Item splitting, sharing and full-text purchase search await T06/T07; physical camera is deferred. Save explicitly before leaving: backgrounding clears unsaved work. Encrypted contents/Keychain are verified in Simulator; SQLite structural metadata is visible, physical lock enforcement unverified, and backup/export/restore unavailable. The five-receipt T03 pilot recovered 57/66 exact purchase amounts, matched only 2/5 totals and reconciled 0/5 without correction; T05's reference-assisted round trips are not a replacement accuracy score. Human correction time and broader retailer accuracy remain unmeasured. Fourteen simulator contrast exceptions are individually documented; device accessibility/material behavior remains unverified. Current deployment target is iOS 27.0; device OS/signing must be checked later.

## Next recommended action
Request approval for T06 — exact item-level bill splitting. Implement a deterministic cent-exact engine, local participant assignments and explicit copy/share output; drafts and unresolved receipts cannot finalize a split. Do not dispatch T06 until the user approves it in the main chat.

## Latest task commit
T05 handoff commit message: `feat: add native receipt import and review workflow`. The exact signed commit hash and GitHub synchronization are verified after the commit and reported in the main chat; use Git history for the hash. Previous task commit: `8da4c92` — `feat: add encrypted local receipt storage and provenance`.

## T05 design follow-up · 2026-10-08

The user requested a native design audit and redesign after seeing the empty wallet. Removed duplicate import/Original actions and decorative tab-like controls, tightened the Paper lift wallet, made primary actions explicit, reduced instructional clutter and moved storage details into an accessible sheet. [Audit and native screenshots](docs/UI_REDESIGN.md). Seven final native checks passed, including actual Photos/keyboard editing, unique Import, collection navigation, storage disclosure, delete cancellation/confirmation, large text and strict structural audits. Fresh Release signature/Debug-control exclusion verified; 12 specific measured/disabled contrast exceptions documented. T06 remains awaiting approval. Follow-up commit message: `fix: redesign wallet and receipt navigation`; exact signed commit hash is reported after GitHub synchronization.
