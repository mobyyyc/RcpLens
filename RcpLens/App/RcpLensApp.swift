import SwiftUI

@main
struct RcpLensApp: App {
    var body: some Scene {
        WindowGroup {
            FoundationView()
                .task {
                    #if DEBUG
                    await SyntheticStorageDiagnostics.runIfRequested()
                    #endif
                }
        }
    }
}
