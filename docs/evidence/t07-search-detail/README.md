# Search detail transition and scroll fix

Search/history results now open a dedicated reading surface with a 0.22-second ease-out fade and 12-point upward movement; Reduce Motion uses only a 0.12-second fade. Home wallet cards retain their existing paper-lift/stack motion. Receipt-level history results, item matches and returning from review all use the reading surface while the library is active.

The previous search path mounted `ReceiptWalletScene` for detail and inserted match context above it with a fixed `safeAreaInset`. That combined the wallet's geometry-based scroll positioning with a new inset and an opaque header boundary. The new surface uses natural vertical layout: context, status, paper and footer in one scroll view, with native soft effects at the system bars. Context scrolls away with the long receipt; no central header overlays or cuts the detail. Paper styling, original access, edit, split, archived results and the retained query continue through the existing workspace.

Verification and exact tested sources are recorded in `validation-summary.json`; fictional screenshots are mapped in `capture-index.json`. This follow-up changes UI and one native regression test only; it does not rescore OCR or change storage/search/splitting arithmetic. No normal-wallet originals or Photos are exported or captured. Physical camera work remains pending approval.
