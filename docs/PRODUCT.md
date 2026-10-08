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

The app must retain a manual-review path if recognition or on-device AI is unavailable. Expose missing/uncertain data. The user approved **Save draft** on 2026-10-07: incomplete or unreconciled receipts may be retained as clearly marked Needs review drafts; finishing requires explicit source review and matching totals. Field edits invalidate prior source confirmation. Draft saving does not authorize a finalized split. Do not finalize a split with unexplained receipt discrepancies or unassigned items.

## Data integrity and privacy
Money uses integer minor units. Financial calculations are deterministic. Preserve original receipt evidence and raw extraction separately from user edits. T04 stores original images and receipt documents (including correction revisions) as CryptoKit AES-256-GCM payloads inside transactional system SQLite, using a non-sync WhenUnlockedThisDeviceOnly Keychain key. SQLite structure, IDs and update metadata remain visible; this is not whole-database encryption. Simulator Keychain, authenticated encryption, rollback, migrations and deletion are verified; physical-device lock enforcement remains unverified. See [storage decision](adr/003-local-receipt-storage.md).

The store is excluded from ordinary system backup; no export/restore exists yet. Save and wallet screens explain local data-loss behavior. Missing/wrong-key stores fail visibly without reset. T05 integrates store closure/release and clearing decrypted presentation state on background/protected-data loss, reopening after unlock; explicit committed saves can survive lifecycle revocation. Scene privacy cover and state-clearing behavior are verified in Simulator, while physical lock enforcement remains unverified. No sensitive contents in logs, analytics, crash breadcrumbs or public fixtures. No claim of E2EE.

## Deferred
Camera until the simulator version is ready; accounts/cloud sync; warranty/tax/rebate/insurance features; bank/email integrations; subscriptions; semantic search; AI chat; live collaborative splitting.

## Pending preferences and inputs
Exact phone iOS version before device testing. Five private HEIC receipt images and checked human references remain Git-ignored: two Costco, two No Frills and one T&T. T03 measured this small pilot; T05 verified all five reference-assisted save/restart/correction/delete workflows, with two finished and three retained as unresolved drafts. This does not replace the raw-accuracy benchmark or measure human correction time. Expanded retailer coverage remains future validation. Simulator local Foundation Models generation and synthetic Vision OCR were verified in T01. Image-assisted model extraction was tested on the Mac; Apple's OCRTool is unavailable in Simulator. Phone performance, hardware file-protection enforcement, device VoiceOver and full native material contrast verification remain unverified. Simulator contrast findings have individually documented measured exceptions in the [demo report](IMPORT_DEMO.md).

## Native design correction · 2026-10-08

The user rejected the initial T05 empty-wallet presentation. The revision retains Paper lift while replacing duplicate import/Original actions and tab-like toolbar icons with one labeled Import action, explicit collection navigation, smaller layered artwork, stronger receipt hierarchy and compact review guidance. Storage limitations remain in Wallet information and the save/review flow. [Native audit and redesign](UI_REDESIGN.md). T06 still requires approval.

## Wallet interaction follow-up · 2026-10-08

The user requested the wallet at the top, oldest-to-newest vertical paper order, newest-first layering behind the wallet, paper previews with bottom fades for long content, and expansion within the same scene with surrounding papers leaving from their respective edges. Return restores the stack. Archive and star are now explicitly in scope: archive moves receipts into Archive; star preserves chronology. Swipes reveal configured actions for a tap; deletion always confirms. Left defaults to Archive and right to Star, with Archive/Star/Delete/None in Settings. See [wallet design](WALLET_DESIGN.md).


### Wallet pocket refinement · 2026-10-08

The user superseded the top wallet crown: keep the pocket at the bottom while the chronological papers slide out on an upward swipe and slide back in on a downward swipe. Fade both viewport edges, add small paper tilts and preserve per-paper shadows. End-of-stack pulling rubber-bands the pocket and papers together. Return from detail retains the selected paper's original layer throughout. Purchase date review uses the native iOS calendar selector, with explicit confirmation and support for unknown dates.
