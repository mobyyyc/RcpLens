# Proposed next test version — Sliplet v0.2

Draft for user approval. Prepared 2026-10-09, America/Toronto. This is a roadmap proposal, not authorization to begin the next implementation task or upload receipts. The user confirmed entirely on-device recognition and a personal test build on 2026-10-09. P2-01 was separately approved and accepted; P2-02 was then separately approved, completed its experiments and independently accepted. P2-03 was separately approved and independently accepted. P2-04 and P2-05 still require task-specific approval.

## Current position

The user tested the app on an iPhone 15 Pro and reports that Face ID and the rest of the app work well, while receipt recognition is poor. This is valuable device feedback, not a formal measurement of recognition accuracy, performance or hardware file protection. Import/camera, review/drafts, encrypted saving, wallet/history/search, exact splits, archive/star, paper appearance and app lock are implemented. Keep the established interface stable except where correction usability requires a change.

The production app already uses Apple Vision (`VNRecognizeTextRequest`, accurate mode), followed by deterministic row grouping and receipt parsing. It currently passes the original decoded image to recognition, without a receipt-specific crop/perspective pipeline. It retains only the highest-ranked text candidate per observation, disables language correction, and selects supported English/French/simplified/traditional Chinese languages. These are candidates for measured experiments; they are not individually established causes of the user's poor results.

The earlier five-receipt Mac benchmark recovered 57/66 exact item amounts with Vision plus parsing, but only 2/5 totals, and no receipt reconciled without correction. Tested local model variants recovered 33/66 and 26/66 validated item amounts and took longer. This does not prove every AI approach is worse; it means replacing the parser with a model is not yet justified by our evidence. See [evaluation](OCR_EVALUATION.md) and [recognition decision](adr/002-receipt-recognition.md).

Apple Vision also offers document-structure recognition for lines, paragraphs, tables and lists. Evaluate this against the current approach rather than assuming it solves receipt interpretation. Apple Intelligence remains unavailable on supported devices purchased in mainland China, according to Apple's current guidance; the user's own phone must remain a first-class test device.

