# MVP milestone plan

## M0: Validate environment, design and extraction
T01: Xcode/SwiftUI foundation and synthetic local AI/OCR smoke test.
T02: Two wallet concepts and user design selection. Complete; Paper lift selected with layer shadows and native Liquid Glass controls/navigation.
T03: Reproducible extraction comparison against real receipt ground truth.

Status: complete and accepted. Five human-verified receipts support Vision plus deterministic parsing for a manual-review pilot; none fully reconciled without correction. See [OCR evaluation](docs/OCR_EVALUATION.md). Broader retailer accuracy and physical-device performance remain unverified.

Exit: simulator build works; local AI availability is known; recognition decision has evidence or a clearly documented provisional fallback; wallet design chosen.

## M1: Store purchase records
T04: Models, verified storage protections, evidence, migrations and CRUD.

Status: complete and accepted on 2026-10-07. Encrypted receipt/image payloads, real simulator Keychain, migrations, rollback/relaunch and deletion verified; physical-device file-protection enforcement remains deferred. See [storage verification](docs/STORAGE.md).

Exit: records/assets survive restart, preserve provenance and delete cleanly.

## M2: Usable imported-image receipt demo
T05: Import -> extract -> correct -> save -> reopen.

Status: complete and accepted on 2026-10-07. Native photo import/editing, encrypted save/reopen/delete and five private receipt round-trips verified. Two reference-assisted corrections finished; three retained unresolved fields/totals as drafts. See [imported receipt demo](docs/IMPORT_DEMO.md) for evidence and simulator/device limitations.

Exit: usable with real receipts from the supported initial retailer set; failures are visible and correctable.

## M3: Immediate and lasting utility
T06: Exact item splits and share summary.
T07: Chronological history and local full-text search.

Status: demo implementation complete in Simulator; user review pending. T06 exact splitting and the wallet-transition refinement are accepted through T07 approval. T07 chronological history and local merchant/item/SKU search are implemented and verified; independent main-chat review and normal Release restoration are complete; user review remains. See [search contract and evidence](docs/SEARCH.md).

Exit: a saved real receipt produces an exact split and is findable by purchased item later.

## Next phase proposal · 2026-10-09

The user has tested the iPhone 15 Pro build and reports that Face ID and the other app functions work well, with receipt recognition the remaining major weakness. Camera capture and privacy/UI follow-ups are implemented. This feedback does not replace a measured recognition or full device-protection test.

The proposed next version focuses on recognition accuracy, correction effort, portable restore and everyday reliability before purchase-memory features. See [draft v0.2 roadmap](docs/NEXT_VERSION.md). P2-01 recognition audit was separately approved and is complete after independent review. P2-02 capture/document-layout experiments were separately approved and independently accepted; no candidate passed the measured no-regression gate, so P2-02 promoted no production change. See [comparison](docs/CAPTURE_LAYOUT_EVALUATION.md). P2-03 retailer parsing is complete and independently accepted, improving merchant/date/total interpretation while exact purchase recovery remains 57/66. P2-04 faster corrections is the next proposed task. The user confirmed entirely on-device recognition and personal testing for v0.2.

## Execution

The original planning chat remains the user's main point of contact. The seven Phase 1 chats are archived. The user requested five Phase 2 chats on 2026-10-09; P2-01 through P2-03 are complete and accepted; P2-04 and P2-05 await sequential task approvals. Do not create additional chats without an explicit request. Approve one next task at a time here, verify its changes, commit/push the verified result, then report the preceding task, current milestone, actual commit message/hash and proposed next task before asking for approval. Default to one app implementation task at a time. The next-version roadmap remains a draft; its audit, capture/document-layout comparison and limited retailer-parsing improvement are accepted, and its next proposed task is faster corrections. Keep TASKS.md and PROGRESS.md current and avoid creating distant implementation tasks.

Detailed acceptance criteria and test requirements are in TASKS.md. Keep the registry concise; do not create distant-roadmap tasks.

The user's main point of contact is the original planning chat. See [docs/WORKFLOW.md](docs/WORKFLOW.md) for the coordination workflow and the instruction that authorizes messaging the existing task chats. The user should not need to select task chats or manage their dependency order.
