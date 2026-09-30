import SwiftUI
import SwiftData

struct ClientStatsView: View {
    @Environment(AuthManager.self) private var authManager
    @Query private var allClients: [Client]
    @Query private var allProposals: [Proposal]
    @Query private var profiles: [BusinessProfile]

    @State private var shareItem: IdentifiableURL? = nil

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

    // MARK: - Monthly Revenue

    private struct MonthBucket: Identifiable {
        let id: String // "YYYY-MM"
        let label: String
        let revenue: Double
        let outstanding: Double
    }

    private static let monthKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private var monthlyBuckets: [MonthBucket] {
        let cal = Calendar.current
        let myInvoices = allProposals.filter { $0.operatorID == authManager.userID && $0.isInvoice }
        var map: [String: (rev: Double, out: Double)] = [:]

        for proposal in myInvoices {
            let refDate = proposal.invoicePaidAt ?? proposal.invoiceSentAt ?? proposal.createdAt
            let comps = cal.dateComponents([.year, .month], from: refDate)
            guard let year = comps.year, let month = comps.month else { continue }
            let key = String(format: "%04d-%02d", year, month)
            var bucket = map[key] ?? (rev: 0, out: 0)
            if proposal.invoicePaidAt != nil { bucket.rev += proposal.total }
            else { bucket.out += proposal.total }
            map[key] = bucket
        }

        return map.sorted { $0.key > $1.key }.prefix(12).compactMap { key, vals in
            guard let date = Self.monthKeyFormatter.date(from: key) else { return nil }
            let label = date.formatted(.dateTime.month(.abbreviated).year())
            return MonthBucket(id: key, label: label, revenue: vals.rev, outstanding: vals.out)
        }
    }

    var body: some View {
        List {
            summarySection
            if !monthlyBuckets.isEmpty { monthlyRevenueSection }
            activitySection
            if !inactiveClients.isEmpty { inactiveSection }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    shareItem = buildReportURL()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(url: item.url)
        }
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

    private var monthlyRevenueSection: some View {
        let maxTotal = monthlyBuckets.map { $0.revenue + $0.outstanding }.max() ?? 1
        return Section {
            ForEach(monthlyBuckets) { bucket in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(bucket.label)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            if bucket.revenue > 0 {
                                Text(bucket.revenue, format: .currency(code: "USD").precision(.fractionLength(0)))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.green)
                            }
                            if bucket.outstanding > 0 {
                                Text(bucket.outstanding, format: .currency(code: "USD").precision(.fractionLength(0)))
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    HStack(spacing: 2) {
                        let revRatio = CGFloat(bucket.revenue / maxTotal)
                        let outRatio = CGFloat(bucket.outstanding / maxTotal)
                        if revRatio > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.green)
                                .frame(width: max(revRatio * 200, 4), height: 6)
                        }
                        if outRatio > 0 {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.orange.opacity(0.7))
                                .frame(width: max(outRatio * 200, 4), height: 6)
                        }
                        Spacer()
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Revenue by Month")
        } footer: {
            HStack(spacing: 16) {
                Label("Collected", systemImage: "square.fill").foregroundStyle(.green)
                Label("Outstanding", systemImage: "square.fill").foregroundStyle(.orange)
            }
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
                StatusChip("\(client.totalVisits) visit\(client.totalVisits == 1 ? "" : "s")", color: .blue)
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

    private func buildReportURL() -> IdentifiableURL? {
        let profile = profiles.first { $0.operatorID == authManager.userID }
        let myProposals = allProposals.filter { $0.operatorID == authManager.userID }
        let data = PDFGenerator.generateSeasonReport(
            clients: myClients,
            proposals: myProposals,
            profile: profile
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PlowR_Season_Report.pdf")
        guard (try? data.write(to: url)) != nil else { return nil }
        return IdentifiableURL(url: url)
    }
}

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
