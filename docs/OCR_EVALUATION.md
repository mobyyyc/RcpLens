# Receipt extraction evaluation

Date: 2026-10-07, America/Toronto. **Status: five-receipt pilot evaluated against independently human-verified labels; Vision plus deterministic parsing selected for the next manual-review demo.** No production app screens/storage were modified.

## Corpus and reference truth

Five consented HEIC receipts remain under Git-ignored `private-receipts/`. Both OCR coverage and the checked human references identify two Costco, two No Frills and one T&T receipt. This is below the 3–5-per-retailer seed target. Expand toward roughly 30 distinct receipts before a broader accuracy conclusion.

The separate fictional corpus contains six rendered images with known expectations: basic retail layouts, a discount, quantities/weighted goods, mixed Chinese/English text and a 140-item long receipt. Fixtures are explicitly synthetic. Parser-only text tests and rendered-image scoring are separate; clean fictional layouts do not establish real-store support.

The user checked and exported five independent human references against the originals. The labels contain 66 purchase lines and 73 lines including adjustments/taxes. Subtotal is known in four references; a null value is unscored unknown. Original input hashes were rechecked after labeling and still match the frozen evaluation. Reference truth covers merchant/date, complete purchases, printed extensions, quantities, discounts, taxes/adjustments, subtotal and total. The private page offers blank entry or an unverified Vision draft, CAD fields, an editable line table, zoom and original-image access. Every edit clears verification; all four explicit human checks plus an input hash/schema match are required before scoring. Pipeline agreement cannot mark labels verified.

Verified private labels: `/Users/moby/Desktop/cs/RcpLens/private-receipts/evaluation/real-v1/ground-truth.json`. These match the final run IDs/hashes and were scored against **real-final**, not the older calibration runs. Final review page (local only): `/Users/moby/Desktop/cs/RcpLens/private-receipts/evaluation/real-final/review.html`. Earlier review pages have the same receipt IDs/input hashes and can produce compatible labels. Export `ground-truth.json` and save it in the private run directory. Do not put it in Git or conversation previews. Unreadable/absent fields remain null; never fill unknown money by computing it.

## Comparison and environment

| Approach | Input and processing | Money/provenance boundary |
| --- | --- | --- |
| A | Accurate Vision OCR, same-row geometry grouping, deterministic parser | Printed decimals to integer cents; observation and row evidence retained |
| B | The identical frozen OCR text, explicitly local Foundation Models guided interpretation | Exact value/quote claims, validated against source rows before acceptance |
| C | Image attachment and Apple's OCRTool, explicitly local Foundation Models guided interpretation | Independent image/tool input; same conservative source check after generation |

The Mac worker uses `SystemLanguageModel.default` explicitly; no provider selection, network client, feedback upload, cloud/PCC routing or external inference exists. Runs execute on the Mac, not a cloud service or physical phone. Original images, raw OCR geometry, model responses/transcripts, normalized results and labels are distinct private files. The runner captures/discards framework stderr and prints only explicit aggregate/count/status metadata. Exception descriptions and associated values are never printed. New private artifacts use restrictive permissions; no broader storage encryption/backup guarantee is claimed.

Installed environment: Apple M5 Pro / 24 GiB, macOS 27.0.1 (26A434), Xcode 27.0 (27A266a), Mac SDK 27.0. Installed Mac and iOS 27 interfaces were checked for model capabilities, context/token counting, guided generation, image attachments and the Vision/Foundation Models cross-import OCRTool. Live local availability is `available`; guided generation, vision and tool calling report supported. English Canada, French Canada, simplified Chinese and traditional Chinese locale probes report supported. This is capability evidence, not measured multilingual receipt accuracy.

The **live model reports 8,192 context tokens**. Older primary context documentation describes smaller windows; use the actual runtime limit. Final configuration: fresh session per request, greedy sampling, 4096 maximum response tokens, 90-second wall timeout; two model passes on each real image, one model pass per synthetic image, two OCR passes per image. The text path counts prompt/instructions/schema and reserves output space; oversized source is rejected, never silently truncated. The installed image tokenizer rejected attachments during calibration, so image requests use the generation API's context-error handling instead. Framework/tool/internal context overhead can still cause generation failure. Timeout output is never accepted.

