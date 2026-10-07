# T03 local receipt evaluation

Isolated macOS 27 / arm64 harness. It does not change the iOS app. Everything that might contain a real receipt stays in the Git-ignored `private-receipts/` tree. `Worker.swift` is a private stdin/stdout protocol endpoint: **do not invoke it directly on real input in a terminal**. The Python runner captures stdout/stderr, writes evidence privately and prints only count/status metadata. No network/provider code, cloud routing or feedback submission exists.

## Run

From the repository root, with installed Xcode 27. No package installation required.

```sh
sh evaluation/receipt-eval/build.sh
python3 -m unittest discover -s evaluation/receipt-eval/tests -v
python3 evaluation/receipt-eval/runtime_checks.py

# Use a NEW private run directory. prepare rejects an existing manifest.
python3 evaluation/receipt-eval/evaluate.py prepare \
  --corpus private-receipts --run private-receipts/evaluation/my-real-run
python3 evaluation/receipt-eval/evaluate.py benchmark \
  --run private-receipts/evaluation/my-real-run --repeats 2

python3 evaluation/receipt-eval/evaluate.py prepare --synthetic \
  --run private-receipts/evaluation/my-synthetic-run
python3 evaluation/receipt-eval/evaluate.py benchmark \
  --run private-receipts/evaluation/my-synthetic-run --repeats 1 \
  --labels private-receipts/evaluation/my-synthetic-run/ground-truth.json
```

Run model benchmarks sequentially. The checked final real corpus uses two passes; the rendered synthetic corpus uses one model pass plus two OCR passes. Each request has a 90-second wall timeout. A fresh local session uses `SystemLanguageModel.default`, greedy sampling and a 4096-token output cap. The runtime supplies the context size; do not assume an older SDK's window. The text path reserves the full response budget and schema/instruction/prompt tokens, and rejects oversized input. The image tokenizer rejected attachments during calibration; the image path skips tokenizer preflight and records generation/context errors instead. Timeouts kill the worker process; late responses are never accepted.

A: accurate Vision OCR, no language correction, selected English/French/simplified/traditional Chinese languages if the installed revision supports them; geometry groups same-row observations; deterministic parsing. B: identical frozen OCR text interpreted by a guided local model. C: image attachment plus Apple's `OCRTool`, with the same explicit local model. C receives no A OCR in its prompt. All generated claims are conservatively checked against A's OCR afterwards. This shared check can reject a correct C-only reading; the private raw response/transcript is retained for review.

## Human reference labels

Open the run's `review.html` as a local file. It offers an unverified Vision draft, blank mode, labeled fields, an editable CAD line table, image zoom and original-file access. Check all merchant/date/subtotal/total fields, complete item coverage, printed extensions, quantities and adjustments against the original. Editing clears all confirmations. A matching total or model agreement is never verification.

Export `ground-truth.json` and save it **beside the page**, inside the private run directory. A browser may initially download it to Downloads; move it to the private directory rather than source control. The report requires `reviewed: true`, `verification_method: human_against_original`, all four verification checks, correct input SHA-256 and a valid schema. Drafts are ignored. Empty/missing fields are null, amounts are signed integer cents. Synthetic expectations are authored fictional goldens, not human-verified real evidence.

```sh
python3 evaluation/receipt-eval/evaluate.py report \
  --run private-receipts/evaluation/my-real-run \
  --labels private-receipts/evaluation/my-real-run/ground-truth.json
```

After code/validation changes, revalidate saved raw proposals without rerunning the model:

```sh
python3 evaluation/receipt-eval/revalidate.py \
  --run private-receipts/evaluation/my-real-run \
  --labels private-receipts/evaluation/my-real-run/ground-truth.json
```

This preserves old normalized output and applies the current deterministic checks to every approach/pass. It never overwrites raw OCR/model evidence or original images. The final source hash is recorded in the manifest and every normalized result.

The printed JSON is an explicit aggregate schema with no input names, digests, item text, prompts, participant identity, per-receipt results or monetary values. Do not print/cat private files. Only reviewed aggregate JSON is suitable for copying into `docs/evidence/t03/`.

