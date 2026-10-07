# MVP milestone plan

## M0: Validate environment, design and extraction
T01: Xcode/SwiftUI foundation and synthetic local AI/OCR smoke test.
T02: Two wallet concepts and user design selection. Design artifacts complete; choice pending.
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
Tasks are separate user-owned chats in the RcpLens project, coordinated from the original planning chat. The user approves one next task at a time here; the main chat starts and follows its execution chat, verifies acceptance, commits/pushes verified changes, then reports completion, current milestone, commit message/hash and next task and asks for approval. Stop before starting another task. T01 is complete and accepted; T02 is approved. Default order is T01, T02, T03, T04, T05, T06, T07. T05 requires T02 design approval plus T03/T04. T06/T07 follow T05. The main chat updates task status and evidence in TASKS.md and PROGRESS.md while preserving other entries.

Detailed acceptance criteria and test requirements are in TASKS.md. Keep the registry concise; do not create distant-roadmap tasks.

The user's main point of contact is the original planning chat. See [docs/WORKFLOW.md](docs/WORKFLOW.md) for the coordination workflow and the instruction that authorizes messaging the existing task chats. The user should not need to select task chats or manage their dependency order.
