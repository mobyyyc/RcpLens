# RcpLens

An iOS-only personal purchase memory app. Import a receipt, correct it quickly, save it, split items with other people and find purchases later.

Status: T01–T04 accepted: native foundation, Paper lift design, extraction evaluation and encrypted local storage. The visible app remains the foundation screen; T05 will integrate receipt import/review/save after user approval. See [MVP_PLAN.md](MVP_PLAN.md), [TASKS.md](TASKS.md), [PROGRESS.md](PROGRESS.md), and [docs/PRODUCT.md](docs/PRODUCT.md).

## Run the foundation

Open `RcpLens.xcodeproj` in Xcode 27, select the shared **RcpLens** scheme and an iPhone running iOS 27, then Run. In Debug, open **Synthetic diagnostics** and tap **Run synthetic checks**. It tests a bundled fictional PNG through Vision and asks the local Foundation Models model for a harmless greeting. Release has no diagnostics screen.

For command-line builds, select Xcode for this shell without changing the system default:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl list devices available
xcodebuild -project RcpLens.xcodeproj -scheme RcpLens -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/RcpLens-T04-DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
xcodebuild -project RcpLens.xcodeproj -scheme RcpLens -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/RcpLens-T04-DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Replace the simulator ID when using another Mac. The current deployment target is iOS 27.0; physical-device signing and testing are deferred. No external dependencies, account or cloud provider is required.

Use local ad-hoc signing for Simulator Keychain access; no Apple account is required for these simulator checks. Xcode 27 displays simulated devices in Device Hub. Exact environment and foundation commands: [docs/FOUNDATION.md](docs/FOUNDATION.md). Current storage tests, fresh-process checks, protection limitations and integration API: [docs/STORAGE.md](docs/STORAGE.md).

## Source boundaries

One app target and one hosted XCTest target. `RcpLens/App` contains the entry point; `UI` contains SwiftUI screens; `Domain` holds exact-money and receipt/evidence models; `Recognition` accepts encoded image bytes and returns Vision text. `Persistence` implements transactional SQLite with encrypted receipt/image payloads and a Keychain key. `Parsing` remains reserved for T05's production pipeline; `evaluation/receipt-eval` is a separate Mac-only benchmark. `Diagnostics` is Debug-only, and `Resources` contains the public synthetic fixture. The production store is not opened by the foundation UI.

Private receipt images and extracted personal data must not enter Git. Use the ignored `private-receipts/` folder for future consented inputs. Diagnostics never accept private images or write OCR/model contents to logs or reports.

GitHub repository: [mobyyyc/RcpLens](https://github.com/mobyyyc/RcpLens). Local `main` tracks `origin/main`.
