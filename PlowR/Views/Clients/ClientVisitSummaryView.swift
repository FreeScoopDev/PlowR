import SwiftUI
import SwiftData

struct ClientVisitSummaryView: View {
    let client: Client
    @Environment(\.dismiss) private var dismiss
    @Query private var allProposals: [Proposal]

    // MARK: - Computed Properties

    private var clientInvoices: [Proposal] {
        allProposals.filter { $0.clientID == client.id.uuidString && $0.isInvoice }
    }

    private var outstanding: Double {
        clientInvoices.filter { $0.invoicePaidAt == nil }.reduce(0) { $0 + $1.total }
    }

    private var paid: Double {
        clientInvoices.filter { $0.invoicePaidAt != nil }.reduce(0) { $0 + $1.total }
    }

    private var goalDiff: Double? {
        guard client.goalMinutes > 0, client.averageServiceMinutes > 0 else { return nil }
        return client.averageServiceMinutes - Double(client.goalMinutes)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                visitSection
                if !clientInvoices.isEmpty {
                    invoiceSection
                }
            }
            .navigationTitle(client.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Sections

    private var visitSection: some View {
        Section("Service History") {
            LabeledContent("Total Visits", value: "\(client.totalVisits) visit\(client.totalVisits == 1 ? "" : "s")")
            if let last = client.lastServiceDate {
                LabeledContent("Last Service") {
                    Text(last, format: .dateTime.month(.abbreviated).day().year())
                }
            }
            if client.averageServiceMinutes > 0 {
                LabeledContent("Average Time") {
                    Text(String(format: "~%.0f min", client.averageServiceMinutes))
                }
            }
            if client.goalMinutes > 0 {
                LabeledContent("Goal Time") {
                    Text("\(client.goalMinutes) min")
                }
            }
            if let diff = goalDiff {
                LabeledContent("vs. Goal") {
                    let label = abs(diff) < 1
                        ? "On target"
                        : (diff > 0 ? "\(Int(diff))m over" : "\(Int(-diff))m under")
                    Text(label)
                        .foregroundStyle(abs(diff) < 2 ? .green : (diff > 0 ? .orange : .green))
                }
            }
        }
    }

    private var invoiceSection: some View {
        Section("Invoices") {
            if outstanding > 0 {
                LabeledContent("Outstanding") {
                    Text(outstanding, format: .currency(code: "USD"))
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                }
            }
            if paid > 0 {
                LabeledContent("Total Paid") {
                    Text(paid, format: .currency(code: "USD"))
                        .foregroundStyle(.green)
                }
            }
            LabeledContent("Invoice Count", value: "\(clientInvoices.count)")
        }
    }
}
