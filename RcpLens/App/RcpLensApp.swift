import SwiftUI

@main
struct RcpLensApp: App {
    @UIApplicationDelegateAdaptor(ReceiptPrivacyDelegate.self) private var privacyDelegate
    var body: some Scene {
        WindowGroup { ReceiptSessionView() }
    }
}

struct ReceiptSessionView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @State private var workspace: ReceiptWorkspace = {
        #if DEBUG
        if SyntheticNativePreview.enabled {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return ReceiptWorkspace(directory: base.appendingPathComponent("T05SyntheticPreviewStore"),
                keyProvider: KeychainReceiptStoreKey(service: "com.mobyyyc.RcpLens.T05-synthetic-preview", account: "v1"))
        }
        if WorkflowTestInput.enabled {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return ReceiptWorkspace(directory: base.appendingPathComponent("T05WorkflowTestStore"),
                keyProvider: KeychainReceiptStoreKey(service: "com.mobyyyc.RcpLens.T05-local-test", account: "v1"))
        }
        #endif
        return ReceiptWorkspace()
    }()
    var body: some View {
        ReceiptHome(workspace: workspace).id(workspace.sessionID)
            #if DEBUG
            .dynamicTypeSize(SyntheticNativePreview.enabled && ProcessInfo.processInfo.arguments.contains("--t05-large-text") ? .accessibility5 : systemTypeSize)
            .preferredColorScheme(SyntheticNativePreview.enabled ? (ProcessInfo.processInfo.arguments.contains("--t05-light") ? .light : .dark) : nil)
            #endif
            .task {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--synthetic-diagnostics") || ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--synthetic-storage-") }) {
                    return
                }
                #endif
                workspace.activate(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
                #if DEBUG
                await SyntheticNativePreview.run(workspace)
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .background: workspace.suspend()
                case .active:
                    ReceiptPrivacyCover.hide()
                    workspace.activate(protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable)
                case .inactive:
                    ReceiptPrivacyCover.show()
                    workspace.privacyCovered = true // Unsaved data is retained through transient picker inactivity.
                @unknown default: workspace.suspend()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataWillBecomeUnavailableNotification)) { _ in workspace.suspend() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
                if scenePhase == .active { ReceiptPrivacyCover.hide(); workspace.activate(protectedDataAvailable: true) }
            }
            #if DEBUG
            .sheet(isPresented: .constant(ProcessInfo.processInfo.arguments.contains("--synthetic-diagnostics"))) {
                NavigationStack { DiagnosticsView(autoRun: true) }
            }
            .onChange(of: workspace.flow) { _, _ in WorkflowTestInput.recordState(workspace, event: "flow") }
            .onChange(of: workspace.availability) { _, _ in WorkflowTestInput.recordState(workspace, event: "availability") }
            .task { await SyntheticStorageDiagnostics.runIfRequested() }
            #endif
    }
}
