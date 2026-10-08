# Phone layout and wallet motion refinement

The review form previously clipped its scrolling surface and placed a fixed 72-point (104-point at accessibility text sizes) blank strip below it. Removing both lets the native soft scroll edge handle content at the bottom. Review now reserves scrolling space for the final storage information rather than covering it with a rectangle.

Import, Edit, Split and review actions use a native bottom safe-area bar and glass button styles, with 20 points of extra clearance above the home-indicator safe area. Normal-size Edit stays on one line; accessibility text uses separate Edit and Split rows. Review/source and archived-inclusion switches explicitly use the standard green tint, separating the on track from its white thumb in dark appearance.

The home reader's custom scroll viewport was also larger than the physical screen. Its end could remain below the screen even after scrolling; adding only extra receipt height would not solve that. The reader now uses native scroll insets, and the receipt footer is measured to reserve its actual height plus bottom breathing room. Hidden home layers cannot intercept detail gestures. The search reader retains its independent upward fade and native scrolling. Paper edges, shadows and return layer ordering are preserved.

The front leather, back panel and feathered occlusion move together. Ordinary scrolling adds a bounded 22-point drift; end overscroll moves the wallet at 22 percent of the existing paper pull. The papers retain their existing elastic projection with the same small wallet drift added, keeping the final receipt tucked at rest. Presentation snapshots include that drift so return does not reset the pocket's position. Reduce Motion disables the added follow-through.

Verification is scoped in `validation-summary.json`; images contain fictional receipts only. The physical iPhone SDK build is compilation-only and unsigned. To update the user's installed phone build, select the physical iPhone in Xcode and Run (Command-R); its existing local Personal Team settings are preserved. Physical camera integration and device accessibility certification remain separate work.
