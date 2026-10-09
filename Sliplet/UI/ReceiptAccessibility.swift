import SwiftUI

/// System values drive production. Debug-only preview flags exercise the same branches without OS changes.
@MainActor enum ReceiptAccessibility {
    static func reduceMotion(_ system: Bool) -> Bool {
        #if DEBUG
        if SyntheticNativePreview.enabled && ProcessInfo.processInfo.arguments.contains("--t05-reduce-motion") { return true }
        #endif
        return system
    }
    static func reduceTransparency(_ system: Bool) -> Bool {
        #if DEBUG
        if SyntheticNativePreview.enabled && ProcessInfo.processInfo.arguments.contains("--t05-opaque") { return true }
        #endif
        return system
    }
    static func contrast(_ system: ColorSchemeContrast) -> ColorSchemeContrast {
        #if DEBUG
        if SyntheticNativePreview.enabled && ProcessInfo.processInfo.arguments.contains("--t05-contrast") { return .increased }
        #endif
        return system
    }
}

struct ReceiptProminentStyle: PrimitiveButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var systemOpaque
    @Environment(\.colorSchemeContrast) private var systemContrast
    func makeBody(configuration: Configuration) -> some View {
        if ReceiptAccessibility.reduceTransparency(systemOpaque) || ReceiptAccessibility.contrast(systemContrast) == .increased {
            Button(configuration).buttonStyle(.borderedProminent).foregroundStyle(Color(uiColor: .systemBackground))
        } else { Button(configuration).buttonStyle(.glassProminent).foregroundStyle(Color(uiColor: .systemBackground)) }
    }
}

/// Native glass actions share a comfortable gap above the home indicator. The safe-area
/// bar reserves their height and supplies the system scroll edge effect, without a solid panel.
struct ReceiptActionBarLayout: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.body.weight(.semibold)).controlSize(.large)
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 20)
            .frame(maxWidth: .infinity)
    }
}

struct ReceiptSecondaryStyle: PrimitiveButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        if ReceiptAccessibility.reduceTransparency(opaque) || ReceiptAccessibility.contrast(contrast) == .increased {
            Button(configuration).buttonStyle(.bordered)
        } else { Button(configuration).buttonStyle(.glass) }
    }
}
