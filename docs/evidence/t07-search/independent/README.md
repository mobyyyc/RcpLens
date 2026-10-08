# Independent matcher verification

The main chat compiled the actual production Swift matcher against a separate, explicitly fictional fixture. All 30 checks pass. This checks current/source/SKU provenance, compact merchant plus item terms, Unicode, archive filtering, deterministic ordering, deletion, query bounds and avoiding cross-item matches. No normal records or images were decoded. The tiny OCRResult definition supplies the parsing type boundary; no OCR engine runs in this standalone check.

From the repository root:

```sh
mkdir -p /tmp/rcplens-t07-review
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swiftc -O \
  RcpLens/Domain/Receipt.swift RcpLens/Domain/ReceiptSplit.swift \
  RcpLens/Domain/ReceiptReview.swift RcpLens/Domain/ReceiptSearch.swift \
  RcpLens/Domain/RecognizedText.swift RcpLens/Parsing/Parsing.swift \
  docs/evidence/t07-search/independent/OCRType.swift \
  docs/evidence/t07-search/independent/main.swift \
  -o /tmp/rcplens-t07-review/search-oracle
/tmp/rcplens-t07-review/search-oracle
```

The executable writes its fictional case results to `/tmp/rcplens-t07-review/independent-search-results.json`. [Verified output and source fingerprint](results.json). Native flows, encrypted persistence and performance are covered by the separate XCTest evidence.
