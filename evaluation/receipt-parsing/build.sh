#!/bin/sh
set -eu
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
sliplet_parser_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$sliplet_parser_root"
python3 -c 'from pathlib import Path; assert "static let maximumAssetBytes = 32 * 1024 * 1024" in Path("Sliplet/Persistence/ReceiptStore.swift").read_text()'
git show 1e5680b:Sliplet/Parsing/Parsing.swift > /tmp/Sliplet-P2-03-before-Parsing.swift
cat >> /tmp/Sliplet-P2-03-before-Parsing.swift <<'SWIFT'
// Evaluation metadata only: old parser uses its unchanged grouped rows.
extension ReceiptParser {
    static func interpretationRows(_ input: [Row], knownRetailer: Bool) -> [Row] { input }
}
SWIFT
for sliplet_parser_mode in before after; do
  if [ "$sliplet_parser_mode" = before ]; then
    sliplet_parser_file=/tmp/Sliplet-P2-03-before-Parsing.swift
  else
    sliplet_parser_file=Sliplet/Parsing/Parsing.swift
  fi
  "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" \
    -parse-as-library -sdk "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
    -target arm64-apple-macos27.0 -o "/tmp/Sliplet-P2-03-$sliplet_parser_mode-worker" \
    evaluation/receipt-parsing/Worker.swift Sliplet/Domain/Receipt.swift \
    Sliplet/Domain/ReceiptReview.swift Sliplet/Domain/ReceiptSplit.swift \
    "$sliplet_parser_file" Sliplet/Recognition/ReceiptImage.swift \
    Sliplet/Recognition/VisionTextRecognizer.swift Sliplet/Domain/RecognizedText.swift
done
