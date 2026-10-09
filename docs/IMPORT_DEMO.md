# T05 · Imported receipt demo

Native SwiftUI on iPhone 18 Pro Simulator, iOS 27, Xcode 27. The import/review/save implementation is accepted by the main chat, with classified native contrast diagnostics and verification limits described below. Git synchronization is recorded in the coordinator handoff.

## Try the app

1. Open the existing iPhone simulator / Device Hub and launch Sliplet. Tap Import, then Photo library or Files.
2. To add a private Mac image to Simulator Photos, use the installed toolchain explicitly. Type the command below through its final space, then drag the image from Finder into Terminal to insert its quoted path. Run it, then choose the image in Sliplet's photo picker. Device Hub drag behaviour is not assumed.

   ```sh
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl addmedia booted "/absolute/path/to/your/receipt.heic"
   ```

3. Read every item against Original. Pinch/double-tap or use the zoom buttons. A line's Source action highlights its linked OCR regions; Printed text offers an uncorrected text alternative. The entire source and all observations are retained.
4. Edit merchant, printed date (`YYYY-MM-DD`), currency, purchases, quantities and printed line amounts. Add/remove purchases or discounts, taxes, deposits, tips and other printed adjustments. Discounts use negative amounts. Quantities are optional positive decimals and never calculate a line extension.
5. **Save draft** keeps missing fields and mismatches, labelled **Needs review**. Malformed typed numbers/dates must be fixed or cleared first. Currency-unknown amounts retain their exact editable text; they do not become zero or acquire an assumed currency.
6. **Finish** requires merchant/date/currency, purchase descriptions/amounts, valid optional quantities, printed total, exact reconciliation and explicit review against the original. If no subtotal is printed, confirm that yourself; unknown/unreadable is not confirmed absence. Any edit clears source confirmation and requires reopening Original.
7. Reopen a slip or All receipts, tap Edit to append corrections, or Delete to remove the receipt, all revisions and original from this app. Ordinary production launches contain no seeded demo receipts.

Recognition uses the selected local Vision/deterministic route; model availability is not needed and no model/cloud fallback runs. Import cancellation saves nothing. Backgrounding or protected-data loss clears unsaved work and decrypted UI/image state; explicitly committed saves can survive and reappear after unlocking. A native opaque cover hides content on scene deactivation before app-switcher snapshots. Storage/key errors are visible and never silently reset the database.

## Source, corrections and arithmetic

The original encoded bytes, actual detected MIME type, uncorrected Vision observations/geometry and exact parser output remain separate from append-only correction revisions. The native system picker's `.current` representation mode avoids requesting conversion; Photos may still supply an edited/current representation instead of byte-identical camera-file metadata. Files imports and local corpus tests preserve byte-identical originals. No plaintext thumbnails or image caches are written by the app.

Money uses Int64 minor units with bounded exact parsing; quantities use coefficient/scale decimals. Grand total must equal all purchases plus signed printed adjustments. A printed subtotal may equal purchases, purchases plus separate discounts, or purchases plus all non-tax adjustments excluding tips. The matching variant is displayed during review and deterministically rechecked by `ReceiptCompletion`; no missing tax is calculated or discrepancy hidden. A layout outside these variants remains a draft until corrected/clarified rather than forcing a misclassified deposit. No splits, full-text index or camera are implemented in T05.

`reviewInput` is an optional field added to the encrypted Codable revision payload. It preserves incomplete editable text and subtotal absence confirmation. Existing v1/v2 documents without it decode as nil; SQL schema remains v2. New receipt creation writes the immutable original plus first correction and image in one transaction. Existing edits use optimistic revision IDs. A synchronously revocable permit serializes the final commit with lifecycle revocation: queued/revoked writes roll back, while a commit already inside the short commit section completes before revocation returns. Foreground opening waits for previous closure; stale task completions cannot repopulate the UI.

If a save commits but refreshing the wallet fails, its new or revised summary is immediately available in the in-memory wallet and the error says it was saved. If deletion commits but refresh fails, the selected evidence and summary are immediately removed.

All store data is local and excluded from ordinary backup. No export/restore exists. Uninstall/device loss may lose receipts. Payload encryption and actual simulator Keychain behavior are inherited from T04; physical lock enforcement and device file/journal protection remain the later phone phase. Releasing buffers/actors is a lifecycle measure, not a guarantee of physical memory zeroization or forensic erasure.

## Verification commands

