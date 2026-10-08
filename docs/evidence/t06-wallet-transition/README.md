# Wallet receipt transition fix · 2026-10-08

The selected paper now lifts from its displayed home position while the surrounding papers leave in screen order: those above go up, and those below plus both wallet panels go down. All fade out. Returning reverses the same offsets and fades together, retaining the original paper depth and scroll position. The live stack stays mounted but hidden during the transition; only visible neighbours are cloned.

[Final animation](receipt-transitions.mp4) includes opening/returning from different heights and a long receipt scrolled before returning. [Entrance frames](entry-frame-review.png) and [return frames](return-frame-review.png) show 50-millisecond samples from this final recording. The original receipt silhouette grows in place; there is no start-position jump or remaining neighbour after the transition.

The 0.38-second ease in/out has a bounded completion instead of waiting for a spring tail. Reading-scroll state stays in the selected-paper subtree; receipt ordering and wallet geometry stay frozen during detail. Reduced Motion retains a 0.12-second fade. The existing elastic scrolling, leather depth, feathered pocket shadows, paper appearance preference and empty-wallet design remain.

## Verification

- Two focused geometry unit tests passed against final sources: offscreen destinations clear the screen/insets/shadows and reverse exactly; elastic projection remains monotone, reversible and anchored.
- Seven affected native cases passed against final sources: chronological expansion/long-detail scroll/return, one/two/three-paper pocket occlusion, projected stretch/reverse, 30-paper/end navigation and accessible motion, the new rendered regression, native structure and the complete split/share/restart/edit/wallet flow.
- The rendered regression uses Vision OCR of actual fictional screenshots, beyond hidden accessibility elements, to require exactly one selected merchant and no wallet count in detail. Nine open/return cycles cover 13 and 30 papers, different selected heights, long-detail scrolling, and the newest receipt after scrolling to the end. Restored X/Y are within two points. It passed again for final movie capture.
- Strict structural audit: zero findings. Twelve existing narrowly classified contrast diagnostics remain; no exception rules changed. Details and measured values are in [accessibility diagnostics](accessibility-diagnostics.json).
- Release build/ad-hoc signature/Debug-marker exclusion passed. The installed executable matches the verified build. All twelve normal encrypted receipts, twelve originals and encrypted preferences remain unchanged; no normal receipt was decoded or photographed for evidence.

[Exact results, fingerprints, run paths and limits](validation-summary.json), [native result](native-results.json), [unit result](unit-results.json), [recorded repeat](recorded-run-results.json), [capture provenance](capture-index.json), [Release verification](release-verification.json), [normal store preservation](normal-store-preservation.json).

Simulator automation returns measure about 1.5 seconds including event synthesis, quiescence and existence polling; these are not application animation duration or frame-rate measurements. Physical iPhone performance remains unmeasured. Two existing invalid-frame startup warnings recur in the structure/split cases; none occur in the repeated transition regression. Xcode's debugger metadata/diagnostic collection also reports nonfatal setup messages. Earlier test iterations and the pre-frame-fix recording are not counted as final verification. The initial OCR assertion accidentally included item names and bullet punctuation; the correction preserves detection of other merchant headings. A subsequent frame-by-frame review found the start-position race, which the final tap-time projected capture fixes.

All published pictures and movies use the explicitly isolated fictional store. T07 remains queued until user approval.

## Reproduce

Set `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Run scheme `T05Workflow` on the installed iOS Simulator with these cases:

- `WalletInteractionTests/testChronologicalStackExpandsAndRestoresEachPaper`
- `WalletInteractionTests/testDetailContainsOnlySelectedPaperAcrossRepeatedReturns`
- `WalletInteractionTests/testElasticStackHasVariableGapsSpeedsAndReversibleScroll`
- `WalletInteractionTests/testManyReceiptsAndAccessibleMotionFallback`
- `WalletInteractionTests/testShortStacksRemainTuckedIntoPocket`
- `NativeAccessibilityTests/testNativeWalletDetailReviewSourceAndLibraryStructureAudit`
- `ReceiptSplitUITests/testNativeAssignFinalizeCopyShareRestartEditAndWalletReturn`

Run scheme `RcpLens` with `ReceiptWorkflowTests/testDeparturesClearTheScreenAndShadowsInScreenOrder` and `ReceiptWorkflowTests/testElasticStackIsOrderedReversibleAndAnchoredAtThePocket`. Use separate derived-data/result paths and ad-hoc signing (`CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-`). For motion, record the fictional regression with `xcrun simctl io <device> recordVideo --codec=h264 <local-file.mp4>` and stop recording after it passes. Never record the normal wallet for public evidence.
