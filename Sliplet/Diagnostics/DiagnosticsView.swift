#if DEBUG
import SwiftUI

struct DiagnosticsView: View {
    var autoRun = false
    @State private var diagnostics = SyntheticDiagnostics()

    var body: some View {
        List {
            Section {
                Text("Fixed synthetic inputs only. No private receipts are read. Results below do not measure receipt accuracy.")
                Button(diagnostics.isRunning ? "Running checks…" : "Run synthetic checks") {
                    Task { await diagnostics.run() }
                }
                .disabled(diagnostics.isRunning)
                .accessibilityIdentifier("runSyntheticChecks")
            }
            Section("Vision · bundled PNG") {
                LabeledContent("Result", value: diagnostics.report.vision)
                LabeledContent("Recognized lines", value: String(diagnostics.report.recognizedLineCount))
                LabeledContent("Expected text matched", value: diagnostics.report.syntheticTextMatched ? "Yes" : "No")
            }
            Section("Foundation Models · local") {
                LabeledContent("Availability", value: diagnostics.report.modelAvailability)
                LabeledContent("Generation", value: diagnostics.report.generation)
                LabeledContent("Response characters", value: String(diagnostics.report.responseCharacterCount))
                if let domain = diagnostics.report.modelFailureDomain {
                    Text("Failure: \(domain), code \(diagnostics.report.modelFailureCode ?? 0)")
                }
                if !diagnostics.syntheticResponse.isEmpty {
                    Text(diagnostics.syntheticResponse)
                        .textSelection(.enabled)
                }
            }
            if diagnostics.reportWriteFailed {
                Text("Could not save aggregate debug results.")
            }
        }
        .navigationTitle("Synthetic checks")
        .task { if autoRun { await diagnostics.run() } }
    }
}
#endif
