import SwiftUI
import SwiftData

/// Bill Unbilled Work: pick a period, see each client with work not billed
/// yet, and make one draft invoice per client ticked (WorkBilling). The
/// drafts land in Documents to check and send.
struct BillWorkView: View {
    /// Only this client's work (from their Service History); nil for everyone.
    var onlyClient: Client?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager

    @State private var period: WorkBilling.Period = .everything
    /// Clients unticked: left out of this billing.
    @State private var leftOut: Set<UUID> = []
    /// The work to bill, looked up when the screen opens or the period
    /// changes, not on every tap.
    /// nil until first looked up.
    @State private var works: [WorkBilling.ClientWork]?
    @State private var outcome: WorkBilling.Outcome?

    private func loadWorks() {
        works = WorkBilling.unbilledWork(in: period.range(now: .now), operatorID: authManager.userID,
                                         clientID: onlyClient?.id.uuidString, in: modelContext)
    }

    // PlowR Pro: read only, this editor shows why instead (EditsNeedPro).
    var body: some View { editor.editsNeedPro() }

    @ViewBuilder private var editor: some View {
        let works = works ?? []
        let chosen = works.filter { !leftOut.contains($0.id) }
        let total = InvoiceLines.roundedToCent(chosen.reduce(0) { $0 + $1.total })
        NavigationStack {
            List {
                Section {
                    Picker("Period", selection: $period) {
                        ForEach(WorkBilling.Period.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if self.works == nil {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                } else if works.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to Bill", systemImage: "checkmark.seal")
                    } description: {
                        Text("No work in this period is waiting to be billed. Jobs come from completed stops and visits, and from Log Work.")
                    }
                } else {
                    Section {
                        ForEach(works) { work in
                            clientRow(work, isOn: !leftOut.contains(work.id))
                        }
                    } footer: {
                        Text("One draft invoice per client ticked, a line per service done with its day. Check and send them from Documents.")
                    }
                }
            }
            .navigationTitle(onlyClient.map { "Bill \($0.name)" } ?? "Bill Unbilled Work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !works.isEmpty {
                    Button {
                        // Billed as it is now: what was billed or deleted
                        // meanwhile is left out (WorkBilling.invoice re-checks).
                        outcome = WorkBilling.invoiceAll(chosen, operatorID: authManager.userID, in: modelContext)
                        loadWorks()
                    } label: {
                        Text(chosen.isEmpty ? "Choose Clients to Bill"
                             : "Create \(chosen.count) Draft Invoice\(chosen.count == 1 ? "" : "s") · "
                                + total.formatted(.currency(code: "USD")))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .primaryActionStyle(.blue)
                    .disabled(chosen.isEmpty)
                    .padding()
                    .background(.bar)
                }
            }
            .task(id: period) { loadWorks() }
            .alert(outcome?.stoppedShort == true ? "Not All Invoices Were Made"
                   : outcome?.invoices.isEmpty == true ? "Nothing Left to Bill" : "Draft Invoices Created",
                   isPresented: Binding(get: { outcome != nil }, set: { if !$0 { outcome = nil } })) {
                Button("OK") { if outcome?.stoppedShort != true { dismiss() } }
            } message: {
                let count = outcome?.invoices.count ?? 0
                let made = "\(count) draft invoice\(count == 1 ? " is" : "s are") in Documents, ready to check and send."
                Text(outcome?.stoppedShort == true
                     ? made + " The next couldn't be saved; the work left is still listed to try again."
                     : count == 0 ? "That work was billed or removed meanwhile." : made)
            }
        }
    }

    private func clientRow(_ work: WorkBilling.ClientWork, isOn: Bool) -> some View {
        Button {
            if isOn { leftOut.insert(work.id) } else { leftOut.remove(work.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(work.client.name).font(.subheadline.weight(.semibold))
                    Text("\(work.records.count) job\(work.records.count == 1 ? "" : "s") · since "
                         + (work.records.first.map { WorkBilling.day($0.performedAt, now: .now) } ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if case let unpriced = work.jobsNeedingAPrice, unpriced > 0 {
                        Text(unpriced == 1 ? "1 job has a service at $0: set its price on the job's page (All Work)"
                                           : "\(unpriced) jobs have a service at $0: set their price on each job's page (All Work)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
                Text(work.total, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
