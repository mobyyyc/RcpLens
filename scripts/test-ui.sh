#!/bin/bash
# Run against one explicit Simulator and remove only its disposable XCTest runner.
set -euo pipefail
if [[ $# -lt 1 ]]; then
    echo "Usage: scripts/test-ui.sh SIMULATOR-UUID [xcodebuild test options]" >&2
    exit 2
fi
sliplet_simulator="$1"
shift
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
sliplet_project="$(cd "$(dirname "$0")/.." && pwd)"
cleanup() {
    # The Apple runner declares continuous background execution and depends on the
    # XCTest launch environment. Left installed, it can relaunch and crash later.
    xcrun simctl uninstall "$sliplet_simulator" com.mobyyyc.RcpLensUITests.xctrunner || echo "Runner cleanup failed; retry after booting this Simulator." >&2
}
trap cleanup EXIT
xcodebuild -project "$sliplet_project/Sliplet.xcodeproj" -scheme T05Workflow \
    -destination "platform=iOS Simulator,id=$sliplet_simulator" \
    -parallel-testing-enabled NO "$@" test
