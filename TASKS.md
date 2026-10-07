# Near-term task registry

The main chat coordinates these task chats. The user approves one task at a time in the main chat; the main chat verifies, commits/pushes and reports the result before requesting approval for the next task. Dependencies must be verified from actual files/results, not assumed from a chat title.

## T01 — 01 · Xcode and SwiftUI foundation

- Status: complete and accepted after main-chat review (2026-10-07)
- Goal: Verify the Mac development environment and build the smallest native app foundation.
- Why: Simulator AI availability and the toolchain must be demonstrated before relying on them.
- Dependencies: none
- Implementation scope: Verify full Xcode 27, iOS 27 runtime and toolchain selection. Check current Apple guidance before changing toolchain configuration. After the runtime finishes, create a single SwiftUI iPhone app and test target. Add a privacy-safe debug harness that checks Foundation Models availability and generates a response from a synthetic prompt. Confirm an imported synthetic image can run through Vision. Define logical domain, recognition, parsing, persistence and UI folders; avoid a monorepo. Add minimal build/test instructions. Use stable supported APIs and verify against the installed SDK. Initialize Git with private-data exclusions if no Git repository exists.
- Acceptance criteria: App builds and launches in the simulator; Foundation Models either demonstrably generates a synthetic response or produces a precisely documented unavailability reason; Vision accepts a synthetic image; a basic test runs; build commands and versions are recorded.
- Tests: Simulator build and launch, synthetic Vision/Foundation Models smoke checks, test-target execution. Do not log receipt content.
- Risk/notes: iOS 27.0 runtime installation verified (build 24A434). Xcode exists at /Applications/Xcode.app, version 27.0; xcode-select still points to /Library/Developer/CommandLineTools, so use DEVELOPER_DIR or explicit tool paths. Host availability and actual simulator generation are verified available; simulator evidence is recorded below. Mac: M5 Pro, 24 GB, macOS 27.0.1. Do not install software, update macOS or change Apple Intelligence settings without the user's explicit instruction.
- Acceptance evidence: Debug/Release simulator builds and launch passed on iPhone 18 Pro, iOS 27.0 (24A434); local Foundation Models available and generated 39 characters; synthetic Vision PNG matched expected text; 3 XCTest tests passed, 0 failures/skips. Commands, limitations and evidence: [docs/FOUNDATION.md](docs/FOUNDATION.md).
- Chat: 01a117d0-a07f-7ec2-8b4a-4d20ec8fcc67 (local; implementation complete)

## T02 — 02 · Wallet interface concepts

- Status: complete and accepted; user selected Paper lift (2026-10-07)
- Goal: Resolve the wallet interaction and receipt organization before implementing the main screens.
- Why: The user wants receipts to pull out of a wallet, with usable navigation when there are many receipts.
- Dependencies: none
- Implementation scope: Develop two reviewable concepts: a restrained wallet pocket and a more tactile paper/wallet version. Show recent receipts, opening a receipt, editing, processing/error states, all-receipts browsing, empty states and search. Check collections containing 5, 50 and 500 synthetic receipts. Use month grouping and merchant filters as the starting organization; multiple named wallets remain exploratory. Provide accessible tap alternatives to dragging, Dynamic Type, VoiceOver labels and Reduce Motion behaviour. Save standalone design artifacts and recommendations under docs/design; do not modify production app source. Ask the user to choose the direction before production UI implementation.
- Acceptance criteria: Both concepts are reviewable, large-collection browsing is clear, primary actions remain accessible, and a design choice or pending preference is recorded.
- Tests: Visual review at small/large screen and text sizes, reduced-motion interaction review, 5/50/500-receipt navigation walkthrough.
- Acceptance evidence: Two interactive browser concepts, Pocket and Paper lift, share a consistent simplified receipt layout. 124 focused browser checks passed across collection sizes, search/filter/source access, edit/reconciliation, recovery, keyboard/tap/pull and reduced motion; final screenshots visually reviewed. Native Dynamic Type/VoiceOver and device performance remain T05/T07 checks. [Design preview and handoff](docs/design/README.md). User selected Paper lift, with restrained layer shadows and native Liquid Glass navigation/buttons required for T05.
- Risk/notes: Use synthetic receipt content. User approved a minimalist native iOS 27 direction with subtle depth and one simplified, consistent digital receipt format across stores. The two concepts explore interaction within that direction. Original evidence remains separately accessible. No logo or multiple-wallet decision is approved yet. Initial retailer scope is No Frills, Costco and T&T.
- Chat: 01a117d0-a6c8-7d91-bc1c-86b6ad3e6a14 (local; design artifacts complete)

## T03 — 03 · Apple receipt extraction evaluation

