# P2-02 capture and document layout

2026-10-09, America/Toronto. Approved in Main after P2-01 acceptance (`52fff21`). Evaluation complete and independently accepted in Main. **Keep current production recognition unchanged:** none of the tested alternatives improved purchase recovery without a retailer regression. This is a completed negative experiment, not an accuracy improvement or a release gate pass.

## Evidence-based scope

The accepted audit found six association suspects with descriptions in grouped OCR and matching amounts elsewhere. Private raw geometry confirms several No Frills/T&T description/price pairs lie about 0.5–1.0 of the smaller text height apart; current grouping uses 0.45. Repeated/unit prices and existing grouping can still make a geometrically nearby value the wrong extension. That supports measured row/price experiments, not indiscriminate image treatment. No human-rated crop, glare, clipping or perspective defect has been established; no preprocessing was selected. Original encoded images remain full-frame and untouched, including their EXIF orientation. No silent trimming or replacement of originals.

Compared unchanged accurate text OCR/grouping, detached-price association, stricter raw column association, document lines, native table rows and document lines with detached-price association. The entire financial/retailer parser is identical across variants; only the evaluation copy's row-provider call changes. No P2-03 retailer rules, model/cloud inference, Apple Intelligence dependency or UI work.

The installed Xcode 27.0 (27A266a) macOS/iOS 27 SDKs expose `RecognizeDocumentsRequest` and `DocumentObservation` from iOS/macOS 26. Apple documents line/paragraph/table/list structure; API existence does not establish receipt accuracy. Checked the SDK declarations, compiled the Mac worker and typechecked the same evaluation files against the actual iPhoneOS 27 SDK. Document recognition selected supported `en-Latn-US`, `fr-Latn-FR`, `zh-Hans-CN`, `zh-Hant-TW`, disabled language correction/automatic language selection, retained one candidate and disabled barcodes. All recognition is local Vision. Primary sources: [request](https://developer.apple.com/documentation/vision/recognizedocumentsrequest), [document structure](https://developer.apple.com/documentation/vision/documentobservation), [normalized coordinates](https://developer.apple.com/documentation/vision/normalizedrect).

## Same-image results

Five exposed development purchases: two Costco, two No Frills, one T&T; 66 purchase lines and 73 all-kind lines. Zero held-out purchases. Checked labels pass schema, explicit human-check, ID, store and original-hash gates. First passes are scored; every variant was repeated once. All 30 full parsed repeat pairs agree, including currency/numeric quantities after removing generated IDs. Baseline matches accepted P2-01 full parsed output on 5/5 images.

| Variant | Exact purchases / 66 | Exact all-line amounts / 73 | Missing / extra purchase proxies | All-line omissions / extras | Printed totals / 5 | Correction-operation proxy |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Current text/grouping | **57** | **61** | **9 / 1** | **12 / 1** | 2 | **20** |
| Text + detached price | 57 | 61 | 9 / 1 | 12 / 1 | 3 | 19 |
| Text + raw columns | 57 | 61 | 9 / 3 | 12 / 3 | 3 | 21 |
| Document lines | 46 | 49 | 17 / 14 | 21 / 15 | 2 | 46 |
| Document native tables | 45 | 48 | 18 / 16 | 22 / 17 | 1 | 50 |
| Document + detached price | 46 | 49 | 17 / 13 | 21 / 14 | 3 | 44 |

Merchant/date remain 3/5 and subtotal 4/4 in every variant. No variant reconciles any receipt. Document variants contain three wrong matched purchase amounts; text variants contain zero. A better total alone does not establish correct purchases. Matching descriptions includes printed SKUs; a changed/combined description can create an omission plus an extra. Extras are not independently adjudicated invented products.

| Variant | Costco exact / 37; omissions/extras; correction proxy | No Frills exact / 26; omissions/extras; correction proxy | T&T exact / 3; omissions/extras; correction proxy |
| --- | --- | --- | --- |
| Current text/grouping | 34; 6/0; 8 | 21; 5/0; 9 | 2; 1/1; 3 |
| Text + detached price | 34; 6/0; 8 | 21; 5/1; 10 | 2; 1/0; 1 |
| Text + raw columns | 34; 6/0; 8 | 21; 5/3; 12 | 2; 1/0; 1 |
| Document lines | 29; 9/6; 20 | 16; 10/7; 21 | 1; 2/2; 5 |
| Document native tables | 29; 9/6; 20 | 15; 11/9; 25 | 1; 2/2; 5 |
| Document + detached price | 29; 9/6; 20 | 16; 10/7; 21 | 1; 2/1; 3 |

Per-store omissions/extras above cover all line kinds. Purchase-only denominators, omissions/extras, fields and stage timings are in [aggregate evidence](evidence/p2-02/aggregate.json). Correction proxies retain the accepted scoring policy and exclude quantity/unit edits; no human correction seconds were collected.

Document recognition returned five document observations. Native table cells resolved to known, unique line UUIDs on all images; **69 rows were actually applied on three images** (47 Costco rows across two images; 22 rows on one No Frills image). The other No Frills image and the T&T image had no native table rows and used line grouping. No real-image fallback was caused by missing/repeated IDs. Therefore table results reflect actual native rows where present, not an unreported adapter failure. Unknown IDs or spanning-cell duplication across rows trigger conservative fallback in fictional tests. Every captured raw observation is retained exactly once in grouped membership, with parsed/issue provenance pointing back to that source.

## Latency and source mapping

| Variant | All-image process wall median / max (ms) | Costco median / max | No Frills median / max | T&T single first-pass time |
| --- | ---: | ---: | ---: | ---: |
| Current text/grouping | 255 / 271 | 258 / 271 | 244 / 255 | 258 |
| Text + detached price | 247 / 280 | 261 / 280 | 253 / 259 | 234 |
| Text + raw columns | 636 / 679 | 674 / 679 | 546 / 636 | 280 |
| Document lines | 283 / 308 | 295 / 308 | 287 / 292 | 270 |
| Document native tables | 287 / 293 | 287 / 287 | 289 / 293 | 288 |
| Document + detached price | 294 / 326 | 299 / 304 | 307 / 326 | 273 |

Measured on arm64 macOS 27.0.1, standalone Mac frameworks, two inputs per first two stores and one T&T input. Framework caches were exercised; the final capture briefly overlapped fictional orientation/typecheck work. Wall time includes process startup, decode, recognition, parsing, serialization and **a second grouping calculation to record evidence**. The raw-column evaluator is especially affected; its median parser stage alone is 199 ms versus baseline 9 ms. These are descriptive evaluation timings, not controlled speed comparisons or production/phone latency. Stage medians are not additive. Phone latency, cold/warm behavior, cancellation timing and its budget remain unmeasured.

Both OCR routes consume the original raw raster with EXIF orientation passed once and no ROI transform. Document corners become bounding boxes in the same oriented normalized lower-left coordinate space used by current source highlights. No transformed source-coordinate mapping is needed. Sixteen fictional OCR requests cover all eight EXIF orientations, including mirrors/quarter turns; top/bottom text and all returned transcriptions/boxes match the upright reference within 0.015 normalized units, and original JPEG hashes remain unchanged. A 480-observation fictional tall-receipt replay retains first/last/all IDs. These are geometry/full-frame checks, not physical UI highlight or worst-case real long-receipt certification.

Mixed-language source observations and printed SKUs pass through grouping unchanged in supplied-observation tests. However the orientation fixture's embedded Chinese glyphs were **not** recovered by either OCR route, and fresh OCR on the five real images returned zero CJK characters. This corpus therefore does not establish Chinese OCR fidelity; no claim of mixed-language recognition improvement is made. Native document transcripts/geometry and all evidence are private, available for source review without changing labels.

## Verification and handoff

14 new layout/label/provenance/ambiguity/long-source checks, 12 audit checks and 14 historical evaluation checks passed. Standalone Mac build and physical iOS SDK typecheck passed. Read-only verification rescored all 60 captures and confirmed full parser repeats, table membership/fallback, source provenance, checked labels and before/after preservation fingerprints. All 33 production app sources match accepted HEAD; original bytes, checked references, accepted P2-01 evidence and the user's uncommitted signing-project hash remain unchanged. No app installation, receipt-store/Keychain access, bundle identifier change or draft/cancellation change. UI/app test runs were unnecessary for an evaluation-only change and would not prove phone accuracy.

Final private evidence: `private-receipts/evaluation/p2-02-final/`. Safe counters/source hashes: [aggregate](evidence/p2-02/aggregate.json); actual commands/limits: [validation](evidence/p2-02/validation.json); reproducible protocol and fallback rules: [harness](../evaluation/receipt-layout/README.md). No original paths/hashes, purchase descriptions/prices/dates, raw OCR or labels are published in public evidence.

Main independently passed the 14 layout checks and final read-only verification, then reproduced every variant and retailer count without importing the evaluation scorer. All 46 tracked app/test files and the exact local signing diff match the pre-task snapshot; public aggregate matches private final evidence and the captured worker/temporary parser hashes match. See [Main acceptance](evidence/p2-02/main-chat-review.json). Main owns signed commit/push and user communication. No commit/push or messages to other chats were made. P2-03 remains separately unapproved: the accepted audit's evidence-present retailer interpretation failures are still its next lead. Future work may collect checked unseen purchases and timed phone correction/latency; these are not required to finish this experiment and are not reported as passed. Keep the China-market iPhone 15 Pro without Apple Intelligence as the required personal-device target.
