# RcpLens

An iOS-only personal purchase memory app. Import a receipt, correct it quickly, save it, split items with other people and find purchases later.

Status: T01–T05 accepted. The native imported-image demo supports review, drafts, exact reconciliation, local saving, reopening and deletion. T06 item splitting is complete and verified; T07 purchase search still awaits approval. The home wallet now holds a chronological paper stack with in-place expansion, archive/star and configurable swipe actions. See [wallet design](docs/WALLET_DESIGN.md), [native redesign](docs/UI_REDESIGN.md), [demo verification](docs/IMPORT_DEMO.md), [MVP_PLAN.md](MVP_PLAN.md), [TASKS.md](TASKS.md), [PROGRESS.md](PROGRESS.md), and [docs/PRODUCT.md](docs/PRODUCT.md).

## Try the receipt demo on your Mac

Open `RcpLens.xcodeproj` in Xcode 27, select the shared **RcpLens** scheme and an iPhone simulator running iOS 27, then Run. Xcode 27 displays simulated devices in **Device Hub**.

Choose **Import → Photo library** to select a receipt image already added to Simulator Photos. With the simulator running, add a Finder image through Terminal (replace the example path):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun simctl addmedia booted "/absolute/path/to/receipt.heic"
```

You can drag the image from Finder into Terminal to insert its path. **Import → Files** also accepts images available inside the simulated device's Files browser.

Review merchant, date, currency, purchases, adjustments and totals. Tap Date to choose the printed purchase day in the native calendar; Cancel preserves the old value and Clear date keeps it unknown. Open **Original** to compare the source; fields can be edited and lines added or removed. **Save draft** keeps incomplete work as **Needs review**. **Finish** requires complete fields, exact reconciliation and your original-source confirmation. Both actions stay in the bottom bar. Saved receipts can be reopened and edited; **Receipt options → Delete receipt** removes them after confirmation. **All receipts** in the top bar opens month and store filters. The wallet pocket stays at the bottom. Swipe up to pull papers out and down to tuck them back in. Papers spread around the upper third and squeeze together near the wallet, moving at different speeds during the same swipe; scrolling content softens beneath the system controls at the top and bottom of the screen. Even a single paper stays partly tucked into the wallet. Receipts are oldest at the top and newest at the bottom, with newer paper in front and subtle alternating tilts. Pulling past the end rubber-bands the papers and wallet together. Tap a paper to expand it, then return to restore the stack and its original layer order. Swipe left for Archive or right for Star, then tap the revealed action. The bottom wallet has a scooped leather opening, stitching and layer shadows. Settings lets you change either swipe direction, open Archive or Starred, and choose **Receipt paper → Always white** or **Match appearance**. Paper defaults to matching Light/Dark Mode; the wallet and controls keep the system appearance. Unarchive restores a paper to its chronological position. The bottom bar has one labeled **Import receipt** action. Wallet information is available through the info control.

Open a saved receipt and tap **Split** to add people and assign every purchase to one owner or several equal owners. Review and accept each adjustment’s allocation policy; tax applicability needs either an explicitly source-confirmed scope or the visible all-purchases fallback. **Save choices** keeps unfinished work. **Finalize** requires a reviewed, reconciled receipt and complete assignments, then enables explicit **Copy summary** and native **Share summary**. Receipt edits invalidate finalization. See [exact splitting and verification](docs/SPLITTING.md).

Save before leaving the app: backgrounding discards unsaved work. Saved receipts remain on this device, excluded from ordinary backup, with no export/restore yet. Uninstalling the app or losing the device can lose them. Recognition uses local Vision and deterministic parsing; manual review is required. Apple Intelligence is not required for this workflow.

Debug also offers **Wallet information → Development → Synthetic diagnostics**, which tests a fictional PNG and a harmless local Foundation Models greeting. Release has no diagnostics or local test controls.

For command-line builds, select Xcode for this shell without changing the system default:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun simctl list devices available
xcodebuild -project RcpLens.xcodeproj -scheme RcpLens -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/RcpLens-T05-DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build
xcodebuild -project RcpLens.xcodeproj -scheme RcpLens -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/RcpLens-T05-DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test
```

Replace the simulator ID when using another Mac. The current deployment target is iOS 27.0; physical-device signing and testing are deferred. No external dependencies, account or cloud provider is required.

Use local ad-hoc signing for Simulator Keychain access; no Apple account is required for these simulator checks. Xcode 27 displays simulated devices in Device Hub. Exact environment and foundation commands: [docs/FOUNDATION.md](docs/FOUNDATION.md). Current storage tests, fresh-process checks, protection limitations and integration API: [docs/STORAGE.md](docs/STORAGE.md).

## Source boundaries

One app target, one hosted XCTest target and a separately selected native UI-test target. `RcpLens/App` manages scene/protected-data lifecycle; `UI` contains the wallet, review, saved receipt and original-image screens; `Domain` holds exact-money, review and receipt/evidence models. `Recognition` accepts encoded image bytes and returns positioned Vision observations; `Parsing` produces a deterministic editable draft. `Persistence` implements transactional SQLite with encrypted receipt/image payloads and a Keychain key. `evaluation/receipt-eval` remains a separate Mac-only benchmark. `Diagnostics` is Debug-only, and `Resources` contains the public synthetic fixture.

Private receipt images and extracted personal data must not enter Git. Use the ignored `private-receipts/` folder for consented inputs and private verification logs/results. Synthetic diagnostics use fictional content. Explicit local Debug test launches can read consented private inputs from a separate simulator inbox; private workflow reports expose only aggregates. Release contains no test importer or checked-reference controls.

GitHub repository: [mobyyyc/RcpLens](https://github.com/mobyyyc/RcpLens). Local `main` tracks `origin/main`.
