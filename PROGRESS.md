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

## Current task
T01 complete and accepted after main-chat code, test-result and screenshot review. M0 still requires T02 design selection and T03 extraction evaluation.

## Task status
T01: complete and accepted. T02–T07: queued, each awaiting its own approval. The main chat handles all task dispatch and handoffs; IDs are recorded in TASKS.md.

## Blockers and pending inputs
- xcode-select points to standalone Command Line Tools; verified build commands use DEVELOPER_DIR to select full Xcode per shell/command.
- Simulator local Foundation Models availability and generation verified; physical-phone availability remains unverified until its later phase.
- Private real-receipt dataset not supplied yet.
- Wallet design choice pending T02 review.

## Decisions
Native Swift/SwiftUI; Mac/simulator first; original evidence preserved; local processing/storage; deterministic money; cloud and physical camera deferred.

## Known issues
Only a foundation scaffold and synthetic diagnostics exist. No production receipt workflow, measured real-receipt accuracy or verified storage-security claims. Current deployment target is iOS 27.0; device OS/signing must be checked later.

## Next recommended action
Request approval for T02 — Wallet interface concepts. Do not start T02 automatically.

## Latest task commit
T01 commit message: `feat: add verified SwiftUI foundation and local diagnostics`. Use `git log -1` and the GitHub branch to inspect its hash and synchronization status.
