# P2-03 retailer parsing accuracy

2026-10-09, America/Toronto. Approved in Main after P2-01 (`52fff21`) and P2-02 (`1e5680b`) acceptance. Implementation and local verification are complete and independently accepted in Main. No commit/push or subsequent-task dispatch in this chat.

## Result and limits

On the same five exposed development purchases, merchant and date matches improve from **3/5 to 5/5**, printed totals from **2/5 to 3/5**, and the correction-operation proxy from **20 to 14**. Exact purchase amount recovery remains **57/66** and all-kind line amounts **61/73**. All-line omissions remain **12**, extras decrease **1 to 0**, and wrong matched purchase amounts remain zero. None of the receipts fully reconciles. This is a limited field/interpretation improvement, not a purchase-recovery improvement or v0.2 release-gate pass.

There are **zero held-out purchases**. All five were previously exposed, and no labels were edited. Generalization, quantity/unit accuracy, actual editing seconds and phone latency remain unmeasured. Extra/omission counts match printed descriptions and are proxies, not independently adjudicated invented/absent products. Matching a total never confirms the purchases.

## Production rules

- Extract the supported brand from unpriced header evidence before the first monetary row; preserve fictional/demo identities. No Frills named headers normalize to NOFRILLS and T&T to T&T SUPERMARKET. A priced product containing the retailer name remains a purchase. Unknown retailers retain conservative generic line/field parsing and visible missing merchant/currency.
- No Frills three-short-number transaction dates use YY/MM/DD only when a printed clock or format marker accompanies the row. Invalid year-first readings fall back to valid ordinary numeric dates. Bare competing short-date readings and conflicting dates stay unknown with linked source issues. Other numeric date ordering remains explicitly flagged; invalid civil dates remain absent. These two exposed No Frills examples do not establish every branch/location's timestamp convention.
- Keep the existing accurate text OCR and 0.45-height grouping. Only a separate single printed amount and an unpriced, nonnumeric-leading description/summary can join: complete geometry, right-side price, offset at most one smaller text height, no intervening row, mutual nearest match and a 0.25-height ambiguity margin. Priced rows, rate/quantity rows, header/payment metadata and competing neighbors are excluded. Numeric-leading detached rows retain uncertainty rather than guessing between SKU/quantity/promotion codes. This removes the T&T extra/total defect without the P2-02 No Frills regression.
- Preserve numeric/SKU-bearing priced descriptions. Exact X/KG/LB operator/unit boundaries prevent SKU or product prefixes such as XTRA/XMAS from being mistaken for quantities. A unit price never fills a missing extension. Multiple monetary tokens need explicit quantity/rate syntax and a consistent printed extension. Exact integer rational half-up cents are used only to check that printed extension; missing prices are never calculated into a receipt. Pending rate evidence needs an immediately neighboring lower geometric purchase plus a matching printed extension; unrelated, geometryless or intervened rate rows remain flagged. Positive discount signs remain unchanged and uncertain; tax/deposit/negative discount values retain printed integer cents.
- Classify decorated printed subtotal/total labels. Repeated identical printed totals remain candidates; contradictions or multiple amounts invalidate the field and retain source issues. Tender, change, balances and savings never substitute for a printed total. An unpriced header word TOTAL does not prematurely terminate purchases. Unpriced/wrapped description rows remain source-linked for review; no speculative concatenation is promoted without enough evidence. Wrapped-row recovery is still incomplete.

Every raw OCR observation, ID, confidence and source coordinate remains unchanged and separately retained. Both baseline grouping and interpretation membership conserve every ID once, and all parsed/issue provenance points to that raw evidence. Original photos remain full-frame. Explicit currency uncertainty, mandatory source review, manual edits/Save draft, exact domain/reconciliation/splitting and installed storage identities remain intact. No UI redesign, Foundation Models/cloud inference or Apple Intelligence dependency; the user's China-market iPhone 15 Pro remains the required personal target.

## Same-observation and same-image results

The frozen-before parser is the accepted `1e5680b` parser, replayed against the accepted first-pass production OCR. Frozen-after uses exactly those same observations. Ten fresh after requests use the same five original images, twice. All 20 requests succeed. Before full output equals accepted P2-01 on 5/5; after frozen/fresh full output equals on 5/5; all five full repeat pairs agree, retaining currency and numeric quantities. Fresh text/confidence/geometry equals accepted OCR on 5/5 after removing generated source IDs. There is no recognition-setting/image-treatment change.

