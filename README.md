# RcpLens

An iOS-only personal purchase memory app. Import a receipt, correct it quickly, save it, split items with other people and find purchases later.

Status: T01 foundation verified on the iOS 27 simulator. Receipt workflows are still planned. See [MVP_PLAN.md](MVP_PLAN.md), [TASKS.md](TASKS.md), [PROGRESS.md](PROGRESS.md), and [docs/PRODUCT.md](docs/PRODUCT.md).

## Run the foundation

Open `RcpLens.xcodeproj` in Xcode 27, select the shared **RcpLens** scheme and an iPhone running iOS 27, then Run. In Debug, open **Synthetic diagnostics** and tap **Run synthetic checks**. It tests a bundled fictional PNG through Vision and asks the local Foundation Models model for a harmless greeting. Release has no diagnostics screen.

For command-line builds, select Xcode for this shell without changing the system default:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl list devices available
xcodebuild -project RcpLens.xcodeproj -scheme RcpLens -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/RcpLens-T01-DerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RcpLens.xcodeproj -scheme RcpLens -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/RcpLens-T01-DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
```

Replace the simulator ID when using another Mac. The current deployment target is iOS 27.0; physical-device signing and testing are deferred. No external dependencies, account or cloud provider is required.

Exact environment, launch/evidence commands, actual results and limitations: [docs/FOUNDATION.md](docs/FOUNDATION.md).

## Source boundaries

One app target and one hosted XCTest target. `RcpLens/App` contains the entry point; `UI` contains SwiftUI screens; `Domain` holds source-recognition types; `Recognition` accepts encoded image bytes and returns Vision text. `Parsing` and `Persistence` reserve the next tasks' boundaries. `Diagnostics` is Debug-only, and `Resources` contains the public synthetic fixture. No production parser or receipt database exists yet.

Private receipt images and extracted personal data must not enter Git. Use the ignored `private-receipts/` folder for future consented inputs. Diagnostics never accept private images or write OCR/model contents to logs or reports.

GitHub repository: [mobyyyc/RcpLens](https://github.com/mobyyyc/RcpLens). Local `main` tracks `origin/main`.
