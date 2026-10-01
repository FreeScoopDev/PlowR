import SwiftUI
import SwiftData

/// A client's Service History: every job in the Service Log, newest first,
/// with what was done, what it came to and whether it's been billed. Work
/// done off a route or a visit can be logged here by hand.
struct ClientServiceHistoryView: View {
    let client: Client

    @Environment(\.modelContext) private var modelContext
    @Query private var records: [ServiceRecord]
    @State private var showingLogWork = false
    @State private var showingBillWork = false
    @State private var showingProof = false

    init(client: Client) {
        self.client = client
        let id = client.id.uuidString
        _records = Query(filter: #Predicate<ServiceRecord> { $0.clientID == id },
                         sort: \.performedAt, order: .reverse)
    }

    /// What Bill Unbilled Work would bill this client (WorkBilling), so the
    /// two never disagree.
    private var unbilledTotal: Double {
        WorkBilling.unbilledWork(in: nil, operatorID: client.operatorID, clientID: client.id.uuidString,
                                 in: modelContext).first?.total ?? 0
    }

    var body: some View {
        List {
            if records.isEmpty {
                ContentUnavailableView {
                    Label("No Work Recorded Yet", systemImage: "list.bullet.clipboard")
                } description: {
                    Text("Completed route stops and scheduled visits show up here. Work done any other way can be logged by hand.")
                } actions: {
                    Button("Log Work") { showingLogWork = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                let unbilled = unbilledTotal
                Section {
                    LabeledContent("Jobs", value: "\(records.count)")
                    LabeledContent("Not Billed Yet") {
                        Text(unbilled, format: .currency(code: "USD"))
                            .foregroundStyle(unbilled > 0 ? .orange : .secondary)
                    }
                    if unbilled > 0 {
                        Button {
                            showingBillWork = true
                        } label: {
                            Label("Bill Unbilled Work", systemImage: "tray.and.arrow.up")
                        }
                    }
                    Button {
                        showingProof = true
                    } label: {
                        Label("Service Report", systemImage: "checkmark.seal")
                    }
                }
                // Looked up once for the list, not once a row.
                let invoiceIDs = ServiceLog.invoiceIDs(in: modelContext)
                let contracts = Contracts.all(in: modelContext)
                Section {
                    ForEach(records) { record in
                        let charge = ServiceLog.charge(of: record, contracts: contracts)
                        let status = ServiceLog.billingStatus(
                            of: record, invoiced: invoiceIDs.contains(record.invoiceID),
                            covered: !record.lines.isEmpty && charge.isEmpty)
                        NavigationLink {
                            ServiceRecordDetailView(record: record, client: client)
                        } label: {
                            ServiceRecordRow(record: record, status: status,
                                             charged: InvoiceLines.roundedToCent(charge.reduce(0) { $0 + $1.price }))
                        }
                    }
                }
            }
        }
        .navigationTitle("Service History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLogWork = true
                } label: {
                    Label("Log Work", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingLogWork) {
            LogWorkView(client: client)
        }
        .sheet(isPresented: $showingProof) {
            ProofOfServiceView(client: client)
        }
        .sheet(isPresented: $showingBillWork) {
            BillWorkView(onlyClient: client)
        }
    }
}

/// One job in a Service History list: what it charges (under a contract,
/// its price, or for covered work what the work came to, in grey), and
/// where it stands with billing.
struct ServiceRecordRow: View {
    let record: ServiceRecord
    let status: ServiceLog.BillingStatus
    /// What it charges (ServiceLog.charge).
    let charged: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.performedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(status == .covered ? ServiceLog.total(of: record) : charged, format: .currency(code: "USD"))
                    .font(.subheadline)
                    .foregroundStyle(record.isBillable && status != .covered ? .primary : .secondary)
            }
            Text(servicesSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                ServiceRecordStatusChip(status: status)
                if record.minutes >= 1 {
                    Label("\(Int(record.minutes.rounded())) min", systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if !record.routeName.isEmpty {
                    Label(record.routeName, systemImage: "map")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var servicesSummary: String {
        let names = record.lines.map(\.name)
        return names.isEmpty ? "No services recorded" : names.formatted(.list(type: .and))
    }
}

/// Where a job stands with billing (ServiceLog.billingStatus).
struct ServiceRecordStatusChip: View {
    let status: ServiceLog.BillingStatus

    var body: some View {
        let (text, colour): (String, Color) = switch status {
        case .invoiced: ("Invoiced", .green)
        case .notTracked: ("Billing Not Tracked", .gray)
        case .noCharge: ("No Charge", .purple)
        case .covered: ("Covered by Contract", .teal)
        case .notBilled: ("Not Billed", .orange)
        }
        StatusChip(text, color: colour)
    }
}
