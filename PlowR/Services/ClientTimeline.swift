import Foundation
import SwiftData

/// Everything that's happened with a client, and what's coming, in one list:
/// jobs done (the Service Log), visits ahead or missed, quotes and invoices
/// (made, sent, paid) and photos, newest first. It was spread over the
/// client's page, their Service History, Documents, the Schedule and the
/// photo gallery.
enum ClientTimeline {
    struct Event: Identifiable, Equatable {
        let id: String
        let date: Date
        let kind: ClientTimelineKind
        let title: String
        var detail: String = ""
        var amount: Double?
    }

    /// The client's events, newest first. A visit completed is its job, not
    /// a second event; a visit not done by today is "missed".
    static func events(for client: Client, now: Date = .now, calendar: Calendar = .current,
                       in context: ModelContext) -> [Event] {
        let id = client.id.uuidString
        var events: [Event] = []

        for record in ServiceLog.records(ofClient: id, in: context) {
            let names = record.lines.map(\.name)
            events.append(Event(id: "job-\(record.id)", date: record.performedAt, kind: .job(recordID: record.id),
                                title: names.isEmpty ? "Job" : names.formatted(.list(type: .and)),
                                detail: record.routeName.isEmpty ? "" : "On \(record.routeName)",
                                amount: ServiceLog.total(of: record)))
        }

        let visits = (try? context.fetch(FetchDescriptor<ScheduledVisit>(
            predicate: #Predicate { $0.clientID == id }))) ?? []
        let today = calendar.startOfDay(for: now)
        for visit in visits {
            let reason = visit.visitReason.isEmpty ? "Visit" : visit.visitReason
            let kind: ClientTimelineKind? = switch visit.status {
            case .completed: nil
            case .skipped: .skippedVisit
            case .cancelled: .cancelledVisit
            case .scheduled: visit.scheduledDate >= today ? .upcomingVisit : .missedVisit
            }
            guard let kind else { continue }
            events.append(Event(id: "visit-\(visit.id)", date: visit.scheduledDate, kind: kind, title: reason))
        }

        let documents = (try? context.fetch(FetchDescriptor<Proposal>(
            predicate: #Predicate { $0.clientID == id }))) ?? []
        for document in documents {
            let number = document.invoiceNumber
            if document.isInvoice {
                events.append(Event(id: "made-\(document.id)", date: document.createdAt,
                                    kind: .invoiceMade(documentID: document.id), title: "Invoice \(number)",
                                    amount: document.total))
                if let sent = document.invoiceSentAt {
                    events.append(Event(id: "sent-\(document.id)", date: sent,
                                        kind: .invoiceSent(documentID: document.id), title: "Sent \(number)"))
                }
                // Each payment on the day it came; paid in full, the invoice
                // is marked paid, with the amount only when no payments show it.
                for payment in document.sortedPayments {
                    events.append(Event(id: "payment-\(payment.id)", date: payment.receivedAt,
                                        kind: .payment(documentID: document.id), title: "Payment on \(number)",
                                        detail: [payment.method, payment.note].filter { !$0.isEmpty }
                                            .joined(separator: " · "),
                                        amount: payment.amount))
                }
                if let paid = document.invoicePaidAt {
                    events.append(Event(id: "paid-\(document.id)", date: paid,
                                        kind: .invoicePaid(documentID: document.id), title: "Paid \(number)",
                                        amount: document.sortedPayments.isEmpty ? document.total : nil))
                }
            } else {
                events.append(Event(id: "quote-\(document.id)", date: document.createdAt,
                                    kind: .quote(documentID: document.id), title: "Proposal", amount: document.total))
            }
        }

        let photos = (try? context.fetch(FetchDescriptor<StopPhoto>(
            predicate: #Predicate { $0.clientID == id }))) ?? []
        for (day, onDay) in Dictionary(grouping: photos, by: { calendar.startOfDay(for: $0.takenAt) }) {
            let latest = onDay.map(\.takenAt).max() ?? day
            events.append(Event(id: "photos-\(Int(day.timeIntervalSinceReferenceDate))", date: latest,
                                kind: .photos(count: onDay.count),
                                title: "\(onDay.count) photo\(onDay.count == 1 ? "" : "s")"))
        }

        return events.sorted { $0.date != $1.date ? $0.date > $1.date : $0.id < $1.id }
    }
}

/// What a timeline event is.
enum ClientTimelineKind: Equatable {
    case job(recordID: UUID)
    case upcomingVisit, missedVisit, skippedVisit, cancelledVisit
    case quote(documentID: UUID)
    case invoiceMade(documentID: UUID), invoiceSent(documentID: UUID), invoicePaid(documentID: UUID)
    case payment(documentID: UUID)
    case photos(count: Int)
}
