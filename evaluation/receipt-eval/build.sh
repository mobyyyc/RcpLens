#!/bin/sh
set -eu
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
sliplet_eval_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc" \
  -parse-as-library -sdk "$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" \
  -target arm64-apple-macos27.0 -o /tmp/Sliplet-T03-worker "$sliplet_eval_dir/Worker.swift"
