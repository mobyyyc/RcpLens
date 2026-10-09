import SwiftUI

struct FoundationView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Your purchase memory")
                        .font(.title2)
                    Text("Receipt import, review and storage will follow the foundation checks.")
                        .foregroundStyle(.secondary)
                }
                #if DEBUG
                Section("Development") {
                    NavigationLink("Synthetic diagnostics") { DiagnosticsView() }
                }
                #endif
            }
            .navigationTitle("Sliplet")
            #if DEBUG
            .sheet(isPresented: .constant(ProcessInfo.processInfo.arguments.contains("--synthetic-diagnostics"))) {
                NavigationStack { DiagnosticsView(autoRun: true) }
            }
            #endif
        }
    }
}
