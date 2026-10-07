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
T03 approved and started on 2026-10-07 using the supplied private receipts. T02 complete: user selected Paper lift with restrained layer shadows and native Liquid Glass controls/navigation. M0 still requires extraction evaluation.

## Task status
T01/T02: complete and accepted. T03: approved and in progress. T04–T07: queued, each awaiting its own approval. The main chat handles all task dispatch and handoffs; IDs are recorded in TASKS.md.

## Blockers and pending inputs
- xcode-select points to standalone Command Line Tools; verified build commands use DEVELOPER_DIR to select full Xcode per shell/command.
- Simulator local Foundation Models availability and generation verified; physical-phone availability remains unverified until its later phase.
- Five private HEIC receipt images supplied in `private-receipts/`; Git exclusion verified. Store coverage and ground truth await T03.
- Receipt reference labels must be independently verified before publishing accuracy metrics; pipeline-derived labels alone are provisional.

## Decisions
Native Swift/SwiftUI; Mac/simulator first; Paper lift with layer shadows and native Liquid Glass navigation/controls; one simplified digital receipt layout across stores; original evidence preserved; local processing/storage; deterministic money; cloud and physical camera deferred.

## Known issues
Only a foundation scaffold and synthetic diagnostics exist. No production receipt workflow, measured real-receipt accuracy or verified storage-security claims. Current deployment target is iOS 27.0; device OS/signing must be checked later.

## Next recommended action
Finish and review T03 — Apple receipt extraction evaluation. Bring any required private label verification to the user here. Commit/push accepted results and request approval for T04; do not start it automatically.

## Latest task commit
T02 artifacts: `abccf2e` — `design: add minimalist wallet concepts and consistent receipt layout`. Design-selection follow-up message: `docs: select Paper lift and native Liquid Glass controls`. Use Git history and the GitHub branch to inspect hashes and synchronization status.