Sources: [Vision document recognition](https://developer.apple.com/documentation/vision/recognizedocumentsrequest), [Apple Intelligence availability](https://support.apple.com/en-us/121115).

## Version goal

Photograph a normal No Frills, Costco or T&T receipt, correct a small number of clearly identified issues, then save, split or find the purchase later. Success means less verified correction work on real receipts, not just nicer OCR text or a matching total.

## Proposed order

| Milestone | Concrete result | Completion evidence |
| --- | --- | --- |
| 1. Diagnose recognition | A private, reproducible failure report separating photo quality, text errors, row/column association and receipt interpretation. Start with the five checked references plus a few troublesome phone photos. | Per-store baseline for merchant/date/totals, purchase amount recovery, omissions/extra lines, correction time and phone latency. Preserve an untouched comparison set. |
| 2. Improve capture and layout | Better input through measured crop/perspective/quality experiments; compare current text OCR with Vision document structure. Keep original photos and correct evidence coordinates. | Same receipt photos scored before/after; preserve mixed-language text, prices and SKUs; no silent trimming of long receipts. Promote only improvements that reduce correction burden. |
| 3. Improve retailer parsing | No Frills, Costco and T&T rules for item/amount pairing, wrapped descriptions, quantities/weights, discounts, taxes, deposits and printed totals, with a conservative generic fallback. | An expanded checked corpus and unseen receipts; avoid improving one store at another's expense. Missing or ambiguous values remain visible, and models never calculate financial allocations. |
| 4. Make corrections faster | Compact issue-first review, convenient original-image comparison and focused edits/retries for uncertain rows. Preserve normal review and Save draft. | Timed phone walkthroughs: fewer edits and faster review, including long receipts and one deliberately bad image. Fully reconciled does not automatically mean fully accurate. |
| 5. Prepare the personal v0.2 build | Portable encrypted export/restore for receipts and originals, safe upgrades, offline/lifecycle checks and a repeatable release checklist. | Restore into an isolated test store, confirm original images and revisions, retain existing data across an upgrade, and complete repeated real shopping/import/review/search/split sessions on the iPhone. |

The first task, **Recognition failure audit and expanded baseline**, is accepted; see [measured audit](RECOGNITION_AUDIT.md). The approved P2-02 capture/document-layout experiments are complete and accepted: document/association alternatives did not pass the no-regression gate, so P2-02 promoted no production change. See [comparison and limits](CAPTURE_LAYOUT_EVALUATION.md). P2-03 is also accepted; the next proposed approval is P2-04 faster corrections. The user requested five corresponding Phase 2 chats on 2026-10-09; they are recorded in TASKS.md. Subsequent task details should use measured findings; do not dispatch all milestones at once.

## Measurement and release gates

- Begin with available receipts; expand toward about 30 distinct purchases, aiming for balanced coverage of the three stores. Phone photos and flat images of the same purchase belong to the same evaluation group, not independent samples.
- Keep a development set and an untouched validation set separated by receipt. Scoring uses checked original references; user corrections must not be treated as automatic ground truth without review.
- Proposed v0.2 targets: at least 95% exact purchase amount recovery, at least 90% merchant/date/printed-total accuracy, and median normal-receipt correction time under 30 seconds. These are goals to confirm after the baseline, not achieved results or accuracy guarantees. Report each store and difficult cases separately, with denominators and omissions/extra-line results.
- A release candidate must improve held-out correction burden without unacceptable latency or a regression in another store. Measure median and slow-case processing/review times on the actual iPhone; choose a phone latency budget after the baseline.
- Preserve deterministic money arithmetic, explicit source confirmation, missing-value handling and draft restrictions. No automatic receipt completion based only on model confidence or matching totals.
- Test upgrade preservation, successful/cancelled Face ID, passcode fallback, offline capture/import, background interruption, original-image access, long receipts, search and exact splits. The user's positive device report is a starting point for this checklist.
- Export/restore must be portable independently of the original device-bound storage key; copying the SQLite database alone is not sufficient. Scope restore to explicit user-selected files and transactional validation.

## Recognition options

Confirmed v0.2 scope: all recognition stays on-device and the next test build is for the user alone. Improve Vision and interpretation first. Compare modern document recognition and carefully chosen OCR/image options. Preserve a reliable fallback on the user's China-market iPhone.

Cloud assistance and cloud benchmarks are outside v0.2. Any future cloud evaluation requires a separate user decision and explicit approval of inputs. Apple Intelligence enhancement on eligible devices remains a measured optional branch; this version must work on the user’s own iPhone without Apple Intelligence.

## Beyond v0.2

Once real receipt data is dependable, build purchase memory: user-confirmed item aliases, past purchase lookup, same-item price history and repeat purchases. Price comparisons must respect package size, weight, quantity and currency; unknown quantities cannot support unit-price claims. Small spending summaries can follow accurate data.

Then consider a small trusted-tester release and feedback workflow. Multiple wallets, broad analytics, accounts/sync, subscriptions, AI chat and warranty integrations stay later proposals rather than immediate implementation tasks. Friends and TestFlight distribution are outside the next personal test version. Revisit distribution, onboarding and support after the user’s everyday accuracy goals are met.

## Working rhythm

Keep the user in this main chat. For each approved task, report the preceding task, current milestone, verification, actual commit message/hash and proposed next task, then ask for approval. The requested five Phase 2 chats exist; P2-01 is accepted, P2-02 is accepted, P2-03 is accepted, and the remaining two wait for separate task approvals. Creating these chats does not authorize implementation. Do not create additional chats unless explicitly requested.


## P2-03 implementation handoff · 2026-10-09

P2-01/P2-02 are accepted (`52fff21`, `1e5680b`); the user separately approved P2-03. The parser changes are implemented and locally verified, independently accepted in Main. On five exposed development purchases, merchant/date matches rise 3/5→5/5, totals 2/5→3/5 and correction proxy falls 20→14 without measured store accuracy regression. Exact purchases remain 57/66; omitted purchases and Costco totals are still unresolved. Sixty native checks, 48 evaluator checks, frozen/fresh comparison and unsigned iOS SDK Release build pass. [Full evidence and limits](RETAILER_PARSING_EVALUATION.md).

There are zero held-out purchases; quantity/unit accuracy, human correction time and phone latency remain unmeasured. The added parser work and a large initial Mac OCR timing outlier are explicitly recorded. The proposed release targets are not met or certified. Original/source conservation, mandatory review/drafts, exact cents/splits, signing/storage identities and entirely local recognition remain intact. P2-04 is the next proposal only after Main acceptance and separate user approval; no correction UI or personal-release work starts in P2-03.
