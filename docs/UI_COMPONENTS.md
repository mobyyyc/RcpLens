# Native UI components

Primary actions use `ReceiptProminentStyle`: native prominent Liquid Glass, with a bordered prominent fallback for reduced transparency or increased contrast. Import, Edit, Finish, Finalize and manual entry share this style.

Secondary actions use `ReceiptSecondaryStyle`: native Liquid Glass, with the same accessibility fallback to bordered controls. Split, Save draft, Save choices, retry, cancellation and wallet jump share this style. Controls use the regular native size; their labels do not add custom vertical frames or capsule padding. Navigation controls use the system toolbar treatment. Form rows retain native row actions; destructive actions retain explicit confirmation.

`ReceiptActionBarLayout` places home, reader, review and split actions in a native bottom safe-area bar, with 8 points above and 12 points below the controls. The system reserves the bar's actual height, including changes for Dynamic Type. Reader content adds only a 12-point finishing margin, without adding the safe-area/bar height again. Large accessibility sizes retain the vertically arranged reader actions.

Receipt paper stays opaque through preview and expansion, including its torn edge and per-layer shadows. Long preview item text fades inside the paper. The wallet front casts the mouth contact shadow; no transparent gradient is applied to the receipt silhouette.