- Status: complete and accepted after main-chat review (2026-10-07)
- Goal: Choose a receipt recognition approach using measured evidence.
- Why: API availability does not demonstrate receipt accuracy; the cost of corrections determines usability.
- Dependencies: T01
- Implementation scope: Build an isolated evaluation harness, not production app screens. Compare Vision plus deterministic parsing, the same OCR enriched by Foundation Models, and supported iOS 27 image-assisted Foundation Models extraction. Keep all benchmark execution on device/Mac; explicitly select a local model and avoid automatic cloud routing. Use the same consented private receipt corpus with expected merchant/date/items/amounts/taxes/total; start with 3–5 per retailer if available and expand toward about 30. Use synthetic fixtures while waiting for real images and label them clearly. Exercise long receipts, discounts, quantities, weighted items and mixed-language text where present. Save aggregate results, parser versions, device/OS and reproducible commands. Keep inputs, OCR, generated receipt content and participant identities out of logs. Verify output against source and never let a model compute money allocations.
- Acceptance criteria: Reproducible comparison reports field and item amount accuracy, omissions/invented lines, reconciliation rate, latency and correction burden; recommended approach and fallbacks are documented in an OCR ADR. Synthetic-only evaluation is explicitly provisional, not a claim of real-receipt support.
- Tests: Golden-corpus regression, malformed/model-unavailable output, repeatability and supported-language checks, context limits on long receipts.
- Acceptance evidence: Five independently human-verified receipts (2 Costco, 2 No Frills, 1 T&T), matched to original-image hashes, plus six fictional image fixtures. Main chat independently passed all 14 regression tests, verified final source hashes and reproduced the published human-scored aggregate. Mac local-model runtime and synthetic browser checks passed. Vision plus deterministic parsing recovered 57/66 exact purchase amounts; model paths recovered 33/66 and 26/66 after source validation. Report and decision: [docs/OCR_EVALUATION.md](docs/OCR_EVALUATION.md), [ADR 002](docs/adr/002-receipt-recognition.md).
- Risk/notes: Select Vision plus deterministic parsing for the manual-review demo. No approach fully reconciled any of the five real receipts without correction; the selected route matched only 2/5 totals. Mandatory correction, visible missing fields and deterministic reconciliation remain T05 requirements. Five receipts do not establish broad retailer accuracy. Correction counts are proxies; actual human correction time and adjudicated invented-content counts remain unmeasured. Image/OCRTool model evaluation ran on the Mac; Apple documents OCRTool as unavailable in Simulator. Raw receipts, OCR, proposals and checked references stay private and ignored. No production app changes in this task.
- Chat: 01a117d0-ae9f-7dc3-bcd2-bd84dda035b2 (local; evaluation complete)

## T04 — 04 · Receipt schema and local storage

- Status: complete and accepted after main-chat review (2026-10-07)
- Goal: Persist receipt records and original evidence safely across app restarts.
- Why: The demo must retain purchases, preserve evidence and avoid data loss during edits/deletion.
- Dependencies: T01
- Implementation scope: Implement Swift domain models and a single local persistence approach with explicit schema migrations. Evaluate encrypted SQLite or a mature alternative; document actual protections, key storage and image storage rather than claiming encryption without verification. Store money as Int64 minor units; represent quantities/rates without binary floating-point money arithmetic. Preserve raw OCR/parser evidence and user edits without overwriting originals. Use UUIDs and timestamps suitable for future sync without building sync. Implement transactional receipt CRUD, asset ownership and cleanup, restart recovery and versioned migrations. Distinguish sync tombstones from user deletion; document local purge and backup behaviour. No receipt content in logs or source-controlled private fixtures.
- Acceptance criteria: A synthetic receipt and original asset survive restart; edits preserve extraction provenance; deletions leave no orphaned image or searchable record; selected database protection and missing-key behaviour are verified; migration preserves existing receipts.
- Tests: CRUD/restart, atomic write failure or recovery, migration preserving data, missing-key handling if encryption selected, deletion/asset cleanup and protection verification.
- Acceptance evidence: Exact Swift money/quantity/date/evidence models; append-only corrections; system SQLite with CryptoKit AES-256-GCM receipt and image payloads; real non-sync Keychain key; transactional CRUD and v1→v2 migration. Main-chat review checked source hashes, actual xcresult (27 passed, 0 failed, 1 hardware-protection skip), signed simulator entitlements and Release signature. Separate-process synthetic evidence verified original/image/revision survival, hot-journal rollback and zero receipts/assets after deletion. [Storage verification and T05 handoff](docs/STORAGE.md), [ADR 003](docs/adr/003-local-receipt-storage.md).
- Risk/notes: Payloads are encrypted, but SQLite structure, UUIDs and update metadata remain visible. Simulator cannot demonstrate physical lock/file-protection enforcement; verify on the later phone phase. Receipt store is excluded from ordinary backup; no export/restore yet. T05 must open only when protected data is available, close/release the actor and drop decrypted buffers on background/protected-data loss, expose missing/wrong-key failures without reset and explain local data-loss behavior. No cloud/accounts/E2EE; extraction/design artifacts unchanged.
- Chat: 01a117d0-b64b-7c00-baeb-66673db8436a (local; implementation complete)

