import SwiftUI
import SwiftData

struct ClientStatsView: View {
    @Environment(AuthManager.self) private var authManager
    @Query private var allClients: [Client]
    @Query private var allProposals: [Proposal]

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == authManager.userID }
    }

    private var activeClients: [Client] {
        myClients.filter { $0.totalVisits > 0 }.sorted { $0.totalVisits > $1.totalVisits }
    }

    private var inactiveClients: [Client] {
        myClients.filter { $0.totalVisits == 0 }.sorted { $0.name < $1.name }
    }

    private var totalVisits: Int { myClients.reduce(0) { $0 + $1.totalVisits } }

    private var totalMinutes: Double { myClients.reduce(0) { $0 + $1.totalServiceMinutes } }

    private var totalRevenue: Double {
        allProposals
            .filter { $0.operatorID == authManager.userID && $0.invoicePaidAt != nil }
            .reduce(0) { $0 + $1.total }
    }

    private var totalOutstanding: Double {
        allProposals
            .filter { $0.operatorID == authManager.userID && $0.isInvoice && $0.invoicePaidAt == nil }
            .reduce(0) { $0 + $1.total }
    }

    private func outstanding(for client: Client) -> Double {
        allProposals
            .filter { $0.clientID == client.id.uuidString && $0.isInvoice && $0.invoicePaidAt == nil }
            .reduce(0) { $0 + $1.total }
    }

    var body: some View {
        List {
            summarySection
            activitySection
            if !inactiveClients.isEmpty { inactiveSection }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.large)
    }

    private var summarySection: some View {
        Section {
            HStack(spacing: 10) {
                summaryCard(
                    label: "Visits",
                    value: "\(totalVisits)",
                    icon: "checkmark.circle.fill",
                    color: .blue
                )
                summaryCard(
                    label: "Revenue",
                    value: totalRevenue == 0 ? "$0" : totalRevenue.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                    icon: "dollarsign.circle.fill",
                    color: .green
                )
                summaryCard(
                    label: "Outstanding",
                    value: totalOutstanding == 0 ? "$0" : totalOutstanding.formatted(.currency(code: "USD").precision(.fractionLength(0))),
                    icon: "exclamationmark.circle.fill",
                    color: totalOutstanding > 0 ? .red : .secondary
                )
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))

            if totalMinutes > 0 {
                let hours = Int(totalMinutes) / 60
                let mins = Int(totalMinutes) % 60
                let timeString = hours > 0 ? "\(hours)h \(mins)m" : "\(mins) min"
                LabeledContent("Total time on-site", value: timeString)
                    .font(.subheadline)
            }
        } header: {
            Text("Season Summary")
        } footer: {
            Text("Stats are recorded automatically when route stops are completed.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var activitySection: some View {
        if activeClients.isEmpty {
            Section("Clients by Activity") {
                Text("No service history recorded yet.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        } else {
            Section("Clients by Activity") {
                ForEach(activeClients) { client in
                    clientRow(client)
                }
            }
        }
    }

    private var inactiveSection: some View {
        Section("Never Serviced") {
            ForEach(inactiveClients) { client in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(client.name)
                            .font(.subheadline)
                        if !client.address.isEmpty {
                            Text(client.address)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("No visits")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func clientRow(_ client: Client) -> some View {
        let balance = outstanding(for: client)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.name)
                        .font(.subheadline.weight(.semibold))
                    if !client.address.isEmpty {
                        Text(client.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(client.totalVisits) visit\(client.totalVisits == 1 ? "" : "s")")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.85))
                    .clipShape(Capsule())
            }
            HStack(spacing: 12) {
                if let last = client.lastServiceDate {
                    Label(last.formatted(.dateTime.month(.abbreviated).day().year()), systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if client.averageServiceMinutes > 0 {
                    Label(String(format: "~%.0f min avg", client.averageServiceMinutes), systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if balance > 0 {
                Label(
                    balance.formatted(.currency(code: "USD")),
                    systemImage: "exclamationmark.circle.fill"
                )
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private func summaryCard(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
    }
}
