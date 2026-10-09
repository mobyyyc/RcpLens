import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Local editing surface. Explicit Save/Finalize persist; Copy/Share exist only for the committed current split.
struct ReceiptSplitView: View {
    @Bindable var workspace: ReceiptWorkspace
    private enum Destination: Hashable { case item(UUID), policy(UUID), summary }
    @State private var path: [Destination] = []
    @State private var plan: ReceiptSplitPlan
    @State private var name = ""
    @State private var source = false
    @State private var discard = false
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    init(workspace: ReceiptWorkspace) {
        self.workspace = workspace
        _plan = State(initialValue: workspace.selected?.splitPlan ?? ReceiptSplitPlan())
    }
    private var record: ReceiptRecord? { workspace.selected }
    private var pristine: Bool { record?.splitPlan == plan || (record?.splitPlan == nil && plan.participants.isEmpty && plan.assignments.isEmpty && plan.policies.isEmpty) }
    private var result: ReceiptSplitResult? { record.flatMap { try? ReceiptSplitEngine.compute($0, plan: plan) } }
    private var failure: String? {
        guard let record else { return "Receipt unavailable." }
        do { _ = try ReceiptSplitEngine.compute(record, plan: plan); return nil }
        catch { return (error as? SplitError)?.errorDescription ?? "Check this split before finalizing." }
    }
    private var summary: String? {
        guard pristine, let record else { return nil }
        return try? ReceiptSplitEngine.summary(record, plan: plan)
    }
    private func change(_ edit: (inout ReceiptSplitPlan) -> Void) {
        edit(&plan); plan.finalizedRevision = nil; copied = false
    }
    private func money(_ value: Int64) -> String {
        let currency = record?.current.fields.currency ?? .cad
        return "\(currency.code) \(ExactInput.format(value, scale: currency.minorUnitScale))"
    }
    var body: some View {
        NavigationStack(path: $path) {
            Form {
                Section {
                    Text(record?.current.fields.merchant ?? "Receipt").font(.headline)
                    if let total = record?.current.fields.total { LabeledContent("Receipt total") { Text(money(total.minorUnits)).foregroundStyle(Color(uiColor: .label)) } }
                    Text("People stay on this device. Save choices to keep unfinished assignments. Finalize requires a reviewed receipt, every item assigned and every adjustment confirmed.").font(.footnote)
                    if let record, !ReceiptCompletion.isComplete(record) {
                        Label("Receipt needs review. Finish its corrections first.", systemImage: "exclamationmark.triangle")
                    }
                }
                Section {
                    ForEach(plan.participants) { person in
                        HStack {
                            Text(person.name).frame(maxWidth: .infinity, alignment: .leading)
                            Button(role: .destructive) {
                                change { p in
                                    p.participants.removeAll { $0.id == person.id }
                                    p.assignments = p.assignments.mapValues { $0.filter { $0 != person.id } }
                                    for i in p.policies.indices where p.policies[i].target == .selectedPeople {
                                        p.policies[i].selectedIDs.removeAll { $0 == person.id }; p.policies[i].accepted = false; p.policies[i].sourceConfirmed = false
                                    }
                                }
                            } label: { Image(systemName: "person.badge.minus").frame(minWidth: 44, minHeight: 44) }
                            .buttonStyle(.borderless).accessibilityLabel("Remove \(person.name)")
                        }
                    }
                    TextField("Person's name", text: $name).textContentType(.nickname).accessibilityIdentifier("splitName")
                    Button("Add person", systemImage: "person.badge.plus") {
                        let entered = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        change { $0.participants.append(.init(id: UUID(), name: entered)) }; name = ""
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name.count > 80 || plan.participants.count >= 100)
                        .accessibilityIdentifier("splitAddPerson")
                } header: { Text("People").foregroundStyle(Color(uiColor: .label)) }
                Section {
                    if let record {
                        ForEach(Array(record.current.fields.items.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: Destination.item(item.id)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.description ?? "Purchase")
                                    if let amount = item.amount { Text(money(amount.minorUnits)).font(.subheadline) }
                                    Text(owners(item.id)).font(.footnote)
                                }.foregroundStyle(Color(uiColor: .label))
                            }.accessibilityIdentifier("splitItem-\(index)")
                        }
                    }
                } header: { Text("Purchases").foregroundStyle(Color(uiColor: .label)) } footer: { Text("Choose one owner, or several people to share an item equally. Extra cents stay balanced across items with the same owners.").foregroundStyle(Color(uiColor: .label)) }
                if let record, !record.current.fields.adjustments.isEmpty {
                    Section {
                        ForEach(Array(record.current.fields.adjustments.enumerated()), id: \.element.id) { index, adjustment in
                            NavigationLink(value: Destination.policy(adjustment.id)) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(adjustment.label ?? adjustment.kind.rawValue)
                                    if let amount = adjustment.amount { Text(money(amount.minorUnits)).font(.subheadline) }
                                    if let policy = plan.policies.first(where: { $0.id == adjustment.id }) {
                                        Text("\(policy.method.title) · \(policy.target.title) · \(policy.accepted ? "Confirmed" : "Needs confirmation")").font(.footnote)
                                    } else { Text("Choose an allocation policy").font(.footnote) }
                                }.foregroundStyle(Color(uiColor: .label))
                            }.accessibilityIdentifier("splitAdjustment-\(index)")
                        }
                    } header: { Text("Adjustments").foregroundStyle(Color(uiColor: .label)) } footer: {
                        Text("Proportional uses each person’s purchase share before discounts and other adjustments; returns count by their positive value. Equal includes every person for All purchases, the selected purchases' owners for Selected purchases, or the chosen people. Zero purchase value requires an explicit Equal choice for a nonzero adjustment.").foregroundStyle(Color(uiColor: .label))
                    }
                }
                Section {
                    if let result {
                        ForEach(plan.participants) { person in
                            LabeledContent(person.name) { Text(money(result.totals[person.id] ?? 0)).foregroundStyle(Color(uiColor: .label)) }.accessibilityIdentifier("splitTotal-\(person.name)")
                        }
                        LabeledContent("Exact total") { Text(money(result.total)).foregroundStyle(Color(uiColor: .label)) }.font(.headline).accessibilityElement(children: .combine).accessibilityIdentifier("splitExactTotal")
                        Text(summary == nil ? "Preview · finalize to copy or share." : "Finalized for this receipt revision.")
                            .accessibilityIdentifier("splitStatus")
                    } else if let failure { Text(failure).accessibilityIdentifier("splitFailure") }
                    if let error = workspace.errorMessage { Text(error).foregroundStyle(Color(uiColor: .label)) }
                    if let summary {
                        NavigationLink("View summary", value: Destination.summary)
                        Button("Copy summary", systemImage: "doc.on.doc") {
                            guard workspace.active, !workspace.privacyCovered else { return }
                            UIPasteboard.general.setItems([[UTType.utf8PlainText.identifier: summary]], options: [.localOnly: true])
                            copied = true
                        }.accessibilityIdentifier("splitCopy")
                        ShareLink(item: summary) { Label("Share summary", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("splitShare")
                        if copied { Text("Copied on this device.").accessibilityIdentifier("splitCopied") }
                    }
                } header: { Text("Amounts").foregroundStyle(Color(uiColor: .label)) }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .item(let id):
                    if let item = record?.current.fields.items.first(where: { $0.id == id }) { itemEditor(item) }
                case .policy(let id):
                    if let adjustment = record?.current.fields.adjustments.first(where: { $0.id == id }) { policyEditor(adjustment) }
                case .summary:
                    ScrollView { Text(summary ?? "Finalize this split first.").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(20) }
                        .navigationTitle("Split summary").modifier(SplitEditorBack())
                }
            }
            .navigationTitle("Split receipt").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if path.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if pristine { dismiss() } else { discard = true } } label: { Text("Done").foregroundStyle(Color(uiColor: .label)).lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(minWidth: 44, minHeight: 48).padding(.horizontal, 4) }.buttonStyle(.plain).controlSize(.large).disabled(workspace.saving).accessibilityIdentifier("splitDone")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { source = true } label: { Text("Original").foregroundStyle(Color(uiColor: .label)).fixedSize(horizontal: true, vertical: false).frame(minHeight: 48).padding(.horizontal, 4) }.buttonStyle(.plain).controlSize(.large).disabled(workspace.image == nil || workspace.saving).accessibilityIdentifier("splitOriginal")
                }
                ToolbarItem(placement: .bottomBar) {
                    Button { workspace.saveSplit(plan, finalize: false) } label: { Text("Save choices").foregroundStyle(Color(uiColor: .label)).frame(minHeight: 34).padding(.horizontal, 8) }.buttonStyle(ReceiptSplitSecondaryStyle()).controlSize(.large)
                        .disabled(workspace.saving || (try? plan.validateStructure()) == nil).accessibilityIdentifier("splitSave")
                }.sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .bottomBar) {
                    Button { workspace.saveSplit(plan, finalize: true) } label: { Text("Finalize").frame(minHeight: 44) }.buttonStyle(ReceiptProminentStyle()).controlSize(.large)
                        .disabled(workspace.saving || result == nil || summary != nil).accessibilityIdentifier("splitFinalize")
                }
                ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Dismiss keyboard") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) } }
                }
            }
            .sheet(isPresented: $source) { ReceiptSourceView(workspace: workspace) }
            .confirmationDialog("Discard unsaved split choices?", isPresented: $discard, titleVisibility: .visible) {
                Button("Discard choices", role: .destructive) { dismiss() }
            }
            .onChange(of: record?.splitPlan?.id) { _, _ in
                if let saved = record?.splitPlan { plan = saved; copied = false }
            }
            .disabled(workspace.saving)
            .interactiveDismissDisabled(!pristine || workspace.saving)
        }.tint(.primary)
        #if DEBUG
        .dynamicTypeSize(SyntheticNativePreview.enabled && ProcessInfo.processInfo.arguments.contains("--t05-large-text") ? .accessibility5 : systemTypeSize)
        #endif
    }
    private func owners(_ item: UUID) -> String {
        let ids = Set(plan.assignments[item] ?? [])
        let names = plan.participants.filter { ids.contains($0.id) }.map(\.name)
        return names.isEmpty ? "Unassigned" : names.joined(separator: ", ") + (names.count > 1 ? " · Shared equally" : "")
    }
    private func toggle(_ id: UUID, in ids: inout [UUID], selected: Bool) {
        ids.removeAll { $0 == id }; if selected { ids.append(id) }
    }
    private func itemEditor(_ item: ReceiptLine) -> some View {
        Form {
            Section {
                Text(item.description ?? "Purchase").font(.headline)
                if let amount = item.amount { Text(money(amount.minorUnits)) }
                if let marker = item.taxMarker { Text("Printed tax marker: \(marker). Applicability has not been inferred.").font(.footnote) }
            }
            Section {
                if plan.participants.isEmpty { Text("Add people on the split screen first.") }
                ForEach(plan.participants) { person in
                    SplitSelectionRow(title: person.name, selection: Binding(get: { plan.assignments[item.id, default: []].contains(person.id) }, set: { selected in
                        change { p in
                            var ids = p.assignments[item.id, default: []]
                            toggle(person.id, in: &ids, selected: selected); p.assignments[item.id] = ids
                        }
                    })).accessibilityIdentifier("splitOwner-\(person.name)")
                }
            } header: { Text("Assign to").foregroundStyle(Color(uiColor: .label)) }
        }.navigationTitle("Item owners").modifier(SplitEditorBack())
    }
    private func policy(_ adjustment: ReceiptAdjustment) -> SplitAdjustmentPolicy {
        plan.policies.first { $0.id == adjustment.id } ?? .init(id: adjustment.id)
    }
    private func setPolicy(_ adjustment: ReceiptAdjustment, edit: (inout SplitAdjustmentPolicy) -> Void) {
        change { p in
            var next = policy(adjustment); edit(&next)
            p.policies.removeAll { $0.id == adjustment.id }; p.policies.append(next)
        }
    }
    private func policyEditor(_ adjustment: ReceiptAdjustment) -> some View {
        let p = policy(adjustment)
        return Form {
            Section {
                Text(adjustment.label ?? adjustment.kind.rawValue).font(.headline)
                if let amount = adjustment.amount { Text(money(amount.minorUnits)) }
                Picker("Allocation", selection: Binding(get: { policy(adjustment).method }, set: { method in
                    setPolicy(adjustment) { $0.method = method; $0.accepted = false }
                })) { ForEach(SplitMethod.allCases) { Text($0.title).tag($0) } }.accessibilityIdentifier("splitMethod").accessibilityValue(p.method.title)
                Picker("Allocate across", selection: Binding(get: { policy(adjustment).target }, set: { target in
                    setPolicy(adjustment) { $0.target = target; $0.selectedIDs = []; $0.accepted = false; $0.sourceConfirmed = false }
                })) { ForEach(SplitTarget.allCases) { Text($0.title).tag($0) } }.accessibilityIdentifier("splitTarget").accessibilityValue(p.target.title)
                Text("Proportional uses each person’s purchase share before discounts and other adjustments; returns count by their positive value. Equal includes all people for All purchases, selected item owners for Selected purchases, or the chosen people. A deposit or item coupon can be limited to the relevant purchases or people.").font(.footnote)
            }
            if p.target == .selectedPurchases, let record {
                Section {
                    ForEach(record.current.fields.items) { item in
                        SplitSelectionRow(title: item.description ?? "Purchase", selection: selection(adjustment, id: item.id))
                        if let marker = item.taxMarker { Text("Raw marker: \(marker)").font(.footnote) }
                    }
                } header: { Text("Included purchases").foregroundStyle(Color(uiColor: .label)) }
            }
            if p.target == .selectedPeople {
                Section { ForEach(plan.participants) { person in SplitSelectionRow(title: person.name, selection: selection(adjustment, id: person.id)) } } header: { Text("Included people").foregroundStyle(Color(uiColor: .label)) }
            }
            if adjustment.kind == .tax {
                Section {
                    Text("A printed tax marker can be ambiguous. Check the original tax legend to select taxable items. If it is unclear, choose All purchases and confirm how to share this tax.")
                    if p.target == .allPurchases { Label(p.method == .equal ? "Fallback: applicability unknown; share equally among all people." : "Fallback: applicability unknown; allocate by all purchase owners’ shares.", systemImage: "info.circle") }
                    else {
                        Button("Check original") { source = true }.disabled(workspace.image == nil)
                        SplitSelectionRow(title: "I verified this tax scope against the original", selection: Binding(get: { policy(adjustment).sourceConfirmed }, set: { confirmed in
                            setPolicy(adjustment) { $0.sourceConfirmed = confirmed; $0.accepted = false }
                        })).accessibilityIdentifier("splitTaxConfirmed")
                    }
                } header: { Text("Tax applicability").foregroundStyle(Color(uiColor: .label)) }
            }
            Section {
                SplitSelectionRow(title: adjustment.kind == .tax && p.target == .allPurchases ? "Accept this unknown-tax fallback" : "Confirm this allocation policy", selection: Binding(get: { policy(adjustment).accepted }, set: { accepted in
                    setPolicy(adjustment) { $0.accepted = accepted }
                })).accessibilityIdentifier("splitPolicyAccepted")
            }
        }.navigationTitle("Allocation policy").modifier(SplitEditorBack())
    }
    private func selection(_ adjustment: ReceiptAdjustment, id: UUID) -> Binding<Bool> {
        Binding(get: { policy(adjustment).selectedIDs.contains(id) }, set: { selected in
            setPolicy(adjustment) { p in toggle(id, in: &p.selectedIDs, selected: selected); p.accepted = false; p.sourceConfirmed = false }
        })
    }
}

