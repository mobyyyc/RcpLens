# T01 foundation verification

Verified 2026-10-07, America/Toronto. T01 is implemented and accepted after main-chat code, xcresult and screenshot review. This is an API/toolchain smoke check with fictional inputs, not a receipt-accuracy benchmark.

## Environment

| Component | Verified value |
| --- | --- |
| Mac | Apple M5 Pro, arm64, 24 GiB (25,769,803,776 bytes) |
| macOS | 27.0.1, build 26A434 |
| Xcode | `/Applications/Xcode.app`, 27.0, build 27A266a |
| Swift | Apple Swift 6.4, swiftlang-6.4.0.34.1, clang-2100.3.34.1 |
| iOS/iPhoneSimulator SDK | 27.0; simulator SDK build 24A430 |
| Installed simulator runtime | iOS 27.0, build 24A434 |
| Tested device | iPhone 18 Pro, arm64 |
| Simulator UUID | `50661E83-1F58-466B-99F0-9DC517D8EC82` |
| App bundle ID / deployment | `com.mobyyyc.RcpLens` / iOS 27.0 |
| Global developer directory | `/Library/Developer/CommandLineTools` |

All Xcode operations used `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; no global toolchain, Apple Intelligence, OS or signing settings changed. No software was installed. The existing Git history, MIT license, remotes and signing configuration were preserved. Temporary build output and test bundles are outside the checkout.

## Actual results

- Debug simulator build: **BUILD SUCCEEDED**; app installed and launched (initial PID 22191; final evidence launch PID 22361).
- Vision accepted the bundled 1000 × 600 synthetic PNG through `VisionTextRecognizer.recognize(imageData:)`. Five observations included the expected synthetic store marker, total marker and `12.34`. Vision can split one printed row into multiple observations.
- Simulator `SystemLanguageModel.default.availability`: **available**. An explicitly local `LanguageModelSession(model: model)` returned a nonempty **39-character** response to the fictional robot greeting prompt. The response was visible only in the debug screen; the JSON records its character count.
- Hosted XCTest target: **3 passed, 0 failed, 0 skipped**, 3.211 seconds in the XCTest suite; xcresult summary also reports Passed with no runtime warnings. Tests cover the real local-model/aggregate-report check, expected synthetic OCR text and malformed-image rejection.
- Release simulator build: **BUILD SUCCEEDED**. The diagnostics types, screen and auto-run launch path are inside `#if DEBUG` and excluded from Release compilation.
- Final diagnostics screenshot visually inspected: Vision passed; availability available; generation passed; response count 39.

Reviewable evidence: [aggregate diagnostics](evidence/t01/synthetic-diagnostics.json), [xcresult summary](evidence/t01/test-summary.json), [test suite excerpt](evidence/t01/test-results.txt), [diagnostics screenshot](evidence/t01/synthetic-checks.png), and [foundation screen](evidence/t01/foundation-screen.png). Screenshots contain synthetic/demo information only.

## Reproduce

Run from the repository root. The commands below use the same flags and paths as verification; invocations during execution used full Xcode executable paths in addition to the environment override.

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcode-select -p
xcodebuild -version
xcrun swift --version
xcrun simctl list runtimes
xcrun simctl list devices available

xcodebuild -project RcpLens.xcodeproj -scheme RcpLens -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/RcpLens-T01-DerivedData CODE_SIGNING_ALLOWED=NO build

# Boot only if this simulator is Shutdown. Calling boot on a booted device reports an error.
xcrun simctl boot 50661E83-1F58-466B-99F0-9DC517D8EC82
xcrun simctl bootstatus 50661E83-1F58-466B-99F0-9DC517D8EC82 -b
xcrun simctl install 50661E83-1F58-466B-99F0-9DC517D8EC82 \
  /tmp/RcpLens-T01-DerivedData/Build/Products/Debug-iphonesimulator/RcpLens.app
xcrun simctl launch 50661E83-1F58-466B-99F0-9DC517D8EC82 \
  com.mobyyyc.RcpLens --synthetic-diagnostics

# Use a new resultBundlePath on repeated runs: xcodebuild requires it not to exist.
xcodebuild -project RcpLens.xcodeproj -scheme RcpLens -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/RcpLens-T01-DerivedData \
  -resultBundlePath /tmp/RcpLens-T01-tests.xcresult -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO test
