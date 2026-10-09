# P2-01 private production baseline

This isolated Mac worker compiles the **unchanged production Swift files** listed in `build.sh`. It calls `ReceiptImage.decode`, `ReceiptRecognitionJob.run` and `ReceiptParser.parse`. It does not launch/install the app, open a receipt store or Keychain, use Foundation Models, change recognition settings, or contact a service. The only shim is the store's 32 MiB import limit, checked against production by the build script. Mac framework execution is local; these results do not measure the iPhone implementation's speed or image capture.

Run from `/Users/moby/Desktop/cs/Sliplet`:

```sh
sh evaluation/receipt-audit/build.sh
python3 -m unittest discover -s evaluation/receipt-audit -p 'test_*.py' -v
python3 -m unittest discover -s evaluation/receipt-eval/tests -v
python3 evaluation/receipt-audit/audit.py --run private-receipts/evaluation/new-p2-01-run
python3 evaluation/receipt-audit/verify.py --run private-receipts/evaluation/new-p2-01-run
```

Always use a new output directory. Never invoke `Worker.swift`'s binary on a real receipt directly in a terminal: stdout contains private OCR and parser output. The Python runner captures both streams, discards framework stderr, suppresses private exceptions, and prints only status/counts. Its default inputs are the archived `real-final` run and human-verified `real-v1/ground-truth.json`. Original files are resolved by SHA-256 among direct private-root images, so the old RcpLens absolute paths need no edits. Existing images, labels and archived evaluation files are never rewritten.

Three distinct comparisons are saved: historical Python parsing/scoring of frozen OCR; current Swift parsing of that OCR; and current production Vision plus Swift parsing of original images twice. Frozen Vision geometry is clamped exactly as the current recognizer clamps coordinates at the unit boundary; untouched archived observations remain the authoritative original evidence. Two archived observations have negative origins; the first incomplete baseline run exposed the need for this adapter and is retained privately. The completed `p2-01-baseline-v2` calibration predates final runner changes; **`p2-01-final` is the review baseline**.

Outputs remain Git-ignored under the private run: `manifest.json` contains source/original/archive/signing hashes; `corpus.json` groups original photos by purchase; `frozen-swift/` and `current/` contain separate responses; `scores/` contains original references, exact amounts and indexed failure suspects; `review.html` is a read-only local original/reference/OCR/parser comparison. This page contains no scripts or remote resources. Do not preview, print or copy its contents into chat or public evidence. `aggregate.json` contains only reviewed count/timing/environment/source fields suitable for aggregate documentation; it has no receipt paths, original hashes, amounts, purchase dates, descriptions, participants or labels.

The independent `verify.py` command performs no inference or writes. It validates current source hashes, untouched originals/archive/signing project, purchase splits, all five captured scores, failure-index evidence, repeat comparisons and published aggregate counters. It also checks the historical published pilot counts. Hash checks intentionally fail if recognition/parser/audit sources change after capture; use a new run after such changes.

Amounts compare exact integer cents with kind plus case/whitespace-normalized printed descriptions. Missing lines remain in the denominator, duplicate purchases are consumed once, and identical prices cannot establish purchase identity. All-line omissions/extras and purchase-only omissions/extras are separate. Extra lines are proxies requiring human adjudication. Unknown fields are unscored. Swift correction proxies exclude quantities because the original labels retain printed quantity strings and Swift retains numeric decimals; do not interpret the adapter as full quantity/unit validation or actual editing effort. Historical scoring retains the original quantity policy to reproduce the T03 number.

Automated failure categories locate the checked description and amount in grouped/raw OCR: both in a row suggests interpretation or description matching; description in a row with amount elsewhere suggests association; incomplete token evidence leaves capture/OCR/transcription unresolved. Repeated prices, unit prices and description changes can mislead these categories. They neither establish photo quality nor prove correct description/amount pairing. Merchant-header checks only report whether the checked brand is contained in an incorrect returned full header. Human adjudication of originals, timed phone correction and actual phone latency remain pending. See [audit report](../../docs/RECOGNITION_AUDIT.md).
