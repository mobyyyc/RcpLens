# P2-03 local retailer parser comparison

This evaluator compiles the accepted `1e5680b` parser and the current production parser with the same current domain/recognizer files. The before parser has a metadata-only `interpretationRows` extension returning unchanged grouped rows; its `parse` implementation is untouched. Both workers use the storage-limit shim checked against production and never open a receipt store/Keychain or launch an app.

Use full Xcode from `/Users/moby/Desktop/cs/Sliplet`:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
sh evaluation/receipt-parsing/build.sh
python3 -m unittest discover -s evaluation/receipt-parsing -p 'test_*.py' -v
python3 evaluation/receipt-parsing/compare.py --run private-receipts/evaluation/new-p2-03-run
python3 evaluation/receipt-parsing/verify.py --run private-receipts/evaluation/new-p2-03-run
```

Always choose a new private output directory. Never run either worker directly on private inputs in a terminal: stdout contains receipt text and financial values. The runner captures both streams, suppresses private exception details and prints counters/status only. No network calls, cloud, language models or Apple Intelligence inference.

The accepted P2-01 corpus has five previously exposed development purchases (two Costco, two No Frills, one T&T), zero held-out purchases. Original checked labels are validated against accepted IDs/hashes/human-check/store/split gates and never modified. All derivatives of a purchase stay in its existing group. Default original inputs resolve through the accepted corpus; the old RcpLens cwd is not used.

For each purchase, replay exactly the same accepted first-pass observations into both parsers, then run current production Vision on the original twice. Twenty captured requests total. Baseline full parsed output must equal accepted P2-01 output; after frozen/fresh output and all fresh repeats must agree, excluding generated UUIDs only. Full comparisons retain currency, quantities and issues. Raw text/confidence/geometry equality with accepted OCR is reported separately for the fresh requests. Sources and checked labels/originals/accepted P2-01/P2-02/archive/signing-project files are fingerprinted before and after.

Every observation is retained exactly once in both grouped and interpretation membership. Parsed/issue provenance points only to retained source IDs, line provenance cannot duplicate an ID, and the mandatory source-review issue retains all raw IDs in order. Original observations, IDs and normalized geometry are untouched. The verifier is read-only: rescores saved responses, reconstructs aggregate/repeat/provenance checks, validates source/binary fingerprints and checks preservation. Main independently reviews final acceptance.

Amount scoring uses the accepted exact cents/kind/case-and-whitespace-normalized-description matching. Repeated purchases are consumed once; identical prices cannot prove identity. Missing lines stay in the denominator. Purchase/all-kind denominators and omission/extra/wrong-value counters are separate. Only known checked fields score. Quantity/unit accuracy and actual human correction time are unscored; the correction-operation proxy excludes quantity edits. Numeric/SKU-bearing descriptions are retained; no label edits or receipt-ID-specific rules.

Final private evidence is `private-receipts/evaluation/p2-03-final/`: captures, manifest, checked-score records and safe aggregate. Read-only verification prints no private paths/hashes/descriptions/amounts/dates. Published source hashes/counters and exact test/build commands are linked in [the task report](../../docs/RETAILER_PARSING_EVALUATION.md). Mac timing is descriptive: the initial fresh OCR request had a large slow outlier, its repeat did not; timing is not a physical-phone latency certification.
