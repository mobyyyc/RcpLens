# T05 follow-up: receipt wallet

The user's 2026-10-08 direction supersedes the earlier compact recent-three-card layout. This remains T05 work; T06/T07 are awaiting approval.

## Interaction and appearance

At the user's request, an empty wallet retains the previous tilted-paper/pocket illustration and centered welcome layout. Once receipts exist, the physical wallet sits at the top. Receipts run from oldest to newest down the screen; newer papers overlap older papers, with the wallet foremost. Every unarchived receipt belongs to the scrollable stack. A jump-to-newest control appears for larger collections; All receipts provides month/store browsing without requiring named wallets.

Each preview shows the stored merchant, civil date, currency/total, review state and a short item excerpt. Paper uses an opaque system surface, a small torn edge, hairline outline and two restrained shadows. Long previews fade toward the bottom; essential receipt summaries remain available to accessibility. The complete digital paper uses the same layout for every retailer and retains unknown values explicitly.

Opening a receipt keeps the stack mounted. Papers above the selected receipt move off the top; papers below it move off the bottom. A shared geometry identifier lifts the selected paper into its expanded reading position. Returning restores the stack and scroll position. Original evidence loads independently; editing is unavailable until that original is ready. Edit and source comparison retain the existing native review/evidence flows.

Reduce Motion replaces the travel animation with a short opacity change. Accessibility text sizes separate cards rather than overlap them. The hidden stack is removed from accessibility while a receipt is expanded. Native Liquid Glass navigation and action controls surround opaque reading surfaces.

The implementation uses Apple's [matched geometry](https://developer.apple.com/documentation/swiftui/view/matchedgeometryeffect(id:in:properties:anchor:issource:)), [UIKit gesture integration](https://developer.apple.com/documentation/swiftui/uigesturerecognizerrepresentable), and [spring animation](https://developer.apple.com/documentation/swiftui/animation/spring(response:dampingfraction:blendduration:)) APIs. This is a custom SwiftUI interaction inspired by Wallet, not a claim to reproduce Apple's private Wallet implementation.

## User-approved actions

- Archive removes a receipt from the home stack into Archive. Unarchive returns it to its chronological position.
- Star marks a favorite without changing chronology. Starred is available from Settings or the collection picker.
- Swipes reveal an action and require a tap. Deletion always needs a separate confirmation, with Cancel.
- Defaults: swipe left reveals Archive; swipe right reveals Star. Settings can assign Archive, Star, Delete or None independently to each direction.
- VoiceOver exposes named receipt actions without requiring horizontal gestures.

Organization is stored inside the authenticated encrypted receipt payload. Old documents lacking the optional organization field decode as unarchived/unstarred. Receipt edits retain organization; organization changes preserve original extraction, image, purchase timestamps and correction revisions. Swipe preferences are encrypted in the existing metadata table with a separate authenticated context. No schema bump or plaintext receipt index is needed. Both write paths use the existing revocable transaction permit.

## Verification

Native fictional screenshots and current validation are stored in [t05-wallet-motion](evidence/t05-wallet-motion/). Historical evidence for the previous layout remains unchanged. Private originals, labels and OCR are not exposed by this design work. It does not re-score receipt recognition accuracy.


47 unit checks and 11 native UI checks passed. The one skipped test requires physical-device file protection. The four Wallet interaction tests exercise chronological/layer ordering, expansion/return, long content, 30-receipt scrolling and scroll restoration, configurable swipes, confirmation, archive/star/settings relaunch persistence and accessibility/motion alternatives. The other seven native checks cover actual Photos/keyboard import and strict structural accessibility across the receipt workflow.

Eight contrast findings have narrowly documented pixel-measured or disabled-control exceptions, with zero unresolved findings. Structural passes do not certify contrast or physical-device accessibility. The final Release builds, has a verified ad-hoc signature and excludes Debug preview/test controls. A simulator install is included in the validation report.

Review the [home stack](evidence/t05-wallet-motion/interaction-stack.png), [expanded paper](evidence/t05-wallet-motion/interaction-expanded-long.png), [swipe action](evidence/t05-wallet-motion/interaction-swipe-star.png), [restored empty wallet](evidence/t05-wallet-motion/native-light-empty.png), and [opening/return animation](evidence/t05-wallet-motion/paper-motion.mp4). These contain only fictional receipts in an isolated store. Hardware camera, device protection and VoiceOver remain part of the later iPhone pass. User approval of this design and T06 is still pending.
