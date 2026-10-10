import SwiftData
import SwiftUI

/// Clients who aren't customers yet (Pipeline): quotes due a follow-up
/// first, then leads, quotes waiting, and those marked lost. Swipe to mark
/// one lost or reopen it; tap to open the client.
struct PipelineView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.access) private var access
    @State private var gate: ProGate?
    @Query private var allClients: [Client]
    @Query private var allProposals: [Proposal]
    @Query private var allRecords: [ServiceRecord]
    @Query private var allVisits: [ScheduledVisit]
    @Query private var allStops: [RouteStop]

    private var entries: [Pipeline.Entry] {
        Pipeline.entries(allClients, operatorID: authManager.userID,
                         facts: Pipeline.Facts(documents: allProposals, records: allRecords, visits: allVisits,
                                               stops: allStops))
    }

    var body: some View {
        let entries = entries
        let followUp = entries.filter(\.needsFollowUp)
        List {
            if entries.isEmpty {
                ContentUnavailableView("No Leads", systemImage: "person.crop.circle.badge.plus",
                                       description: Text("Clients with no work booked or done yet show here: new leads, and those you've sent a proposal."))
            }
            section("Follow Up", followUp,
                    footer: "Sent a proposal \(Pipeline.followUpDays) or more days ago with no reply yet.")
            section("Leads", entries.filter { $0.stage == .lead }, footer: "No proposal or work yet.")
            section("Quoted", entries.filter { $0.stage == .quoted && !$0.needsFollowUp },
                    footer: "Sent a proposal. Booking them (a visit or a route stop), a job or an invoice makes them a customer.")
            section("Lost", entries.filter { $0.stage == .lost }, footer: "Swipe to reopen one.")
        }
        .navigationTitle("Pipeline")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let blocked = ProGate.proFeature("The Request Link", access) {
                    Button { gate = blocked } label: {
                        Label("Request Link", systemImage: "link")
                    }
                } else {
                    NavigationLink { RequestLinkView() } label: {
                        Label("Request Link", systemImage: "link")
                    }
                }
            }
        }
        .proGateSheet($gate)
    }

    @ViewBuilder
    private func section(_ title: String, _ entries: [Pipeline.Entry], footer: String) -> some View {
        if !entries.isEmpty {
            Section {
                ForEach(entries) { entry in
                    NavigationLink { EditClientView(client: entry.client) } label: { row(entry) }
                        .swipeActions {
                            if entry.stage == .lost {
                                Button("Reopen") { Pipeline.setLost(false, for: entry.client, in: modelContext) }
                                    .tint(.blue)
                            } else {
                                Button("Lost") { Pipeline.setLost(true, for: entry.client, in: modelContext) }
                                    .tint(.gray)
                            }
                        }
                }
            } header: {
                Text("\(title) (\(entries.count))")
            } footer: {
                Text(footer)
            }
        }
    }

    private func row(_ entry: Pipeline.Entry) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.client.name)
                Text(detail(entry)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let total = entry.quoteTotal {
                Text(total, format: .currency(code: "USD")).font(.subheadline)
            }
            if entry.needsFollowUp, let days = entry.waitingDays {
                StatusChip("\(days)d", systemImage: "clock", color: .orange)
            }
        }
    }

    private func detail(_ entry: Pipeline.Entry) -> String {
        switch entry.stage {
        case .lost:
            entry.client.lostAt.map { "Lost \($0.formatted(.dateTime.month(.abbreviated).day()))" } ?? "Lost"
        case .quoted:
            if let days = entry.waitingDays {
                days == 0 ? "Sent today, no reply yet" : "No reply for \(days) day\(days == 1 ? "" : "s")"
            } else if entry.client.lastMessageSentAt != nil {
                "Replied"
            } else {
                "Proposal not sent yet"
            }
        default:
            "Added \(entry.client.createdAt.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }
}
