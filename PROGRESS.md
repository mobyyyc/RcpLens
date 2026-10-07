# Progress

## Current milestone
M0 — environment, design and extraction validation.

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

## Current task
T02 design artifacts complete and accepted on 2026-10-07; user choice between Pocket and Paper lift remains pending. M0 still requires design selection and T03 extraction evaluation.

## Task status
T01: complete and accepted. T02: design artifacts complete and accepted; user concept choice pending. T03–T07: queued, each awaiting its own approval. The main chat handles all task dispatch and handoffs; IDs are recorded in TASKS.md.

## Blockers and pending inputs
- xcode-select points to standalone Command Line Tools; verified build commands use DEVELOPER_DIR to select full Xcode per shell/command.
- Simulator local Foundation Models availability and generation verified; physical-phone availability remains unverified until its later phase.
- Five private HEIC receipt images supplied in `private-receipts/`; Git exclusion verified. Store coverage and ground truth await T03.
- Wallet design choice pending user review of the completed T02 preview. Recommendation: Pocket; no choice assumed.

## Decisions
Native Swift/SwiftUI; Mac/simulator first; minimalist native iOS 27 appearance with depth; one simplified digital receipt layout across stores; original evidence preserved; local processing/storage; deterministic money; cloud and physical camera deferred.

## Known issues
Only a foundation scaffold and synthetic diagnostics exist. No production receipt workflow, measured real-receipt accuracy or verified storage-security claims. Current deployment target is iOS 27.0; device OS/signing must be checked later.

## Next recommended action
Present Pocket/Paper lift for selection and request approval for T03 — Apple receipt extraction evaluation using the supplied private images. Do not start T03 automatically. A pending concept choice does not prevent extraction evaluation, but must be resolved before T05.

## Latest task commit
T02 commit message: `design: add minimalist wallet concepts and consistent receipt layout`. Use `git log -1` and the GitHub branch to inspect its hash and synchronization status.
