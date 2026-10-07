# MVP milestone plan

## M0: Validate environment, design and extraction
T01: Xcode/SwiftUI foundation and synthetic local AI/OCR smoke test.
T02: Two wallet concepts and user design selection.
T03: Reproducible extraction comparison against real receipt ground truth.

Exit: simulator build works; local AI availability is known; recognition decision has evidence or a clearly documented provisional fallback; wallet design chosen.

## M1: Store purchase records
T04: Models, verified storage protections, evidence, migrations and CRUD.

Exit: records/assets survive restart, preserve provenance and delete cleanly.

## M2: Usable imported-image receipt demo
T05: Import -> extract -> correct -> save -> reopen.

Exit: usable with real receipts from the supported initial retailer set; failures are visible and correctable.

## M3: Immediate and lasting utility
T06: Exact item splits and share summary.
T07: Chronological history and local full-text search.

Exit: a saved real receipt produces an exact split and is findable by purchased item later.

## Next phase, not task-broken yet
Physical iPhone 15 Pro camera capture, phone-specific performance/privacy validation, repeated personal dogfood, reliability hardening and eventual trusted testers.

## Execution
Tasks are separate user-owned chats in the RcpLens project. They are initially queued: inspect prerequisites on their first turn, then wait for the user to start implementation. This prevents concurrent edits to the same new app. Start T01 after the runtime download completes. T02 can proceed independently with standalone artifacts. Run T03 and T04 after T01, initially sequentially. T05 requires T02 design approval plus T03/T04. T06/T07 follow T05. Each task updates its status, evidence and next step in PROGRESS.md and TASKS.md only when implementing, and preserves other task entries.

Detailed acceptance criteria and test requirements are in TASKS.md. Keep the registry concise; do not create distant-roadmap tasks.

The user's main point of contact is the original planning chat. See [docs/WORKFLOW.md](docs/WORKFLOW.md) for the coordination workflow and the instruction that authorizes messaging the existing task chats. The user should not need to select task chats or manage their dependency order.
