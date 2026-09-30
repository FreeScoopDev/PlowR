import SwiftUI
import SwiftData

/// A client's timeline (ClientTimeline): jobs, visits, quotes, invoices and
/// photos, newest first, by month. Jobs and documents open when tapped.
struct ClientTimelineView: View {
    let client: Client

    @Environment(\.modelContext) private var modelContext
    @State private var events: [ClientTimeline.Event]?

    var body: some View {
        List {
            if let events {
                if events.isEmpty {
                    ContentUnavailableView("Nothing Yet", systemImage: "clock",
                                           description: Text("Jobs, visits, invoices and photos for \(client.name) will show here."))
                } else {
                    ForEach(months(of: events), id: \.month) { group in
                        Section(group.month.formatted(.dateTime.month(.wide).year())) {
                            ForEach(group.events) { row($0) }
                        }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .navigationTitle("Timeline")
        .navigationBarTitleDisplayMode(.inline)
        .task { events = ClientTimeline.events(for: client, in: modelContext) }
    }

    private func months(of events: [ClientTimeline.Event]) -> [(month: Date, events: [ClientTimeline.Event])] {
        let calendar = Calendar.current
        var groups: [(month: Date, events: [ClientTimeline.Event])] = []
        for event in events {
            let month = calendar.dateInterval(of: .month, for: event.date)?.start ?? event.date
            if groups.last?.month == month {
                groups[groups.count - 1].events.append(event)
            } else {
                groups.append((month, [event]))
            }
        }
        return groups
    }

    @ViewBuilder
    private func row(_ event: ClientTimeline.Event) -> some View {
        let content = HStack(spacing: 12) {
            IconBadge(systemImage: symbol(event.kind), color: color(event.kind), size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(subtitle(event)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let amount = event.amount {
                Text(amount, format: .currency(code: "USD")).font(.subheadline).monospacedDigit()
                    .foregroundStyle(event.kind.isPaid ? .green : .primary)
            }
        }
        switch event.kind {
        case .job(let id):
            if let record = try? modelContext.fetch(FetchDescriptor<ServiceRecord>()).first(where: { $0.id == id }) {
                NavigationLink { ServiceRecordDetailView(record: record, client: client) } label: { content }
            } else { content }
        case .quote(let id), .invoiceMade(let id), .invoiceSent(let id), .invoicePaid(let id):
            if let document = try? modelContext.fetch(FetchDescriptor<Proposal>()).first(where: { $0.id == id }) {
                NavigationLink { ProposalDetailView(proposal: document) } label: { content }
            } else { content }
        case .photos:
            NavigationLink { ClientPhotoGalleryView(client: client) } label: { content }
        default:
            content
        }
    }

    private func subtitle(_ event: ClientTimeline.Event) -> String {
        let when = event.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let what: String = switch event.kind {
        case .job: "Job done"
        case .upcomingVisit: "Scheduled"
        case .missedVisit: "Scheduled, not marked done"
        case .skippedVisit: "Skipped"
        case .cancelledVisit: "Cancelled"
        case .quote: "Proposal made"
        case .invoiceMade: "Invoice made"
        case .invoiceSent: "Invoice sent"
        case .invoicePaid: "Invoice paid"
        case .photos: "Photos taken"
        }
        return [what, when, event.detail].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func symbol(_ kind: ClientTimelineKind) -> String {
        switch kind {
        case .job: "checkmark.circle.fill"
        case .upcomingVisit: "calendar"
        case .missedVisit: "calendar.badge.exclamationmark"
        case .skippedVisit: "arrow.right.circle"
        case .cancelledVisit: "xmark.circle"
        case .quote: "doc.text"
        case .invoiceMade: "doc.badge.arrow.up"
        case .invoiceSent: "paperplane.fill"
        case .invoicePaid: "dollarsign.circle.fill"
        case .photos: "photo.on.rectangle.angled"
        }
    }

    // Status colours as elsewhere: green done or paid, orange outstanding or
    // missed, red cancelled.
    private func color(_ kind: ClientTimelineKind) -> Color {
        switch kind {
        case .job, .invoicePaid: .green
        case .upcomingVisit, .quote, .invoiceMade: .blue
        case .missedVisit, .skippedVisit, .invoiceSent: .orange
        case .cancelledVisit: .red
        case .photos: .teal
        }
    }
}

private extension ClientTimelineKind {
    var isPaid: Bool { if case .invoicePaid = self { true } else { false } }
}
