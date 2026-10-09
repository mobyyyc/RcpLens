# Exact item splitting · T06

T06 adds local people and per-purchase ownership to a saved receipt. Open a receipt, tap **Split**, add names, then open each purchase to choose one owner or several equal owners. Every purchase, including a zero-value or returned purchase, needs an assignment. **Save choices** retains an unfinished plan. **Finalize** requires T05's source-reviewed, complete, reconciled receipt and a valid allocation policy for every adjustment. Drafts cannot finalize.

The user confirmed **Proportional to assigned purchases** as the default on 2026-10-08. Every adjustment has editable Proportional/Equal and All purchases/Selected purchases/Selected people choices. Adjustment choices require explicit confirmation; no missing policy silently takes the default.

## Allocation contract

- Money remains signed Int64 minor units in the receipt's exact currency/scale. No floating-point money or model arithmetic.
- Purchases with the same canonical owner set use cumulative equal apportionment in receipt order, with separate positive and negative running buckets. Each line adds its signed amount to its bucket, allocates the cumulative amount equally through the largest-remainder allocator, then subtracts the prior bucket allocation. Each line sums exactly and each owner receives a floor/ceil-equal line share. Repeated odd cents stay balanced rather than repeatedly favoring one person; the net owner-set totals differ by at most one minor unit because the positive/negative remainder prefixes cancel. Zero lines use the positive bucket. Separate sign buckets avoid unfair line shares when returns cross zero (for example, -1 then +2). Adjustment allocation remains signed-magnitude largest remainder. Names, participant display order, dictionary order and policy display order do not affect results.
- Proportional adjustments use **absolute gross allocated purchase shares**, before separate discounts, tax, deposits, tips or other adjustments. Returned purchases contribute their absolute value as a weight. Adjustments do not compound or modify later adjustment bases. This is an explicit sharing convention, not a calculation of statutory tax.
- All purchases + Proportional uses all purchase owners. All purchases + Equal includes **every participant**, even a person with no assigned purchase. Selected purchases + Equal uses just those purchases' owners. Selected people + Equal uses just the chosen people. Selected people + Proportional uses those people's gross purchase shares.
- Item coupons and deposits can be limited to the affected purchase owners or specific people. Tips and negative adjustments use the same explicit choices. The app never assumes a coupon's applicability from its label.
- A nonzero adjustment with zero proportional base fails visibly. Choose Equal deliberately to proceed. A zero adjustment can use a zero base and allocates zero. Empty or invalid selected scopes fail.
- Full-width UInt64 multiply/divide avoids intermediate amount-times-weight overflow; signed magnitude handles Int64.min. Weight sums and signed accumulations are checked. If an aggregate or intermediate signed accumulation is not representable, the split is rejected even if a different accumulation order might avoid overflow. Bounds: at most 100 people, 10,000 purchases and 10,000 adjustments; names at most 80 characters. The existing receipt-review gate additionally limits each entered amount to 100,000,000,000 minor units. Full signed Int64 extremes are tested at the allocator boundary; receipts beyond the review bound cannot finalize.
- Every finalized component sums to its receipt line; all participant totals must sum exactly to the receipt total. Complete assignments and valid currencies are required. Repeated computation uses stable IDs and receipt order.

## Tax applicability

The current parser does not provide a trustworthy retailer/jurisdiction mapping for tax markers. Raw retained markers are shown in item ownership and selected-purchase policy screens. **No marker text automatically means taxable or exempt.** To restrict a tax, open Original, choose the purchases/people whose applicability was checked, and explicitly attest that the scope was verified against the original. This keeps known taxable/non-taxable lines outside/inside the correct user-confirmed scope.

For unknown applicability, **All purchases** is a visible fallback. The user chooses Proportional or Equal and explicitly accepts that fallback for each tax. The human-readable summary says “Unknown tax applicability fallback”; selected tax scopes say “Source-confirmed scope”. An uncertain marker never authorizes a finalized restricted scope.

## Persistence and lifecycle

`ReceiptSplitPlan` is an optional, versioned member of the existing authenticated AES-GCM receipt document. Legacy encrypted documents missing the field decode nil; there is no new SQLite column/table or SQL schema migration. Historical v1→v2 SQLite migration remains intact. Version 1 plans reject unsupported versions/structurally invalid data; malformed authenticated plans fail closed when read. No names, assignments, policies or summaries enter plaintext SQLite fields or telemetry.

Writes use the existing SQLite transaction and revocable lifecycle permit, verify original asset integrity and compare both current receipt revision and prior plan UUID. New committed writes get a fresh plan token. Conflicts fail instead of overwriting another editor. Saving choices clears finalization; finalizing reruns the pure engine in the storage boundary and binds the plan to the current receipt revision. Purchase evidence, raw parser/OCR, correction history, timestamps and wallet organization remain separate.

Receipt edits preserve participant identities and assignments for surviving item IDs. Removed items/policies are pruned; new purchases remain unassigned. Every edit clears finalization, policy acceptance and tax-source confirmation. Results are recomputed from current receipt values; cached amounts are never persisted. Finalization must be repeated after receipt editing. Receipt deletion removes the plan with its owning encrypted document/assets. Background/protected-data loss clears split presentation and decrypted state through the existing session reset and revokes queued writes.

## Explicit sharing

