# Product and accepted decisions

Approved on 2026-10-07, America/Toronto.

## Hypothesis
People will voluntarily scan another receipt when capture/extraction is quick, corrections are easy, and splitting plus purchase search provides enough value.

## Accepted direction
- iOS only; native Swift and SwiftUI.
- Initial retailers: No Frills, Costco and T&T. Accuracy claims require real receipts.
- Build on the Mac and iPhone simulator first, using imported images. Physical iPhone 15 Pro camera work follows the finalized simulator test version.
- Minimalist native iOS 27 appearance with subtle depth. User selected **Paper lift** on 2026-10-07: a receipt pulls from the wallet with a slight fold/tilt. Use restrained shadows to make the wallet, slips and opened receipt layers clear; do not commit to multiple wallets.
- Use native Liquid Glass for appropriate navigation and controls, including the bottom bar and buttons. Prefer system SwiftUI components/material behaviour, with accessibility settings respected; keep receipt text on a legible solid content surface. Browser concepts approximate the layout and motion, not the native material interaction.
- All stores use the same simplified digital receipt layout, with predictable merchant/date, items, discounts, tax and total sections. Preserve the original receipt separately and make it easy to open for verification; do not reproduce each retailer's paper format in the main detail view.
- Local-first, offline core workflow; no mandatory account, backend or cloud AI.
- T03 selected Apple Vision plus deterministic receipt parsing for the manual-review demo. Five human-verified receipts support this pilot choice: 57/66 exact purchase amounts, but only 2/5 totals and no fully reconciled receipts without correction. Require source review/correction and deterministic reconciliation; retain local Foundation Models variants as evaluation-only. See [recognition decision](adr/002-receipt-recognition.md). All benchmark execution stayed on the Mac; phone behavior remains unverified.

## First usable demo
Import -> extract -> review/correct -> save -> reopen -> assign items to local people -> exact split -> copy/share summary -> search an old item -> find original evidence.

The app must retain a manual-review path if recognition or on-device AI is unavailable. Expose missing/uncertain data. Do not finalize a split with unexplained receipt discrepancies or unassigned items.

## Data integrity and privacy
Money uses integer minor units. Financial calculations are deterministic. Preserve original receipt evidence and raw extraction separately from user edits. Verify actual local storage protections and key management. No sensitive contents in logs, analytics, crash breadcrumbs or public fixtures. Support receipt deletion and asset cleanup. Explicitly document backup behaviour. No claim of E2EE.

## Deferred
Camera until the simulator version is ready; accounts/cloud sync; warranty/tax/rebate/insurance features; bank/email integrations; subscriptions; semantic search; AI chat; live collaborative splitting.

## Pending preferences and inputs
Exact phone iOS version before device testing. Five private HEIC receipt images and checked human references remain Git-ignored: two Costco, two No Frills and one T&T. T03 measured this small pilot; expanded retailer coverage and timed correction usability remain future validation. Simulator local Foundation Models generation and synthetic Vision OCR were verified in T01. Image-assisted model extraction was tested on the Mac; Apple's OCRTool is unavailable in Simulator. Phone performance and production storage protections remain unverified.