xcrun xcresulttool get test-results summary --path /tmp/RcpLens-T01-tests.xcresult

xcodebuild -project RcpLens.xcodeproj -scheme RcpLens -configuration Release \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/RcpLens-T01-DerivedData CODE_SIGNING_ALLOWED=NO build
```

For evidence, relaunch Debug after tests (the test runner replaces the foreground app), wait for the UI to show finished checks, then capture:

```sh
xcrun simctl launch 50661E83-1F58-466B-99F0-9DC517D8EC82 \
  com.mobyyyc.RcpLens --synthetic-diagnostics
xcrun simctl io 50661E83-1F58-466B-99F0-9DC517D8EC82 screenshot /tmp/RcpLens-checks.png
rcplens_container=$(xcrun simctl get_app_container \
  50661E83-1F58-466B-99F0-9DC517D8EC82 com.mobyyyc.RcpLens data)
cat "$rcplens_container/Library/Caches/synthetic-diagnostics.json"
```

Launch without the argument to see the foundation home screen. The committed PNG can be regenerated with `xcrun swift scripts/make-synthetic-fixture.swift` on macOS. This AppKit script writes only fictional fixture content, not app code or real data.

## API and privacy boundaries

The installed iOS 27 SDK's `FoundationModels.swiftinterface` confirmed `SystemLanguageModel.default`, availability reasons, `LanguageModelSession(model:)`, `respond(to:options:)` and `GenerationOptions(samplingMode:maximumResponseTokens:)`. We use `.greedy` and 48 maximum response tokens. No deprecated generation-error API is used. Model failures retain only NSError domain/code, never full error descriptions that could contain contents. Unavailable states distinguish `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`, and future unknown reasons. An available model that fails generation fails the model test; an unavailable model is explicitly skipped with its reason rather than presented as a generation pass.

`VNRecognizeTextRequest` uses accurate recognition, `en-US` and no language correction for this smoke check. Recognition runs behind an actor and does not persist or print text. The synthetic fixture is read as encoded PNG bytes from the bundle and passed through the same image-data boundary intended for later imported images. Photo-picker import and multilingual/retailer parsing remain T03/T05 work.

The debug report in app Caches contains only status strings, numeric counts, synthetic-text-match booleans and optional failure domain/codes. It contains no images, recognized strings, prompts, generated strings or private user input. The diagnostics harness has no private-image input path, network client or cloud routing. Release currently still bundles the harmless synthetic PNG, but no harness can execute. No storage encryption or backup guarantee is claimed by this scaffold.

Primary Apple references checked alongside the installed SDK:

- [Configuring command-line tools settings](https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings): a per-command `DEVELOPER_DIR` override can select Xcode without changing the system default.
- [Generating content and performing tasks with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models): availability checking and asynchronous session generation.
- [Recognizing text in images](https://developer.apple.com/documentation/vision/recognizing-text-in-images): Vision image/text-recognition boundary.

## Resolved failures and limitations

The first build failed because synchronized folder placeholders produced duplicate `.gitkeep` resource outputs. Replaced them with distinct comment-only Swift files reserving Parsing/Persistence; subsequent Debug/test/Release builds passed. Xcode emits an App Intents metadata warning because the app defines no App Intents. Simulator tests also printed system PointerUI/XPC startup messages; neither failed a test, and xcresult records no runtime warnings. A screenshot taken while the test runner was replacing the app showed an empty screen; it was replaced by the visually checked final app screenshot.

The Codex filesystem sandbox prevented cache writes and some simulator/host inspections. Scoped escalated commands succeeded; this was a sandbox constraint, not evidence of broken Apple services. No remaining permission is needed for this foundation handoff.

Only synthetic English text and a harmless local generation request were checked. No real receipt extraction accuracy, financial parsing, durable storage, wallet UX, photo permissions, offline stress test, device performance or iPhone 15 Pro support has been established. Physical-device deployment requires its actual OS version and signing configuration later. The current simulator result depends on this Mac's model availability and does not establish identical behaviour on another host or a physical phone.

## Handoff

T02 is the proposed next task, pending user approval in the main chat. T03/T04 can depend on this accepted scaffold. Main-chat task commit message: `feat: add verified SwiftUI foundation and local diagnostics`. The execution chat did not commit or push; the main chat handles Git synchronization after acceptance.