Apple documents OCRTool as unavailable in Simulator. It compiled and was exercised through a real Mac local-model image request, but no iPhone 15 Pro or simulator image-tool behavior is claimed. T05 should retain Vision/text/manual paths in the simulator.

## Human-scored real pilot results

First-pass results on the same five images, scored after final source validation. Repeated generation is recorded separately. Unknown reference values are excluded.

| Metric | A · Vision + parser | B · same OCR + local model | C · image + local model/OCRTool |
| --- | ---: | ---: | ---: |
| Merchant | 3/5 | 0/5 | 2/5 |
| Date | 3/5 | 3/5 | 3/5 |
| Subtotal | 4/4 | 4/4 | 1/4 |
| Total | 2/5 | 3/5 | 1/5 |
| Exact purchase amounts, including omissions | **57/66 (86.4%)** | 33/66 (50.0%) | 26/66 (39.4%) |
| Exact all-line amounts | 61/73 (83.6%) | 33/73 (45.2%) | 26/73 (35.6%) |
| Omitted lines / extra-line proxy | 12 / 1 | 40 / 12 | 47 / 1 |
| Correction-operation proxy | **20** | 61 | 60 |
| Reconciled without correction | **0/5** | **0/5** | **0/5** |
| First-pass end-to-end median | 225 ms | 67,629 ms | 78,441 ms |
| API-success attempts across both passes | 10/10 | 10/10 | 4/10 |
| Equal successful output / successful repeat pairs | 5/5 | 5/5 | 1/1 |
| Repeat pairs with any failed pass | 0/5 | 0/5 | 4/5 |

C's six failures were 90-second wall timeouts. Two pairs timed out on both passes; these are matching failures, not extraction repeatability. A includes a 23.85-second cold/setup outlier, so the 225 ms median is exploratory rather than a device-performance promise. Human correction seconds were **not measured**.

Source validation rejected 33 of B's 78 proposed lines and 18 of C's 45 proposed lines on the first pass. To distinguish source-binding problems from factual transcription, a separate research-only raw score compares copied values directly with the same human references. B recovered **41/66 (62.1%)** exact purchase amounts before source rejection, with 30 omissions and 35 extra-line proxies; C recovered **26/66 (39.4%)**, with 42 omissions and 14 extra-line proxies. Raw B total accuracy was 4/5, versus 3/5 after source validation; raw merchant accuracy was 1/5, versus 0/5 accepted. Raw outputs remain untrusted proposals, and these figures do not authorize bypassing source checks. Differently transcribed names can inflate omission/extra proxies, so none of these extra counts is proof of invented products.

**Pilot decision:** use Vision plus deterministic parsing as T05's initial recognition route, with original evidence, required corrections and deterministic reconciliation. A has the best item recovery, lowest correction proxy and much lower exploratory median latency in this sample. Keep B/C as isolated evaluation variants rather than automatic production extraction or cloud fallbacks. B's improved raw total accuracy is an interesting future suggestion path, but its weaker item coverage and latency do not justify automatic use in this pilot. The current A parser is also incomplete: only two raw totals matched and no full receipt reconciled. T05 must expose missing/uncertain data and require correction; no automatic completed receipt or final split is justified by this run.

The decision is limited to these five checked images and this exact parser/prompt/model/configuration. It does not claim robust real-retailer support, a calibrated confidence score, usability/correction time, statistically representative accuracy or iPhone performance. Expand the corpus and test correction usability before broadening it.

## Synthetic findings

The six known fictional images validate plumbing separately. A recovered 147/150 exact purchase amounts, with 3 omitted/2 extra-line proxies and 5/6 reconciled; all six merchant/date/subtotal/total fields matched. B recovered 5/150 accepted item amounts (three generation successes, two structured-operation failures, one timeout). C completed six API requests but recovered only 3/150 accepted item amounts. These strict-source/printed-description scores are synthetic-only, not estimates of store accuracy.

