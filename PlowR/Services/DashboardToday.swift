import Foundation

/// What the Dashboard puts first (Joe, 2026-10-11: today first). Which route
/// leads the day, and what needs the business's attention, in the order it
/// matters. Kept out of the view so the choices are tested.
enum DashboardToday {
    /// The route that leads Today: the one run most recently (crews repeat
    /// their routes), or the newest when none has been run. Nil with none.
    static func leadRoute(_ routes: [PlowRoute], lastRuns: [String: Date]) -> PlowRoute? {
        routes.max { a, b in
            let ra = lastRuns[a.id.uuidString], rb = lastRuns[b.id.uuidString]
            switch (ra, rb) {
            case let (x?, y?): return x < y
            case (nil, _?): return true
            case (_?, nil): return false
            case (nil, nil): return a.createdAt < b.createdAt
            }
        }
    }

    /// The things waiting, in order, leaving out any with nothing in it.
    static func attention(overdue: (count: Int, amount: Double),
                          paymentsDue: (count: Int, amount: Double),
                          readyToSend: (count: Int, amount: Double),
                          followUps: Int, billedTwice: Int, overpaid: Int) -> [DashboardAttention] {
        let all = [
            DashboardAttention(kind: .overdue, count: overdue.count, amount: overdue.amount),
            DashboardAttention(kind: .paymentsDue, count: paymentsDue.count, amount: paymentsDue.amount),
            DashboardAttention(kind: .readyToSend, count: readyToSend.count, amount: readyToSend.amount),
            DashboardAttention(kind: .followUps, count: followUps, amount: nil),
            DashboardAttention(kind: .billedTwice, count: billedTwice, amount: nil),
            DashboardAttention(kind: .overpaid, count: overpaid, amount: nil)
        ]
        return all.filter { $0.count > 0 }
    }
}

/// One thing waiting on the business, with how many and how much.
struct DashboardAttention: Identifiable, Equatable {
    enum Kind: Int, CaseIterable {
        // In the order shown: money late first, then money to bill, then
        // money to chase, then records to check.
        case overdue, paymentsDue, readyToSend, followUps, billedTwice, overpaid
    }
    let kind: Kind
    let count: Int
    let amount: Double?
    var id: Kind { kind }

    var title: String {
        switch kind {
        case .overdue: count == 1 ? "1 invoice overdue" : "\(count) invoices overdue"
        case .paymentsDue: count == 1 ? "1 contract payment due" : "\(count) contract payments due"
        case .readyToSend: count == 1 ? "1 invoice ready to send" : "\(count) invoices ready to send"
        case .followUps: count == 1 ? "1 quote to follow up" : "\(count) quotes to follow up"
        case .billedTwice: count == 1 ? "1 contract payment billed twice" : "\(count) contract payments billed twice"
        case .overpaid: count == 1 ? "1 invoice paid more than its total" : "\(count) invoices paid more than their total"
        }
    }
}
