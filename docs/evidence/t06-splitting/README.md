# T06 splitting and wallet-shadow evidence

All screenshots show isolated fictional receipts. No normal-wallet image or decrypted normal receipt is included.

Verification covers 73 hosted unit passes plus one physical-protection skip, the independent main-chat allocator oracle (40/40), and 19 unique native cases. Eight final affected cases pass in UI14; its only failing contrast case is replaced by the passing focused UI17 audit, with unchanged app sources. Ten unaffected native cases precede the final UI-only refinements. Exact scope, source hashes, actual warnings and limitations are in [validation-summary.json](validation-summary.json).

- [Finalized exact amounts; single-line Done and single Save surface](T06-finalized-exact-amounts.png)
- [Dark split controls](T06-dark-split.png)
- [True accessibility5 text, reduced motion and opaque controls](T06-large-text-reduced-motion.png)
- [Explicit tax fallback](T06-explicit-tax-fallback.png)
- [Actual native Share sheet](T06-native-share-sheet.png)
- [Persisted finalized split after restart](T06-restarted-split.png)
- [Receipt edits invalidate output](T06-edit-invalidates-finalization.png)
- [One paper: softened side shadows and retained pocket occlusion](Tucked-wallet-1.png)
- [Two papers](Tucked-wallet-2.png)
- [Three papers](Tucked-wallet-3.png)
- [Elastic stack at rest](Elastic-stack-rest.png)
- [Elastic stack after a swipe](Elastic-stack-pulled.png)

The final audit classifies the ownership footer and Adjustments heading at/below the bottom-toolbar edge as occluded/unmeasurable, rather than claiming their offscreen pixels establish contrast. Disabled Finalize is explicitly noninteractive; its actual native gray is recorded. Save choices (20.01:1) and Back in each editor (19.66:1) are individually measured SDK false positives. Unknown visible findings fail, structural audits have no waivers, and participant-name exceptions are absent.

The 19-case baseline bundle records nine invalid-frame warnings, one per attributed case. The final nine-case bundle records six, and the focused audit records one. Exact attribution is retained in the summary; successful assertions do not remove those warnings. Device certification remains pending. The final Release app is installed and normally launched; all twelve encrypted normal-wallet payloads match the before-test fingerprint.