The 140-item fixture dominates the item denominator: A recovered 139/140 exact amounts, B timed out, and C returned successful structured output but recovered **0/140** expected items after validation, with most content omitted. Successful guided generation therefore cannot be treated as complete extraction. The 6000-row context probe was rejected during token preflight. No chunked receipt pipeline is implemented. Scenario metadata under `docs/evidence/t03/synthetic-scenarios.json` makes these long/discount/quantity/mixed-language cases reproducible.

## Metrics and limits

Only verified real labels (or authored synthetic expectations) enable accuracy metrics. Null reference fields/quantities mean unknown or unreadable and are excluded from accuracy, correction counts and unexpected-field claims; they do not mean confirmed absence. Pending real values are null, never zero or 100%. Fields: case/whitespace merchant equivalence, accepted date-format normalization, exact subtotal/total cents. Lines: kind plus printed description matching, consuming duplicate purchases separately. Item/line amount accuracy includes omitted expected lines in its denominator. Wrong names may appear as an omission plus an extra line; the aggregate extra-line count is an invention proxy that needs human adjudication. Raw model line proposals and source-rejected lines are reported separately from accepted normalized output.

Reconciliation is deterministic sum consistency for purchases, signed discounts, taxes, deposits and adjustments against printed total; it does not prove field/item correctness. Subtotal comparison assumes taxes are excluded and other adjustments included; layouts with different adjustment placement require explicit review. No model computes tax/discount allocations or financial splits.

Correction operations count field changes, omitted/extra line operations, incorrect matched amounts and quantity changes. This is a machine proxy, not a minimum-edit estimate or timed user study. Human correction seconds remain unmeasured unless explicitly supplied. Latencies include process startup; B includes the recorded shared OCR time and its model time, C includes tool/model time. A's setup timings include cold startup and possible setup contention; these exploratory timings are not a controlled device performance claim. Timeout values are censored at the configured limit. Repeatability reports successful pairs and equal successful output separately from same-failure statuses and pairs with a failed pass; two timeouts do not demonstrate extraction repeatability. Timings are excluded.

## Verification and evidence

- Golden text regression, malformed schema/claims, exact minor units, duplicate matching, geometry grouping, unavailable-output correction counting, line-extension validation and review-page escaping/export gates are covered by the isolated tests.
- Synthetic runtime checks exercise forced unavailable handling, malformed-image rejection and oversized-context rejection. An available model failing extraction is a failure, never relabeled as unavailable or skipped. All 14 regression tests pass; final unavailable/malformed/context runtime checks and the fictional local-browser review checks pass.
- Source grounding does not trust model-reported confidence. B/C claims must contain literal source quotes, numeric token matches and description/amount evidence on a common row; unit prices cannot replace line extensions.
- The private review page has no remote resources, storage or HTTP connections. Export is explicit human action.

Aggregate results and final check evidence are under `docs/evidence/t03/`; private raw evidence remains under `private-receipts/evaluation/`. Calibration runs are retained separately. The final model response budget was increased after shorter synthetic output worked but larger real structured output failed with the original 1500-token cap. Calibration failures are not conflated with final benchmark results.

## Reproduce and next decision

See [harness instructions](../evaluation/receipt-eval/README.md) for actual commands and metric definitions. Build with per-command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; no global toolchain changes or installations are required. Use a new private run directory, sequential model benchmarks and the same image/input hashes. Manifests/aggregate evidence record parser/prompt versions, source hashes and runtime configuration.

The human reference file is already available. Reproduce final scoring without running inference again:

```sh
python3 evaluation/receipt-eval/revalidate.py --run private-receipts/evaluation/real-final \
  --labels private-receipts/evaluation/real-v1/ground-truth.json
python3 evaluation/receipt-eval/score_raw.py --run private-receipts/evaluation/real-final \
  --labels private-receipts/evaluation/real-v1/ground-truth.json
```

Use the [OCR ADR](adr/002-receipt-recognition.md) for the measured pilot decision and fallbacks. Expand corpus coverage, measure actual correction usability and retest on device before broader claims. No mandatory accounts, automatic cloud inference or physical-camera implementation was introduced.

Primary Apple references checked alongside installed SDKs:

- [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels)
- [OCRTool](https://developer.apple.com/documentation/vision/ocrtool)
- [Generating content and performing tasks](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession)
- [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window)
- [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
