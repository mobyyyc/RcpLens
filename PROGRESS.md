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

## Current task
T01 queued and ready for environment validation; iOS 27.0 runtime installation is verified.

## Task status
T01–T07: queued; seven separate chats created under the RcpLens project. IDs are recorded in TASKS.md. Initial chat turns only check readiness; implementation begins when the user starts a task.

## Blockers and pending inputs
- Simulator Foundation Models availability unverified.
- xcode-select currently points to standalone Command Line Tools.
- Mac Apple Intelligence enabled/downloaded status unverified.
- Private real-receipt dataset not supplied yet.
- Wallet design choice pending T02 review.

## Decisions
Native Swift/SwiftUI; Mac/simulator first; original evidence preserved; local processing/storage; deterministic money; cloud and physical camera deferred.

## Known issues
No application code yet. No measured real-receipt accuracy or verified security claims.

## Next recommended action
Start T01 to validate the simulator build and local AI/OCR. T02 can be explored independently.
