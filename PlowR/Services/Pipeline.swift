import Foundation
import SwiftData

/// Where each client stands before they're a customer: a lead, quoted, or
/// lost. Worked out from what's on file, not typed in, so it can't go
/// stale: a client with no work, quote or invoice yet is a lead; one sent a
/// proposal is quoted; work booked or done (a visit scheduled, a stop on a
/// route, a job, an invoice) makes them a customer. Lost is the one the
/// business sets (and can undo); a proposal made after it puts them back in
/// Quoted. A quote still waiting for a reply after `followUpDays` is due a
/// follow-up.
enum Pipeline {
    enum Stage: Int, CaseIterable, Identifiable, Comparable {
        case lead, quoted, customer, lost

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .lead: "Lead"
            case .quoted: "Quoted"
            case .customer: "Customer"
            case .lost: "Lost"
            }
        }

        static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// How long a quote waits for a reply before it's due a follow-up.
    static let followUpDays = 5

    /// One client in the pipeline.
    struct Entry: Identifiable {
        let client: Client
        let stage: Stage
        /// Their latest proposal's total, when they've been quoted.
        var quoteTotal: Double?
        /// Days since a document was sent without a reply, when there is one.
        var waitingDays: Int?
        var id: UUID { client.id }

        /// Quoted, and waiting for a reply `followUpDays` or more.
        var needsFollowUp: Bool { stage == .quoted && (waitingDays ?? 0) >= Pipeline.followUpDays }
    }

    /// What's on file that decides the stages, gathered once.
    struct Facts {
        /// Clients with work booked or done: a visit scheduled or done, a
        /// stop on a route, a job in the Service Log, or an invoice.
        var withWork: Set<String> = []
        /// Each client's proposals (not invoices), newest first.
        var proposals: [String: [Proposal]] = [:]

        init(documents: [Proposal], records: [ServiceRecord], visits: [ScheduledVisit], stops: [RouteStop]) {
            withWork = Set(records.map(\.clientID))
                .union(documents.filter(\.isInvoice).map(\.clientID))
                .union(visits.filter { $0.status != .cancelled }.map(\.clientID))
                .union(stops.filter { !$0.isCustomStop }.map(\.clientID.uuidString))
            proposals = Dictionary(grouping: documents.filter { !$0.isInvoice }, by: \.clientID)
                .mapValues { $0.sorted { $0.createdAt > $1.createdAt } }
        }

        /// Everyone's, from the store.
        init(in context: ModelContext) {
            self.init(documents: (try? context.fetch(FetchDescriptor<Proposal>())) ?? [],
                      records: (try? context.fetch(FetchDescriptor<ServiceRecord>())) ?? [],
                      visits: (try? context.fetch(FetchDescriptor<ScheduledVisit>())) ?? [],
                      stops: (try? context.fetch(FetchDescriptor<RouteStop>())) ?? [])
        }

        /// One client's only: for their page, which redraws as it's typed in.
        init(of client: Client, in context: ModelContext) {
            let id = client.id.uuidString
            let uuid = client.id
            self.init(
                documents: (try? context.fetch(FetchDescriptor<Proposal>(predicate: #Predicate { $0.clientID == id }))) ?? [],
                records: ServiceLog.records(ofClient: id, in: context),
                visits: (try? context.fetch(FetchDescriptor<ScheduledVisit>(predicate: #Predicate { $0.clientID == id }))) ?? [],
                stops: (try? context.fetch(FetchDescriptor<RouteStop>(predicate: #Predicate { $0.clientID == uuid }))) ?? [])
        }
    }

    static func stage(of client: Client, facts: Facts) -> Stage {
        let id = client.id.uuidString
        if client.totalVisits > 0 || facts.withWork.contains(id) { return .customer }
        let newestProposal = facts.proposals[id]?.first?.createdAt
        // Lost, unless they've been sent a proposal since: back in Quoted.
        if let lostAt = client.lostAt, (newestProposal ?? .distantPast) <= lostAt { return .lost }
        return newestProposal != nil ? .quoted : .lead
    }

    /// Whether `client` is waiting to reply to what was sent them (an
    /// invoice or proposal): "Awaiting Response". The one rule for it.
    static func isAwaitingResponse(_ client: Client) -> Bool {
        guard let sent = client.lastMessageSentAt else { return false }
        return (client.clientRespondedAt ?? .distantPast) < sent
    }

    /// Days `client` has been awaiting a response, or nil if they aren't.
    static func waitingDays(_ client: Client, now: Date, calendar: Calendar = .current) -> Int? {
        guard isAwaitingResponse(client), let sent = client.lastMessageSentAt else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: sent),
                                       to: calendar.startOfDay(for: now)).day
    }

    /// When to remind the business to follow up on each quote still waiting:
    /// 9 AM on the day it's been waiting `followUpDays`, or the next 9 AM if
    /// that's passed. One per client. Worked out afresh from what's on file
    /// each time (FollowUpReminders), so a quote marked lost or answered, or
    /// a client booked, loses its reminder, and one still waiting is
    /// reminded again the next morning after the app was used.
    static func followUpDates(_ entries: [Entry], now: Date, calendar: Calendar = .current)
        -> [(client: Client, date: Date)] {
        entries.compactMap { entry in
            guard entry.stage == .quoted, let sent = entry.client.lastMessageSentAt,
                  isAwaitingResponse(entry.client),
                  let due = calendar.date(byAdding: .day, value: followUpDays, to: calendar.startOfDay(for: sent)),
                  var date = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: due) else { return nil }
            while date <= now {
                guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { return nil }
                date = next
            }
            return (entry.client, date)
        }
    }

    static func entry(for client: Client, facts: Facts, now: Date) -> Entry {
        let stage = stage(of: client, facts: facts)
        return Entry(client: client, stage: stage,
                     quoteTotal: facts.proposals[client.id.uuidString]?.first?.total,
                     waitingDays: waitingDays(client, now: now))
    }

    /// This operator's active clients who aren't customers yet, by stage:
    /// the longest-waiting first, then the newest.
    static func entries(_ clients: [Client], operatorID: String, facts: Facts, now: Date = .now) -> [Entry] {
        clients.filter { $0.operatorID == operatorID && $0.isActive }
            .map { entry(for: $0, facts: facts, now: now) }
            .filter { $0.stage != .customer }
            .sorted { ($0.waitingDays ?? -1, $0.client.createdAt) > ($1.waitingDays ?? -1, $1.client.createdAt) }
    }

    /// Marks a lead or quote lost, or (`lost` false) reopens it.
    static func setLost(_ lost: Bool, for client: Client, in context: ModelContext, now: Date = .now) {
        client.lostAt = lost ? now : nil
        try? context.save()
    }
}
