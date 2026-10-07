# Progress

## Current milestone
M0 — environment, design and extraction validation: complete and accepted. M1 — store purchase records: next, awaiting T04 approval.

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

## Current task
T03 complete and accepted on 2026-10-07. T04 — receipt schema and local storage — is the proposed next task; it has not started.

## Task status
T01–T03: complete and accepted. T04: next, awaiting approval. T05–T07: queued, each awaiting its own approval. The main chat handles all task dispatch and handoffs; IDs are recorded in TASKS.md.

## Blockers and pending inputs
- xcode-select points to standalone Command Line Tools; verified build commands use DEVELOPER_DIR to select full Xcode per shell/command.
- Simulator local Foundation Models availability and generation verified; physical-phone availability remains unverified until its later phase.
- Five private HEIC images and independently checked human labels are present, matched to original hashes and Git-ignored. No additional reference-label input is pending.
- Apple's OCRTool image-model path is unavailable in Simulator; the actual comparison ran on the Mac. The selected Vision route and manual review are suitable for the next simulator demo.

## Decisions
Native Swift/SwiftUI; Mac/simulator first; Paper lift with layer shadows and native Liquid Glass navigation/controls; one simplified digital receipt layout across stores; original evidence preserved; local processing/storage; deterministic money; Vision plus deterministic parsing with mandatory source correction and reconciliation. Local model variants remain evaluation-only; cloud and physical camera deferred.

## Known issues
The app remains a foundation scaffold with synthetic diagnostics; the extraction harness is separate. No production receipt workflow or verified storage-security claims yet. The five-receipt pilot recovered 57/66 exact purchase amounts with the selected route, but matched only 2/5 totals and reconciled 0/5 without correction. Correction-operation counts are proxies; human correction time and broader retailer accuracy remain unmeasured. Current deployment target is iOS 27.0; device OS/signing must be checked later.

## Next recommended action
Request approval for T04 — receipt schema and local storage. Verify persistence, migrations, exact-money models, evidence/edit provenance, deletion and actual storage protections before T05 integrates the native import/review workflow. Do not dispatch T04 automatically.

## Latest task commit
T03 handoff commit message: `feat: add verified local receipt extraction evaluation`. The exact signed commit hash and GitHub synchronization are verified after the commit and reported in the main chat; use Git history for the hash. Prior design-selection commit: `1939192` — `docs: select Paper lift and native Liquid Glass controls`.
