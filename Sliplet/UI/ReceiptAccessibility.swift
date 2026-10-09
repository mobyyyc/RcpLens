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
        let button = Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.frame(minHeight: 30)
        }
        if ReceiptAccessibility.reduceTransparency(systemOpaque) || ReceiptAccessibility.contrast(systemContrast) == .increased {
            button.buttonStyle(.borderedProminent).foregroundStyle(Color(uiColor: .systemBackground)).controlSize(.regular)
        } else { button.buttonStyle(.glassProminent).foregroundStyle(Color(uiColor: .systemBackground)).controlSize(.regular) }
    }
}

/// Native glass actions share a comfortable gap above the home indicator. The safe-area
/// bar reserves their height and supplies the system scroll edge effect, without a solid panel.
struct ReceiptActionBarLayout: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.body).controlSize(.regular)
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
            .frame(maxWidth: .infinity)
    }
}

struct ReceiptSecondaryStyle: PrimitiveButtonStyle {
    var circular = false
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isEnabled) private var enabled
    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        let solid = ReceiptAccessibility.reduceTransparency(opaque) || ReceiptAccessibility.contrast(contrast) == .increased
        if circular {
            let button = Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.frame(width: 44, height: 44)
            }.buttonStyle(.plain).foregroundStyle(.primary).opacity(enabled ? 1 : 0.4)
            if solid {
                button.background { Circle().fill(Color(uiColor: .secondarySystemGroupedBackground)) }
                    .overlay { Circle().stroke(.primary.opacity(0.35), lineWidth: 1) }
            } else {
                button.glassEffect(.regular.interactive(), in: .circle)
            }
        } else {
            let button = Button(role: configuration.role, action: configuration.trigger) {
                configuration.label.frame(minHeight: 30)
            }.buttonBorderShape(.capsule)
            if solid { button.buttonStyle(.bordered).controlSize(.regular) }
            else { button.buttonStyle(.glass).controlSize(.regular) }
        }
    }
}
