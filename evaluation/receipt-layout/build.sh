#!/bin/sh
set -eu
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
sliplet_layout_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$sliplet_layout_root"
# The production file is untouched. Change one call in a temporary evaluation
# copy so every variant uses the identical financial/retailer parser.
python3 - <<'PY'
from pathlib import Path
source = Path('Sliplet/Parsing/Parsing.swift').read_text()
assert source.count('for row in rows(observations) {') == 1
assert 'static let maximumAssetBytes = 32 * 1024 * 1024' in Path('Sliplet/Persistence/ReceiptStore.swift').read_text()
Path('/tmp/Sliplet-P2-02-Parsing.swift').write_text(source.replace('for row in rows(observations) {', 'for row in LayoutExperiment.rows(observations) {'))
PY
exec "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" \
  -parse-as-library -sdk "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
  -target arm64-apple-macos27.0 -o /tmp/Sliplet-P2-02-worker \
  evaluation/receipt-layout/Worker.swift evaluation/receipt-layout/LayoutExperiment.swift \
  Sliplet/Domain/Receipt.swift Sliplet/Domain/ReceiptReview.swift Sliplet/Domain/ReceiptSplit.swift \
  /tmp/Sliplet-P2-02-Parsing.swift Sliplet/Recognition/ReceiptImage.swift \
  Sliplet/Recognition/VisionTextRecognizer.swift Sliplet/Domain/RecognizedText.swift