## T05 — 05 · Import, review and save receipts

- Status: next task; awaiting user approval
- Goal: Deliver the first usable receipt workflow in the iPhone simulator.
- Why: Importing, correcting and saving real receipts is the core product loop before adding camera capture.
- Dependencies: T01, T02, T03, T04
- Implementation scope: Integrate photo import, the selected local recognition/parser pipeline, truthful processing states, fast merchant/date/item/amount edits, add/remove lines, reconciliation feedback and saved receipt detail. Preserve the original image and offer side-by-side or quick source access. Display uncertainty without treating LLM-generated confidence as calibrated confidence. Handle cancellation, permission denial, failed OCR, unavailable AI and interrupted work. Import real receipt images from a private Mac folder via simulator Photos/photo picker. Build the chosen wallet design after user selection. Do not add physical camera capture yet. Keep capture as an input boundary for the later phone phase.
- Acceptance criteria: A real supported-store image can be imported, reviewed/corrected, saved, reopened after restart and deleted; mismatches and missing fields remain explicit; manual correction is available if AI/OCR fails; interaction remains usable with many receipts.
- Tests: Simulator end-to-end import/edit/save/restart/delete; cancellation and failure cases; correction usability with private No Frills/Costco/T&T images; accessibility and reduced-motion checks.
- Risk/notes: T01–T04 dependencies accepted. Paper lift selected: retain layer shadows and use native Liquid Glass navigation/buttons with accessible alternatives; browser previews approximate the design only. T03 selected Vision plus deterministic parsing with mandatory correction and reconciliation; model paths remain evaluation-only. Follow T04's storage lifecycle, provenance, key-failure and backup handoff in docs/STORAGE.md. Do not claim a finalized test version from synthetic examples alone.
- Chat: 01a117d0-be03-7d12-8ea8-55d5349c89b7 (local; awaiting approval)

## T06 — 06 · Exact item-level bill splitting

- Status: queued
- Goal: Assign purchases to local people and share cent-exact results.
- Why: Splitting provides immediate value for scanning a receipt.
- Dependencies: T05
- Implementation scope: Implement a pure Swift money/split engine before wiring its UI. Support one-person item ownership and equally shared items, explicit allocation policies for receipt discounts/taxes/deposits/adjustments and deterministic largest-remainder rounding with stable tie-breaking. Use tax markers when available; expose a documented fallback when applicability is unknown. Require complete assignments and resolution of unexplained receipt discrepancies before finalized output. Persist participant assignments and generate a human-readable copy/share summary. Recompute when receipt data changes. Quantity splitting is optional and must not delay the basic workflow.
- Acceptance criteria: Every finalized split exactly matches the receipt total, assignments and fallback policies are visible, invalid inputs cannot silently finalize, and shared summaries contain the chosen amounts/items without requiring participant accounts.
- Tests: Odd cents, three people, shared and individual items, taxable/non-taxable lines, discounts/coupons, deposits/tips, negative adjustments, zero-value bases, repeated deterministic output, overflow/bounds and sum invariants.
- Risk/notes: No model-generated arithmetic, settlement/payment integration or collaborative accounts. Clipboard/share is explicit user action; no participant data in telemetry.
- Chat: 01a117d0-d507-7bf0-a9cc-c6f6724d16a0 (local; queued)

## T07 — 07 · Purchase history and local search

- Status: queued
- Goal: Find an old item or merchant and reopen its original receipt.
- Why: Search supplies the long-term purchase-memory value and completes the first imported-image demo.
- Dependencies: T04, T05
- Implementation scope: Implement efficient chronological history and local full-text search over merchant, raw description, corrected/normalized description and SKU where available. Integrate month grouping and merchant filters from the chosen wallet design. Search should support supported multilingual text and common abbreviations without embeddings. Keep indexing consistent on save/edit/delete. Open a result to its receipt/item and original evidence. Review complete imported-image demo including splits once T06 is done and record remaining issues before physical-camera testing.
- Acceptance criteria: Saved purchases are findable by merchant/item; corrections are reflected; deleted records disappear; 500 synthetic receipts remain practical to browse/search; original evidence is reachable from results.
- Tests: Search create/edit/delete consistency, merchant/raw/normalized/SKU coverage, supported multilingual examples, restart and a 500-receipt performance/usability sample.
- Risk/notes: No semantic search, AI chat, cloud backend or mandatory multiple wallets. Camera testing is the next phase after the simulator demo, not part of this task.
- Chat: 01a117d0-ee31-7363-9ee0-f0b9986d83f2 (local; queued)