A committed finalized plan has View summary, Copy summary and native Share summary controls. Local edits remove these controls until the new plan is finalized. The summary contains merchant/date/currency, exact receipt total, each person's total, item/adjustment shares, selected scope and policies. Negative totals remain negative. No account or payment/settlement record is created. Copy writes a local-only pasteboard item to prevent Universal Clipboard transfer; Share opens the native system sheet only after a tap. There is no automatic export, cloud routing or summary logging. The existing backup/device-loss limitations apply to assignment data too.

Native receipt paper and the wallet scene retain their accepted styling/animation. The editor uses system Form/navigation/sheets, native controls and the existing Glass prominent style with opaque/increased-contrast alternatives. Quantity sub-splitting, camera, search, accounts, cloud and payments remain outside T06.

## Verification

Focused fictional XCTest cases cover signed odd cents/three people, individual/shared/zero/return items, coupon scope, taxable/non-taxable source-confirmed scope, unknown fallback, proportional/equal adjustments, deposits/tips/negative adjustments, zero bases, deterministic reordered input, full Int64 extremes, invalid inputs and sum invariants. Isolated encrypted-store checks cover legacy decoding, restart, ciphertext absence of participant fields, receipt-edit rebasing/new items, deletion, stale plans/revisions, failed commit, permit revocation, malformed authenticated plan and workspace background clearing.

Use the existing Simulator with Xcode selected for the shell:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Sliplet.xcodeproj -scheme Sliplet -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/Sliplet-T06-DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test -only-testing:SlipletTests

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project Sliplet.xcodeproj -scheme T05Workflow -configuration Debug \
  -destination 'platform=iOS Simulator,id=50661E83-1F58-466B-99F0-9DC517D8EC82' \
  -derivedDataPath /tmp/Sliplet-T06-DerivedData -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- test \
  -only-testing:SlipletUITests/ReceiptSplitUITests
```

Native test launches use `--t05-synthetic-preview split` and the separate fictional preview store/keychain service. Resume relaunches retain only that test store. Normal Simulator receipts, including the ten DEMO samples, are not purged, replaced or opened by these checks. The final hosted unit result contains **73 passes, one existing physical-file-protection skip, and zero failures** (74 total). Its 15 split-engine cases and seven encrypted split-storage cases use fictional data. An independent main-chat comparison of the actual allocator against Python Fraction passed **40/40 cases**, including full signed Int64 extremes; this checks the allocator separately from whole-engine, UI and persistence coverage. Final native execution evidence and limits are recorded in [the validation summary](evidence/t06-splitting/validation-summary.json).

Final native split coverage comprises five passing flow/structural cases in UI14 and the passing focused contrast audit in UI17, with identical app sources across those runs. The native workflow exercises single/shared ownership, explicit unknown-tax acceptance, cent-exact finalization, explicit local Copy, the actual system Share sheet, process restart, receipt-edit invalidation and return to the retained wallet. Other cases cover original access/unsaved dismissal, dark appearance and true accessibility5 text with reduced motion and opaque/increased-contrast controls. Strict structural audits of the split, item-owner and adjustment-policy screens have zero waivers/findings.

The final contrast audit records six findings: three individually measured black labels (Save choices 20.01:1; Back in both editors 19.66:1); the exact disabled Finalize control (actual white/#8F8F92, 3.22:1, noninteractive/exempt); and two exact Form nodes crossing/below the bottom-toolbar edge (ownership footer and Adjustments header). Those occluded nodes are unmeasurable as readable text: their screenshot histogram values do **not** establish text contrast. The allowlist checks exact labels/identifiers and actual toolbar-relative frames. Unknown visible findings fail. No participant-name exemptions remain; existing wallet audit rules are unchanged.

Main chat also softened the full-width pocket backing with a 32-point clear-to-opaque upper feather while retaining solid lower occlusion and original front/back order. Three final-source wallet cases verify one/two/three-paper occlusion, chronological open/return and elastic scrolling. Their fresh fictional captures are in [the evidence index](evidence/t06-splitting/README.md). Ten unaffected native cases precede these final UI-only refinements. The combined coverage is 19 unique native cases; the evidence summary describes each run rather than presenting them as one all-green full-suite run.

The baseline 19-case bundle records nine actual invalid-frame warnings (six split cases, large-text review, wallet/detail/review/source/library audit, and native date review). UI14 records six, one per split case; the focused UI17 audit records one. Exact cases and messages are retained in the validation summary. Two hosted-unit QoS runtime warnings and the nonfatal Xcode diagnostics-collection warning are also recorded. All selected final assertions pass; physical-device accessibility/material certification remains pending.

Final Release build/ad-hoc signature and exclusion of Debug preview/test/sample hooks passed. The combined Release app was installed and normally launched, and all twelve encrypted normal-wallet receipt payloads match the before-test fingerprint. T07 is unstarted. Planned main-chat commit: `feat: add exact receipt splits and soften wallet shadows`; implementation chat does not commit/push or mark user acceptance.

Primary API references: [Swift UInt64 full-width arithmetic](https://developer.apple.com/documentation/swift/uint64), [native ShareLink](https://developer.apple.com/documentation/swiftui/sharelink), and [UIPasteboard options](https://developer.apple.com/documentation/uikit/uipasteboard). The installed Xcode 27 SDK compiled the implementation. Physical-device lock enforcement, device VoiceOver, receipt accuracy and jurisdictional tax correctness are not established by fictional Simulator tests.