| Field/line measure | Before | After frozen and fresh |
| --- | ---: | ---: |
| Merchant / 5 | 3 | 5 |
| Date / 5 | 3 | 5 |
| Known subtotal / 4 | 4 | 4 |
| Printed total / 5 | 2 | 3 |
| Exact purchase amounts / 66 | 57 | 57 |
| Exact all-kind line amounts / 73 | 61 | 61 |
| Purchase omissions / extras | 9 / 1 | 9 / 0 |
| All-kind omissions / extras | 12 / 1 | 12 / 0 |
| Wrong matched purchase amounts | 0 | 0 |
| Correction-operation proxy | 20 | 14 |
| Fully reconciled / 5 | 0 | 0 |

| Store (purchase count) | Exact purchases | Exact all-kind amounts | Merchant/date | Known subtotal; total | All-kind omissions/extras | Correction proxy |
| --- | --- | --- | --- | --- | --- | --- |
| Costco (2) | 34/37 → 34/37 | 38/44 → 38/44 | 2/2; 2/2 unchanged | 2/2; 0/2 unchanged | 6/0 → 6/0 | 8 → 8 |
| No Frills (2) | 21/26 → 21/26 | 21/26 → 21/26 | each 0/2 → 2/2 | 2/2; 2/2 unchanged | 5/0 → 5/0 | 9 → 5 |
| T&T (1) | 2/3 → 2/3 | 2/3 → 2/3 | 1/1; 1/1 unchanged | subtotal unknown/unscored; total 0/1 → 1/1 | 1/1 → 1/0 | 3 → 1 |

Purchase omissions remain Costco 3, No Frills 5, T&T 1; purchase extra proxies improve T&T 1→0, other stores stay zero. Zero wrong matched purchase amounts in each store. There is no measured retailer accuracy regression on this development set. Costco's missed purchases/discounts and printed totals, No Frills detached numeric rows, and the remaining T&T purchase are unresolved; SKU removal, payment-total substitution and broad association are not justified by these results. The proposed 95% purchase recovery / held-out correction-burden gate is not achieved.

## Validation, timing and preservation

**60 native unit tests pass, zero failures/skips:** 22 new fictional retailer parser cases, 21 existing workflow cases, 15 exact split cases and two domain cases. New cases cover supported header normalization/demo identity, priced brand/SKU/unit-word prefixes, ambiguous/invalid dates, unknown retailer/currency, repeated/wrapped rows, explicit rate versus printed extension, weighted rounding, quantity boundaries/geometry, detached/competing prices, discounts/tax/deposit, contradictory/multi-amount/decorated totals, and mandatory manual source review. Tests run on a disposable Simulator; normal installed phone/Simulator data was not opened or replaced.

Eight new evaluator privacy/conservation checks, 12 audit checks, 14 layout checks and 14 historical evaluation checks pass (**48 Python checks**). Before/after Mac workers build. Simulator Debug app/test build and unsigned physical iOS SDK Release build pass. Read-only final capture verification passes source/binary/provenance/checked-label/repeat/preservation gates. Physical SDK compilation is not a phone installation or device-performance test. A pre-existing nonfatal child diagnostic utility lookup warning occurs after native tests; the actual xcresult confirms 60 passes and zero failures/skips.

Frozen parser-stage median is **9.4 ms before / 36.6 ms after**; the added interpretation/ambiguity checks cost about 27 ms on this Mac sample. Fresh after first-pass process-wall median is **269 ms**, maximum **24,256 ms**. The large initial Costco outlier is in Vision OCR (**24,180 ms**, parsing **37 ms**); its same-input repeat is **264 ms** wall. Other first passes are 253–296 ms. The outlier's cause is not established. Capture later overlapped briefly with physical build/xcresult work; framework caches and host contention were not controlled. These timings include process startup/serialization and separate row-membership recording. They do not prove an acceptable physical-phone latency budget, absence of a performance regression, or human review speed. The outlier and additional parser cost are retained rather than hidden by averaging/replacement.

The unchanged accepted archives, P2-01/P2-02 evidence, originals, checked labels and signing-project file pass before/after fingerprints. Main's pre-task source snapshot confirms the parser is the sole changed pre-existing app/test source and the exact Personal Team signing diff is unchanged. Bundle `com.mobyyyc.RcpLens`, Keychain/storage identifiers, installed app data and original files are preserved. The isolated test Simulator is removed after validation; no normal app installation was performed.

Private captures/labels/provenance stay ignored under `private-receipts/evaluation/p2-03-final/`. [Safe aggregate and final source hashes](evidence/p2-03/aggregate.json), [exact validation commands and limitations](evidence/p2-03/validation.json), [reproduction protocol](../evaluation/receipt-parsing/README.md). Main independently passed 11 final fictional checks, rescored every variant/store without the evaluation scorer, checked final source/signing conservation, and passed protocol/evidence verification. Main acceptance is recorded in [independent review](evidence/p2-03/main-chat-review.json). Signed commit/push remain Main-owned. No commit/push, new chats/agents, outgoing messages or P2-04/P2-05 implementation. Next proposed milestone is P2-04 only after Main acceptance and separate user approval.
