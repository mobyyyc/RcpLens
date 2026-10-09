# P2-02 capture/document-layout comparison

Standalone local Mac evaluation; no app install, store/Keychain access, Foundation Models, cloud calls or production-source edits. All five checked purchases are exposed development data. Recognition timing here is **Mac evaluator timing**, not iPhone latency or human correction seconds.

## Reproduce

From `/Users/moby/Desktop/cs/Sliplet`, with full Xcode:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
sh evaluation/receipt-layout/build.sh
python3 -m unittest discover -s evaluation/receipt-layout -p 'test_*.py' -v
python3 evaluation/receipt-layout/compare.py --run private-receipts/evaluation/new-p2-02-run
python3 evaluation/receipt-layout/verify.py --run private-receipts/evaluation/new-p2-02-run
```

Use a new output directory. The final captured candidate is `private-receipts/evaluation/p2-02-final`; `p2-02-experiment-v1` is initial calibration with earlier sources and an uncontrolled first-process outlier. Never invoke the worker on real images directly in a terminal. Its stdout includes private OCR, document structures and parser output. The Python runner captures stdout/stderr, suppresses private exceptions and prints counts/status only.

Default inputs are the accepted P2-01 corpus, `real-final/manifest.json` and `real-v1/ground-truth.json`. A custom `--labels` file must be private and pass the same schema, human-review, verification-check, receipt-ID and original-hash gates, plus matching store/group hashes. The actual selected label path and hash are retained in the private manifest; labels are never published. All original bytes, checked references, accepted baseline files, app/evaluation sources and the user's signing project are fingerprinted before and after capture.

`build.sh` creates a temporary copy of `Parsing.swift` in `/tmp` and replaces exactly one call (`rows(observations)` → `LayoutExperiment.rows(observations)`). The original app file is untouched. Consequently all six variants share the exact same current retailer/financial parsing rules and exact integer money behavior. The temporary adapter and compiled worker hashes are in the private manifest. Store-size shim is checked against production. Native document structures stay encoded in the private responses; raw line IDs/coordinates are never rewritten by association experiments.

## Variants

- `baseline`: unchanged production `VNRecognizeTextRequest`, accurate/no language correction, then current row grouping.
- `text-association`: baseline OCR/grouping; only detached price-only rows may attach to a description with no amount. Horizontal separation, at most one smaller text height of vertical offset, mutual nearest matching and a 0.25-height ambiguity margin are required. Ambiguous pairs remain in the baseline rows.
- `text-column-association`: examine all price-only observations, including prices already grouped with text. Match stripped description rows by the same geometry/uniqueness rules. Unmatched prices retain their original row; conflicting multiple prices cause whole-image fallback. This candidate is slower and adds extra-line proxies on the sample.
- `document-lines`: `RecognizeDocumentsRequest(.revision1)` and current grouping of `document.text.lines`.
- `document-tables`: native table-row cell membership, including non-table text through baseline grouping. Each original document line must belong to exactly one output row. Unknown or repeated cross-row cell UUIDs cause baseline line-grouping fallback; no tables means line grouping. Cells spanning rows are deliberately conservative.
- `document-association`: document lines plus the detached-price association rule.

Document options select the installed SDK's supported English/French/simplified/traditional Chinese languages, disable correction and automatic language selection, retain one candidate and disable barcodes. Same originals, full frame, orientation passed once; no crop/resize/perspective/tiling. No parser/model-calculated totals, retailer-specific rules or automatic completion are introduced.

Six variants × five originals × two passes = 60 captured successful requests. First passes are scored; second passes verify **full parsed equality**, including currency and numeric quantities, excluding generated line/evidence UUIDs only. Baseline is also compared against P2-01 by that full comparison. Scoring continues the accepted amount/field/description policy; it does not score numeric quantities, SKU correctness or actual correction effort. Independent read-only verification reconstructs scores, repeat comparisons, provenance/membership, table fallback and preservation hashes. Missing/extra counts remain proxies.

Every response contains raw observations, all native document structures, final row-ID memberships, parsed provenance and stage/wall timings. Raw observation IDs must be unique; final row membership must retain every ID exactly once; all parsed/issue provenance must point to raw observations. Bounds are checked within oriented normalized source coordinates. Private failures cannot be copied to public reports.

## Fictional orientation check

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift \
  evaluation/receipt-layout/OrientationFixture.swift /tmp/Sliplet-P2-02-orientations
python3 evaluation/receipt-layout/orientation.py \
  --folder /tmp/Sliplet-P2-02-orientations --report /tmp/Sliplet-P2-02-orientation.json
```

Eight fictional JPEGs contain inverse-transformed raw pixels with all EXIF orientations. Both OCR routes must retain top/bottom text and return the same transcription/normalized boxes within 0.015 of the upright reference; original bytes must remain unchanged. This is a geometry/full-frame smoke check, not proof of recognition quality or physical-device UI highlights. These fictional images did **not** recover the embedded Chinese glyphs. Unicode/SKU preservation through grouping is checked separately with supplied fictional observations. The five-real-image OCR captures contain no CJK characters, so mixed-language recognition quality remains unmeasured.

## Timing limits and decision

Each request runs in a separate process; capture order rotates by purchase. Frameworks were already exercised. The final run overlapped briefly with the fictional orientation check and iOS typecheck; no cold-device or controlled resource-isolation claim is made. Process-wall includes startup, JSON encoding and a second row computation to capture group evidence; stage medians are not additive. This particularly inflates the column experiment's wall time. No result proves faster production behavior.

All alternatives failed the no-regression/purchase-recovery gate. Production recognition, source highlighting, cancellation, original storage, drafts and money logic are unchanged. [Results and Main handoff](../../docs/CAPTURE_LAYOUT_EVALUATION.md).