## Evidence and scoring

`manifest.json`: private input filenames and hashes; `ocr/`: raw observations, geometry and stable grouped-row IDs; `raw-model/`: proposed output and transcript; `results/`: normalized output/provenance/warnings; `previews/`: local image derivatives; `ground-truth.json`: separate human labels; `aggregate.json`: shareable aggregates. Original images are retained untouched. There is no database/storage-security or backup claim; this is a local developer evaluation folder with restrictive newly-created file permissions.

Fields compare merchant case/whitespace, recognized date formats and exact subtotal/total cents. Missing values count as incorrect only when a non-null reference is known. Null reference fields/quantities are unscored unknowns, so proposed values do not count as corrections or unexpected fields. Confirmed absence requires a future explicit reference representation. Lines match by kind plus printed description with case/whitespace normalization, consuming duplicates individually and preferring equal amounts. Amount accuracy includes omissions in its denominator. Unmatched expected lines are omissions; unmatched proposed lines are extra-line proxies, not proof of hallucination (a differently transcribed description can produce both). Grounded normalized output is scored; raw source-rejected model line counts are reported separately. Human adjudication of actual invented content remains necessary.

Correction operations count field changes, missing/extra line operations, wrong matched amounts and quantity changes. This is a conservative machine proxy, not a timed usability measurement or a minimum edit distance. No correction seconds are fabricated; optional human timings remain private until aggregated. Reconciliation uses deterministic integer sums of printed line extensions, discounts, taxes and other adjustments. Subtotal is checked against non-tax lines; the assumed placement of adjustments is explicit and may not fit all receipt layouts. A matching sum is arithmetic consistency, not accuracy or permission to finalize a split.

Two passes compare normalized output, excluding timings. Successful pairs/equal successful outputs are separate from matching failure statuses and pairs with any failed pass; identical failures are never extraction-repeatability evidence. Golden text tests isolate parser logic; rendered-image goldens measure OCR plus parsing, including long, weighted/quantity, discount and mixed-language fixtures. No synthetic result establishes real-retailer support. Unknown retailers, date ambiguities, geometry mistakes, unclear extensions and unsupported AI remain manual-review cases. Never calculate allocations with model output.

## Optional review browser check

Uses only the fictional review page. With an existing local Playwright and Chrome installation, run `tests/review-browser.cjs` with `NODE_PATH` pointing to that Playwright package and `RCPLENS_BROWSER` pointing to the installed Chrome executable. No browser is downloaded. The check covers draft/blank mode, verification reset, export gating, invalid decimal rejection, integer-cent export and no page HTTP requests. It captures no screenshots or DOM contents. These dependencies are optional; the build/runtime/parser evaluation uses only installed Apple SDKs and Python's standard library.

## Checked pilot artifacts

`docs/OCR_EVALUATION.md` and ADR 002 record the five human-scored real receipts, the six synthetic images, raw factual scores separate from accepted source-grounded scores, failures and remaining limitations. The checked references are private at `private-receipts/evaluation/real-v1/ground-truth.json`; their IDs/hashes match the final results in `private-receipts/evaluation/real-final/`. Use the final directory, rather than the calibration runs, for the measured decision.

```sh
python3 evaluation/receipt-eval/revalidate.py --run private-receipts/evaluation/real-final \
  --labels private-receipts/evaluation/real-v1/ground-truth.json
python3 evaluation/receipt-eval/score_raw.py --run private-receipts/evaluation/real-final \
  --labels private-receipts/evaluation/real-v1/ground-truth.json
```

The second command is research-only: it measures raw copied values against checked references, including proposals that fail source binding. Its scores never authorize bypassing source validation in an app. Ordinary amount/correction metrics use exact printed description matching, so a changed abbreviation/name can create both a missing and extra-line proxy. Human correction seconds and adjudicated hallucination counts were not collected.

The model's asset revision is not pinned by this harness. Record its API identity, capabilities/context and OS/build; rerun after OS/model updates. Do not treat source hashes as model-weight/version hashes.
