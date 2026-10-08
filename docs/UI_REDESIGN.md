# T05 follow-up · Native design audit and redesign

**Latest design:** [Wallet stack, in-place paper expansion and configurable actions](WALLET_DESIGN.md). The audit below records the earlier redesign.

Requested by the user on 2026-10-08 after reviewing the running empty wallet. This is an authorized T05 design correction; T06 is still awaiting approval.

## Audit

| Finding | Resulting design |
|---|---|
| Two import controls compete on the empty screen. | One persistent, labeled **Import receipt** action, in the native bottom toolbar. |
| Large decorative wallet, slogan, instructions and storage warning compete for attention. | Compact layered paper illustration, one short explanation, and a quiet local-privacy label. Storage disclosure remains reachable through the info control and in review before saving. |
| Icon-only bottom switches make one collection look like two destinations. | **Wallet** has a clear title; **All receipts** opens its filtered collection from the header and provides a Wallet return control. |
| Large wallet lip, triangle decorations and equally weighted receipt text weaken the paper metaphor. | Smaller pocket edge, restrained tilt, thin borders and soft layer shadows. Merchant and total lead each real receipt button; date and Needs review state remain readable. |
| Original is repeated in the detail and review flows. | One labeled **Original** control in the navigation bar. Linked per-item Source actions retain their distinct evidence purpose. |
| A large trash button competes with editing. | One labeled **Edit receipt** action. Delete lives in receipt options and still requires confirmation and a visible cancellation path. |
| Floating actions can cover the last visible library row. | Library and review reserve a clear area above floating actions. |
| Settled layouts could hide a title; very large text clipped the merchant field. | Wallet and library use a consistent explicit heading; the editable merchant field wraps when text is enlarged. |
| Long instructional rows push receipt fields down. | Short review prompt; quantity and adjustment guidance in section footers; source confirmation remains explicit. |

The design keeps neutral system colours, solid reading surfaces and native Liquid Glass controls. Paper lift remains the chosen direction. Large Dynamic Type changes the receipt stack to separated, unrotated rows; optional pull-to-open and tap both remain available. The empty illustration contains no fake receipt fields.

Native navigation/action hierarchy is informed by Apple's [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars) and [Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass) guidance. This app currently has one receipt collection, so this revision uses collection navigation rather than decorative tab-like toolbar buttons.

## Native review

All screenshots below are fictional Debug fixtures, isolated from production receipts. Private originals, labels, OCR and screenshots stay ignored and were not exposed during this design review.

- [Empty · dark](evidence/t05-redesign/native-empty.png) and [empty · light](evidence/t05-redesign/native-light-empty.png)
- [Recent receipts](evidence/t05-redesign/native-wallet.png) and [dark wallet](evidence/t05-redesign/native-dark-wallet.png)
- [Digital receipt](evidence/t05-redesign/native-detail.png), [editable review](evidence/t05-redesign/native-review.png), and [large text](evidence/t05-redesign/native-large-text.png)
- [500-record library](evidence/t05-redesign/native-library.png) and [original evidence](evidence/t05-redesign/native-source.png)

**Validation:** all seven native tests pass: five navigation/accessibility checks and two actual photo-import/edit/recovery checks. The single Import action, storage disclosure, collection navigation, delete cancellation/confirmation, source access and large-text paths are exercised. Final Release builds with a verified ad-hoc signature and no compiled Debug controls. Twelve narrowly identified simulator contrast findings are documented using screenshot measurements or the disabled-control exception; there are no unresolved findings, and this is not full device/material accessibility certification. Results and current source hashes are in [validation-summary.json](evidence/t05-redesign/validation-summary.json). The prior T05 evidence describes commit `95e69ed`; it remains preserved. This UI follow-up does not change parsing, reconciliation, encrypted storage or their accepted unit-test results, and does not re-score real-receipt OCR accuracy. It verifies the new presentation and navigation with native tests and a fresh Release build. Physical iPhone/VoiceOver and complete material-state accessibility checks remain deferred.

## Phone layout follow-up (2026-10-08)

Review uses a native soft scroll edge with no clipped blank spacer. Import/Edit/Split/review actions have extra clearance above the home indicator in a native bottom safe-area bar. On switches use the native green track. The home reader uses native insets and a measured footer so a long paper's total, torn bottom and local-storage label can all be scrolled clear of the controls. Wallet leather follows both scroll directions at a smaller speed while papers retain their elastic spacing and depth. [Diagnosis and exact verification scope](evidence/t07-phone-layout/README.md).
