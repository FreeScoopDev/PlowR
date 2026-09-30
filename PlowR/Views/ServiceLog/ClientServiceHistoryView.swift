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

    init(client: Client) {
        self.client = client
        let id = client.id.uuidString
        _records = Query(filter: #Predicate<ServiceRecord> { $0.clientID == id },
                         sort: \.performedAt, order: .reverse)
    }

    private var unbilledTotal: Double {
        records.filter { ServiceLog.isUnbilled($0, in: modelContext) }
            .reduce(0) { $0 + ServiceLog.total(of: $1) }
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
                }
                Section {
                    ForEach(records) { record in
                        NavigationLink {
                            ServiceRecordDetailView(record: record, client: client)
                        } label: {
                            ServiceRecordRow(record: record)
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
    }
}

/// One job in a Service History list.
struct ServiceRecordRow: View {
    let record: ServiceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(record.performedAt, format: .dateTime.month(.abbreviated).day().year())
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(ServiceLog.total(of: record), format: .currency(code: "USD"))
                    .font(.subheadline)
                    .foregroundStyle(record.isBillable ? .primary : .secondary)
            }
            Text(servicesSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                ServiceRecordStatusChip(record: record)
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
    let record: ServiceRecord
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let (text, colour): (String, Color) = switch ServiceLog.billingStatus(of: record, in: modelContext) {
        case .invoiced: ("Invoiced", .green)
        case .notTracked: ("Billing Not Tracked", .gray)
        case .noCharge: ("No Charge", .purple)
        case .notBilled: ("Not Billed", .orange)
        }
        StatusChip(text, color: colour)
    }
}
