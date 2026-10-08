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
T05 — import, review and save receipts — accepted. Its user-requested Wallet interaction follow-up is implemented and verified on 2026-10-08, awaiting the user’s design review. T06 — exact item-level bill splitting — remains next and awaits approval.

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
The app now has a usable imported-image review/save workflow. Item splitting, sharing and full-text purchase search await T06/T07; physical camera is deferred. Save explicitly before leaving: backgrounding clears unsaved work. Encrypted contents/Keychain are verified in Simulator; SQLite structural metadata is visible, physical lock enforcement unverified, and backup/export/restore unavailable. The five-receipt T03 pilot recovered 57/66 exact purchase amounts, matched only 2/5 totals and reconciled 0/5 without correction; T05's reference-assisted round trips are not a replacement accuracy score. Human correction time and broader retailer accuracy remain unmeasured. Nine current simulator contrast exceptions are individually documented; device accessibility/material behavior remains unverified. Current deployment target is iOS 27.0; device OS/signing must be checked later.

## Next recommended action
Request approval for T06 — exact item-level bill splitting. Implement a deterministic cent-exact engine, local participant assignments and explicit copy/share output; drafts and unresolved receipts cannot finalize a split. Do not dispatch T06 until the user approves it in the main chat.

## Latest task commit
Current refinement commit message: `fix: refine wallet pocket motion and native date review`. Previous visual refinement: `97d9542` — `fix: refine receipt paper motion and swipe controls`. Previous Wallet follow-up: `825a2da` — `feat: add animated receipt wallet and swipe actions`. The exact signed commit hash and GitHub synchronization are reported in the main chat; use Git history for the hash. Previous commit: `728fcd7` — `fix: redesign wallet and receipt navigation`. T05 workflow commit: `95e69ed` — `feat: add native receipt import and review workflow`.

## T05 design follow-up · 2026-10-08

The user requested a native design audit and redesign after seeing the empty wallet. Removed duplicate import/Original actions and decorative tab-like controls, tightened the Paper lift wallet, made primary actions explicit, reduced instructional clutter and moved storage details into an accessible sheet. [Audit and native screenshots](docs/UI_REDESIGN.md). Seven final native checks passed, including actual Photos/keyboard editing, unique Import, collection navigation, storage disclosure, delete cancellation/confirmation, large text and strict structural audits. Fresh Release signature/Debug-control exclusion verified; 12 specific measured/disabled contrast exceptions documented. T06 remains awaiting approval. Follow-up commit message: `fix: redesign wallet and receipt navigation`; exact signed commit hash is reported after GitHub synchronization.

## T05 Wallet interaction follow-up · 2026-10-08

The user specified the wallet at the top, oldest-to-newest paper order, newest-first layers, in-place expansion with directional departures/return, long-preview fades and customizable swipe actions. Archive moves out of the home stack; stars retain chronology; swipes reveal an action for a tap; deletion confirms. The prior empty-wallet illustration is restored at the user's request, and every paper has both a soft shadow and a contact shadow. Organization and swipe settings persist encrypted, preserving receipt evidence/revisions. [Current design](docs/WALLET_DESIGN.md). Commit message: `feat: add animated receipt wallet and swipe actions`. T06 remains awaiting approval.

Verification: 47 unit checks and 11 native UI checks passed; one physical-protection test remains skipped in Simulator. The native checks cover chronology, expansion/return, long papers, 30-receipt scrolling, swipe actions, archive/star/settings persistence, deletion confirmation, real Photos/keyboard import, and structural accessibility. Eight narrowly documented contrast exceptions remain, with no unresolved findings. Fictional light/dark/large-text screenshots and animation are in [current evidence](docs/evidence/t05-wallet-motion/). Release build/signature and removal of Debug controls verified. This revision awaits user review; T06 remains unapproved.

## T05 Wallet visual refinement · 2026-10-08

The user identified clipped preview shadows, uneven return timing, covered/static swipe actions, paper blinking, missing length extension and an overly dark light-mode crown. Shadows now render outside the content mask. One retained paper silhouette grows/contracts with its torn edge, synchronized with neighboring papers in one animation transaction; a scrolled detail compensates for its reading offset on return. Glass action width/height grow with drag distance, remain inside the revealed gap, and the active row rises above neighbors. The light-mode crown is pale neutral. The previous empty illustration is retained. [Latest design and evidence](docs/WALLET_DESIGN.md). Commit: `fix: refine receipt paper motion and swipe controls`. T06 remains awaiting approval.

Refinement verification: four Wallet interaction and five native accessibility checks passed. Nine narrow contrast exceptions are documented with zero unresolved findings; structural checks remain strict. Reviewed fictional light/dark/empty/long-paper screenshots and opening/return animation frames. Final Release signature/Debug-control exclusion verified and the app installed/normally launched in the simulator. The historical unit/import baseline remains unchanged. [Evidence](docs/evidence/t05-wallet-refinement/validation-summary.json). User design review and T06 approval remain pending.


## T05 bottom pocket, date selector and return layers · 2026-10-08

The wallet now stays at the bottom while papers slide out on an upward swipe and tuck back in on a downward swipe. Both viewport edges fade; previews alternate small tilts and retain layer shadows. Pulling past the last paper rubber-bands the pocket and papers together using their actual measured end. Returning from detail retains the selected paper's original depth, with newer paper and wallet in front throughout. Native graphical date review supports Cancel, Done and Clear without inventing an unknown date. The earlier empty-wallet illustration remains.

Verification: 48 unit passes, one physical-device skip and ten native passes. Three affected flow checks reran after disabling the invisible wallet's detail hit testing; two expansion/return and 30-paper/end-bounce checks passed with the final measured geometry. Nine narrow contrast exceptions remain documented, with zero unresolved findings. Fictional screenshots and motion frames were reviewed, including the joint bounce and return layers. Final Release build/signature/Debug-control exclusion verified; installed and normally launched in the simulator. [Exact scope and evidence](docs/evidence/t05-wallet-pocket/validation-summary.json). Commit: `fix: refine wallet pocket motion and native date review`. User design review and T06 approval remain pending.