Use per-command `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Simulator Keychain requires the existing ad-hoc signing settings/entitlements.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Sliplet.xcodeproj -scheme Sliplet -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/Sliplet-T05-Unit-DerivedData \
  -resultBundlePath /tmp/Sliplet-T05-unit-reviewed.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Sliplet.xcodeproj -scheme Sliplet -configuration Release \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/Sliplet-T05-Release-DerivedData \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- build

# These explicitly local private checks require the already-consented ignored corpus/reference files.
# prepare resets ONLY the dedicated T05 test inbox and T05WorkflowTestStore, never the production wallet.
python3 scripts/verify-t05.py prepare
python3 scripts/verify-t05.py private

# Use a disposable simulator for synthetic picker/audit tests; leave the user Photos library intact.
# Replace SYNTHETIC_SIMULATOR_UUID with its booted UUID. This needs no private corpus.
python3 scripts/verify-t05.py prepare-synthetic --simulator SYNTHETIC_SIMULATOR_UUID
# Generate a synthetic-only image with distinctive photo metadata, then load it before picker tests.
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/make-t05-photo.swift
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun simctl addmedia \
  SYNTHETIC_SIMULATOR_UUID docs/evidence/t05/synthetic-photo.jpg
python3 scripts/verify-t05.py synthetic --simulator SYNTHETIC_SIMULATOR_UUID
python3 scripts/verify-t05.py accessibility --simulator SYNTHETIC_SIMULATOR_UUID
# Fictional screenshots use a separate preview store and restore ordinary launch afterward.
python3 scripts/capture-t05.py --simulator SYNTHETIC_SIMULATOR_UUID
```

`T05Workflow` is a separate UI-test scheme. Private tests use a Debug-only local file boundary that calls the same production image validation/recognition/import path; reference-assisted corrections are supplied from a local ignored JSON file. This is distinct from native system Photos picker and manual field-control tests. All private XCTest logs, screenshots and xcresults stay in ignored `private-receipts/evaluation/t05/`; only allowlisted aggregate counts/statuses go into public evidence. Synthetic-only native visual previews use `--t05-synthetic-preview wallet|review|detail|source|library|empty` and a separate store. No private corpus, references or test importer compile into Release.

## Apple sources and installed API evidence

Current primary Apple pages checked; the installed iOS 27 SDK and successful builds verify the APIs used:

- [System Photos picker](https://developer.apple.com/documentation/photosui/phpickerviewcontroller) and [PHPickerConfiguration preferred asset representation](https://developer.apple.com/documentation/photosui/phpickerconfiguration/preferredassetrepresentationmode).
- [Liquid Glass custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views): native navigation/toolbars and supported `.glassProminent` buttons; solid reading surfaces.
- [Vision text requests](https://developer.apple.com/documentation/vision/vnrecognizetextrequest): accurate recognition, locally supported English/French/Chinese languages and cancellable requests.
- [Protecting application files](https://developer.apple.com/documentation/uikit/encrypting-your-app-s-files) and [scene deactivation](https://developer.apple.com/documentation/uikit/uiscene/willdeactivatenotification): store release/protected-data availability plus explicit scene privacy cover.

## Verified results and limits

- **Release:** the coordinator independently rebuilt the final app, verified its deep/strict ad-hoc signature and absence of compiled Debug/test controls, and confirmed all 26 snapshot source hashes match. See [root-release.json](evidence/t05/root-release.json). That verified Release app is installed and normally launched on the original simulator.
- **Unit suite:** 43 passed, 0 failed, 1 physical-device protection skip (44 total). Final result bundle: `/tmp/Sliplet-T05-unit-reviewed.xcresult`; public aggregate: [unit-tests.json](evidence/t05/unit-tests.json). The save-refresh regression also checks immediate reopen and revised-summary visibility before retry.
- **Five consented originals:** all five passed import → draft → process restart → reference-assisted correction → source check → save/restart/verify → delete. All five preserved exact supplied bytes and original parser fields, and matched independently human-checked merchant/date, line kinds/descriptions/amounts, subtotal and total. The private verifier does not separately score corrected quantities or currency; exact typed quantity/currency behaviour has unit coverage. Two passed the completion gate; three remained Needs review because reference fields/arithmetic were unresolved. This is a round-trip/correction test, not fresh extraction accuracy or a timed human correction study. Public counts: [private-workflow.json](evidence/t05/private-workflow.json). The dedicated test database has zero receipts and assets after deletion ([deletion.json](evidence/t05/deletion.json)).
- **Ordinary native picker:** two synthetic UI tests passed, including the actual system picker, expected uncorrected synthetic OCR identity, merchant replacement through the keyboard, source viewing, malformed-input recovery, cancellation and Home/background clearing. The test selects a dated individual image, never an arbitrary stock photo or its containing grid. Public aggregate: [synthetic-ui-tests.json](evidence/t05/synthetic-ui-tests.json).
- **Accessibility:** three final native tests passed structure/description/hit-region audits across wallet, detail, review, source and library, plus large-text/reduced-motion/opaque/increased-contrast tap paths. The contrast audit retains **14 narrowly classified findings**, with **0 unclassified findings**: ten reading-text samples and two native Glass action labels measure 20.47–20.82:1 against their captured backgrounds; one is the intentionally disabled Finish button (white on grey, 3.23:1); one is a native list row partly beneath the floating toolbar. Initial actual heading contrast of 3.29:1 was corrected using concrete semantic label colours. The handler accepts only these specific fixture labels/control states/frame overlaps, and verifies black glyph-interior contrast ≥7:1 for the reading/action exceptions; unexpected or insufficient-contrast findings fail the test. Auditor inconsistency for the measured reading text is an inference from the screenshots, not a claim of complete accessibility certification. Dominant-background/glyph-interior sampling excludes antialias edges and does not cover every native Glass state or device setting. See [accessibility.json](evidence/t05/accessibility.json), per-element labels/roles/frames/reasons/colours/ratios in [contrast-diagnostics.json](evidence/t05/contrast-diagnostics.json), a fictional [flagged example](evidence/t05/contrast-diagnostic-example.png), and the coordinator's independent [measured example](evidence/t05/root-contrast-example.json).
- **Scene privacy:** the unit test verifies an opaque cover installed synchronously on native scene deactivation. The synthetic Home test records content-free deactivation/cover counters and confirms unsaved UI is cleared on return ([scene-privacy.json](evidence/t05/scene-privacy.json)). UIKit app-switcher snapshot pixels were not directly inspected, and this is not physical-device lock evidence.
- **Prominent Import button:** the final focused regression passes in light and dark themes, with measured glyph-interior contrast of 19.42:1 and 19.95:1. The final three-test accessibility run repeats this regression against matching current sources. See [prominent-button.json](evidence/t05/prominent-button.json).
- **Native screenshots:** labelled fictional [wallet](evidence/t05/native-wallet.png), [review](evidence/t05/native-review.png), [detail](evidence/t05/native-detail.png), [linked original](evidence/t05/native-source.png), [500-record library](evidence/t05/native-library.png), [dark wallet](evidence/t05/native-dark-wallet.png), [large text review](evidence/t05/native-large-text.png), [dark empty wallet](evidence/t05/native-empty.png), and [light empty wallet](evidence/t05/native-light-empty.png). The 500-record case verifies listing, filtering structure and absence of a plaintext thumbnail cache; it does not establish performance for 500 large real images.

The previously accepted [T03 benchmark](OCR_EVALUATION.md) remains the raw-accuracy baseline: 57/66 exact purchase amounts, 2/5 totals, zero fully reconciled originals. T05 has not replaced those figures with an iOS raw-accuracy score. The passing private round-trip run is `private-receipts/evaluation/t05/20261007-193228`; it predates final focus/picker/presentation/cache refinements and did not capture a source-hash manifest. Later UI runs capture per-run `source-hashes.json`; final artifact paths and current app source hashes are indexed in [validation-summary.json](evidence/t05/validation-summary.json). The final cache upsert was covered by the unit regression rather than repeating the private corpus. The latest unit suite precedes the final cosmetic heading/button-colour changes. The two-test native photo/edit workflow run precedes only the final prominent-button foreground and synthetic fixture changes; those changes are covered by the focused light/dark contrast regression, the final accessibility run and Release build.

Physical file/Keychain lock enforcement, device VoiceOver and a timed human correction study remain unverified. Simulator presentation flags exercise the same custom reduce-motion/transparency/contrast branches and large Dynamic Type without changing the user's system preferences; they do not establish the system's own Liquid Glass accessibility behavior. The temporary synthetic simulator is removed after verification; the user's simulator is returned to an ordinary launch. No Photos reset or deletion is performed on the original simulator. The main chat owns acceptance, the signed commit and GitHub push.
