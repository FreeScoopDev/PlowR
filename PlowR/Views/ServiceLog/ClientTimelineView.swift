import SwiftUI
import SwiftData

/// A client's timeline (ClientTimeline): jobs, visits, quotes, invoices,
/// texts sent and photos, newest first, by month. Jobs and documents open when tapped.
struct ClientTimelineView: View {
    let client: Client

    @Environment(\.modelContext) private var modelContext
    @State private var events: [ClientTimeline.Event]?

    var body: some View {
        List {
            if let events {
                if events.isEmpty {
                    ContentUnavailableView("Nothing Yet", systemImage: "clock",
                                           description: Text("Jobs, visits, invoices, texts and photos for \(client.name) will show here."))
                    .listRowBackground(Color.clear)   // the empty state sits on the page
                } else {
                    ForEach(months(of: events), id: \.month) { group in
                        Section(group.month.formatted(.dateTime.month(.wide).year())) {
                            ForEach(group.events) { row($0) }
                        }
                        .listRowBackground(PlowRColor.surface)
                    }
                    .listRowBackground(PlowRColor.surface)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .plowRGrouped()
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
            IconBadge(systemImage: symbol(event.kind), status: status(event.kind), size: 32)
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
        case .quote(let id), .invoiceMade(let id), .invoiceSent(let id), .invoicePaid(let id), .payment(let id):
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
        // A text's time too: "did I tell them we were coming?" is about when.
        let when = event.kind == .text
            ? event.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            : event.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
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
        case .payment: "Payment received"
        case .text: ""
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
        case .payment: "banknote"
        case .text: "message.fill"
        case .photos: "photo.on.rectangle.angled"
        }
    }

    /// Done green, needing attention amber, cancelled grey; anything else
    /// the brand (`PlowRColor.Status`).
    private func status(_ kind: ClientTimelineKind) -> PlowRColor.Status? {
        switch kind {
        case .job, .invoicePaid, .payment: .done
        case .upcomingVisit, .quote, .invoiceMade, .text, .photos: nil
        case .missedVisit, .skippedVisit, .invoiceSent: .owed
        case .cancelledVisit: .void
        }
    }
}

private extension ClientTimelineKind {
    var isPaid: Bool {
        switch self {
        case .invoicePaid, .payment: true
        default: false
        }
    }
}
