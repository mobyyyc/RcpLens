# Wallet paper and native control refinement

Fictional receipts only; no personal receipt screenshots or labels are included.

The receipt silhouette is opaque in preview and expansion, with item text fading inside it. The leather front casts an upward contact shadow. Home, reader, review and split use shared regular native primary/secondary styles. Native safe-area bars reserve actual action height; the reader no longer adds the bar inset a second time.

Seven UI cases passed across two scoped runs on iPhone 18 Pro / iOS 27.0: native import contrast in light/dark, large-text opaque/reduced-motion controls, complete split assignment/finalization/share/relaunch, dark review switch and footer, long reader footer with a bounded end gap, paper appearance persistence, and one/two/three receipt sandwich layering plus return.

The initial run executed two NativeAccessibilityTests; its four selectors pointing at SyntheticUIWorkflowTests matched zero cases. The second run used WalletInteractionTests and ReceiptSplitUITests and executed all five requested cases. No unexecuted selectors are counted.

Simulator Release and unsigned physical iPhone SDK Release builds passed. Existing Xcode debugger lookup, cleanup simctl lookup and SwiftUI invalid-frame diagnostics remain in the raw local logs; all executed cases passed. Screenshots were visually checked for compact controls, readable final content and opaque paper at the pocket.

See [shared UI components](../../UI_COMPONENTS.md). Device testing remains a user follow-up.
