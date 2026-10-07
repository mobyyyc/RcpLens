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
- Evaluate Apple Vision and Foundation Models with deterministic receipt parsing, and verify APIs against the installed SDK.

## First usable demo
Import -> extract -> review/correct -> save -> reopen -> assign items to local people -> exact split -> copy/share summary -> search an old item -> find original evidence.

The app must retain a manual-review path if recognition or on-device AI is unavailable. Expose missing/uncertain data. Do not finalize a split with unexplained receipt discrepancies or unassigned items.

## Data integrity and privacy
Money uses integer minor units. Financial calculations are deterministic. Preserve original receipt evidence and raw extraction separately from user edits. Verify actual local storage protections and key management. No sensitive contents in logs, analytics, crash breadcrumbs or public fixtures. Support receipt deletion and asset cleanup. Explicitly document backup behaviour. No claim of E2EE.

## Deferred
Camera until the simulator version is ready; accounts/cloud sync; warranty/tax/rebate/insurance features; bank/email integrations; subscriptions; semantic search; AI chat; live collaborative splitting.

## Pending preferences and inputs
Exact phone iOS version before device testing. Five private HEIC receipt images supplied in `private-receipts/` on 2026-10-07; exclusion from Git verified. Retailer coverage and independently verified ground truth remain to be checked in T03. Simulator local Foundation Models generation and synthetic Vision OCR were verified in T01; real-receipt accuracy and phone performance remain unverified.
