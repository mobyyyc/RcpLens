# Product and accepted decisions

Approved on 2026-10-07, America/Toronto.

## Hypothesis
People will voluntarily scan another receipt when capture/extraction is quick, corrections are easy, and splitting plus purchase search provides enough value.

## Accepted direction
- iOS only; native Swift and SwiftUI.
- Initial retailers: No Frills, Costco and T&T. Accuracy claims require real receipts.
- Build on the Mac and iPhone simulator first, using imported images. Physical iPhone 15 Pro camera work follows the finalized simulator test version.
- Wallet-inspired UI: receipt can pull out of a pocket. Detailed appearance and organization remain preferences to resolve with two concepts. Do not commit to multiple wallets.
- Local-first, offline core workflow; no mandatory account, backend or cloud AI.
- Evaluate Apple Vision and Foundation Models with deterministic receipt parsing, and verify APIs against the installed SDK.

## First usable demo
Import -> extract -> review/correct -> save -> reopen -> assign items to local people -> exact split -> copy/share summary -> search an old item -> find original evidence.

The app must retain a manual-review path if recognition or on-device AI is unavailable. Expose missing/uncertain data. Do not finalize a split with unexplained receipt discrepancies or unassigned items.

## Data integrity and privacy
Money uses integer minor units. Financial calculations are deterministic. Preserve original receipt evidence and raw extraction separately from user edits. Verify actual local storage protections and key management. No sensitive contents in logs, analytics, crash breadcrumbs or public fixtures. Support receipt deletion and asset cleanup. Explicitly document backup behaviour. No claim of E2EE.

## Deferred
Camera until the simulator version is ready; accounts/cloud sync; warranty/tax/rebate/insurance features; bank/email integrations; subscriptions; semantic search; AI chat; live collaborative splitting.

## Pending preferences and inputs
Wallet concept choice; private receipt corpus location/consent; exact phone iOS version before device testing. Mac Apple Intelligence readiness and simulator Foundation Models functionality are unverified.
