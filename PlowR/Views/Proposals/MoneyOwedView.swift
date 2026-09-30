import SwiftData
import SwiftUI

/// Money owed, by how late it is (MoneyOwed): the total at each age, then
/// each client who owes, the latest payers first. A client opens their
/// invoices with a balance.
struct MoneyOwedView: View {
    @Environment(AuthManager.self) private var authManager
    @Query private var allProposals: [Proposal]

    private var summary: MoneyOwed.Summary {
        MoneyOwed.summary(allProposals, operatorID: authManager.userID)
    }

    var body: some View {
        let summary = summary
        List {
            if summary.clients.isEmpty {
                ContentUnavailableView("Nothing Owed", systemImage: "checkmark.seal",
                                       description: Text("Every invoice is paid."))
            } else {
                Section {
                    LabeledContent("Total Owed") {
                        Text(summary.total, format: .currency(code: "USD")).fontWeight(.semibold)
                    }
                    ForEach(MoneyOwed.Age.allCases) { age in
                        LabeledContent(age.title) {
                            Text(summary.byAge[age] ?? 0, format: .currency(code: "USD"))
                                .foregroundStyle((summary.byAge[age] ?? 0) > 0 ? color(age) : .secondary)
                        }
                    }
                } footer: {
                    Text("Late counts from each invoice's due date. Drafts, and invoices with no due date, aren't late.")
                }
                Section("By Client") {
                    ForEach(summary.clients) { client in
                        NavigationLink {
                            List(client.invoices) { invoice in
                                NavigationLink { ProposalDetailView(proposal: invoice) } label: {
                                    ProposalRowView(proposal: invoice)
                                }
                            }
                            .navigationTitle(client.name)
                            .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(client.name)
                                    Text(client.invoices.count == 1 ? "1 invoice" : "\(client.invoices.count) invoices")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(client.owed, format: .currency(code: "USD")).fontWeight(.semibold)
                                    if client.oldest != .notDue {
                                        StatusChip(client.oldest.title, color: color(client.oldest))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Money Owed")
        .navigationBarTitleDisplayMode(.inline)
    }

    // Outstanding is orange, overdue red (the status colours).
    private func color(_ age: MoneyOwed.Age) -> Color {
        age == .notDue ? .orange : .red
    }
}