private struct ReceiptSplitSecondaryStyle: PrimitiveButtonStyle {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    func makeBody(configuration: Configuration) -> some View {
        if ReceiptAccessibility.reduceTransparency(opaque) || ReceiptAccessibility.contrast(contrast) == .increased {
            Button(configuration).buttonStyle(.bordered)
        } else { Button(configuration).buttonStyle(.glass) }
    }
}

/// Standard full-row selection button: a native 44pt action with an explicit selected state.
private struct SplitSelectionRow: View {
    let title: String
    @Binding var selection: Bool
    var body: some View {
        Button { selection.toggle() } label: {
            HStack(spacing: 12) {
                Text(title).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selection ? "checkmark.circle.fill" : "circle").accessibilityHidden(true)
            }.foregroundStyle(Color(uiColor: .label)).frame(minHeight: 48).contentShape(Rectangle())
        }.buttonStyle(.plain)
            .accessibilityLabel(title).accessibilityValue(selection ? "Selected" : "Not selected")
            .accessibilityAddTraits(selection ? .isSelected : [])
    }
}

private struct SplitEditorBack: ViewModifier {
    @Environment(\.dismiss) private var pop
    func body(content: Content) -> some View {
        content.navigationBarBackButtonHidden()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { pop() } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left").accessibilityHidden(true)
                            Text("Back")
                        }.foregroundStyle(Color(uiColor: .label)).frame(minHeight: 48).padding(.horizontal, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).controlSize(.large)
                        .accessibilityLabel("Back to split").accessibilityIdentifier("splitEditorBack")
                }
            }
    }
}
