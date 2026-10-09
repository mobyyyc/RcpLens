#!/bin/sh
set -eu
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
sliplet_audit_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$sliplet_audit_root"
# Keep the sole storage shim in lockstep with production's import limit.
python3 -c 'from pathlib import Path; assert "static let maximumAssetBytes = 32 * 1024 * 1024" in Path("Sliplet/Persistence/ReceiptStore.swift").read_text()'
exec "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" \
  -parse-as-library -sdk "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
  -target arm64-apple-macos27.0 -o /tmp/Sliplet-P2-01-worker \
  evaluation/receipt-audit/Worker.swift Sliplet/Domain/Receipt.swift \
  Sliplet/Domain/ReceiptReview.swift Sliplet/Domain/ReceiptSplit.swift \
  Sliplet/Parsing/Parsing.swift Sliplet/Recognition/ReceiptImage.swift \
  Sliplet/Recognition/VisionTextRecognizer.swift Sliplet/Domain/RecognizedText.swift
