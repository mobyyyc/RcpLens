# T05 follow-up: receipt wallet

The user's 2026-10-08 direction supersedes the earlier compact recent-three-card layout. This remains T05 work; T06/T07 are awaiting approval.

## Interaction and appearance

At the user's request, an empty wallet retains the previous tilted-paper/pocket illustration and centered welcome layout. Once receipts exist, the physical wallet sits at the top. Receipts run from oldest to newest down the screen; newer papers overlap older papers, with the wallet foremost. Every unarchived receipt belongs to the scrollable stack. A jump-to-newest control appears for larger collections; All receipts provides month/store browsing without requiring named wallets.

Each preview shows the stored merchant, civil date, currency/total, review state and a short item excerpt. Paper uses an opaque system surface, a small torn edge, hairline outline and two restrained shadows. Content masks are applied before the shadow, so the silhouette casts a shadow beyond the preview’s bounds. The wallet crown uses a pale neutral material in light mode and charcoal in dark mode. Long previews fade toward the bottom; essential receipt summaries remain available to accessibility. The complete digital paper uses the same layout for every retailer and retains unknown values explicitly.

Opening a receipt keeps the stack mounted. Papers above the selected receipt move off the top; papers below it move off the bottom. A retained paper surface lifts from its measured preview rectangle into the reading position. The paper’s height grows to fit all contents, carrying its torn bottom edge with it. Returning restores the stack and scroll position. Original evidence loads independently; editing is unavailable until that original is ready. Edit and source comparison retain the existing native review/evidence flows.

Reduce Motion replaces the travel animation with a short opacity change. Accessibility text sizes separate cards rather than overlap them. The hidden stack is removed from accessibility while a receipt is expanded. Native Liquid Glass navigation and action controls surround opaque reading surfaces.

The implementation uses Apple's [animation completion](https://developer.apple.com/documentation/swiftui/withanimation(_:completioncriteria:_:completion:)), [UIKit gesture integration](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable), and [spring animation](https://developer.apple.com/documentation/swiftui/animation/spring(response:dampingfraction:blendduration:)) APIs. This is a custom SwiftUI interaction inspired by Wallet, not a claim to reproduce Apple's private Wallet implementation.

## User-approved actions

- Archive removes a receipt from the home stack into Archive. Unarchive returns it to its chronological position.
- Star marks a favorite without changing chronology. Starred is available from Settings or the collection picker.
- Swipes reveal a [native glass](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)) action and require a tap. Its width and height grow with drag distance, entirely within the revealed gap; the active row rises above neighboring papers while swiping. Deletion always needs a separate confirmation, with Cancel.
- Defaults: swipe left reveals Archive; swipe right reveals Star. Settings can assign Archive, Star, Delete or None independently to each direction.
- VoiceOver exposes named receipt actions without requiring horizontal gestures.

Organization is stored inside the authenticated encrypted receipt payload. Old documents lacking the optional organization field decode as unarchived/unstarred. Receipt edits retain organization; organization changes preserve original extraction, image, purchase timestamps and correction revisions. Swipe preferences are encrypted in the existing metadata table with a separate authenticated context. No schema bump or plaintext receipt index is needed. Both write paths use the existing revocable transaction permit.

## Verification

The latest refinement is verified in [t05-wallet-refinement](evidence/t05-wallet-refinement/). Earlier interaction evidence is stored in [t05-wallet-motion](evidence/t05-wallet-motion/). Historical evidence for the previous layout remains unchanged. Private originals, labels and OCR are not exposed by this design work. It does not re-score receipt recognition accuracy.


The current refinement passed four Wallet interaction and five native accessibility checks. The Wallet suite covers chronological/layer ordering, expansion/return (including a scrolled long receipt), 30-receipt scrolling and restoration, configurable swipes, confirmation, archive/star/settings relaunch persistence and motion/text alternatives. New assertions require the glass action to be hittable, at least 44pt wide and entirely beside the shifted paper.

Nine contrast findings have narrowly documented pixel-measured or disabled-control exceptions, with zero unresolved findings. Two specific virtual receipt-summary buttons include overlapping paper and its cast shadow; their fictional crops measure black/white glyph pairs at 21:1. Unexpected reading/action contrast findings still fail, and structural checks remain strict. Structural passes do not certify contrast or physical-device accessibility. Final Release build/signature and Debug-control exclusion passed, and that app is installed and normally launched in the simulator.

The preceding milestone's 47 unit passes, 11 native passes and one physical-device protection skip remain the historical baseline. The current UI-only refinement reran nine native checks, without changing receipt models, persistence, recognition or import logic. [Validation scope and final sources](evidence/t05-wallet-refinement/validation-summary.json).

Review the [home stack](evidence/t05-wallet-refinement/interaction-stack.png), [expanded paper](evidence/t05-wallet-refinement/interaction-expanded-long.png), [swipe action](evidence/t05-wallet-refinement/interaction-swipe-star.png), [restored empty wallet](evidence/t05-wallet-refinement/native-light-empty.png), and [opening/return animation](evidence/t05-wallet-refinement/paper-motion.mp4). These contain only fictional receipts in an isolated store. Hardware camera, device protection and VoiceOver remain part of the later iPhone pass. User approval of this design and T06 is still pending.
