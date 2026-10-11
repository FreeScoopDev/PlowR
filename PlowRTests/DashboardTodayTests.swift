import Foundation
import Testing
@testable import PlowR

/// The Dashboard's first things: which route leads Today, and what's
/// waiting on the business, in order.
@MainActor
struct DashboardTodayTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func route(_ name: String, createdDaysAgo days: Double) -> PlowRoute {
        let route = PlowRoute(name: name, operatorID: "op")
        route.createdAt = now.addingTimeInterval(-days * 86_400)
        return route
    }

    @Test func theRouteRunMostRecentlyLeads() {
        let monday = route("Monday", createdDaysAgo: 30)
        let tuesday = route("Tuesday", createdDaysAgo: 1)
        let lastRuns = [monday.id.uuidString: now.addingTimeInterval(-3_600),
                        tuesday.id.uuidString: now.addingTimeInterval(-86_400)]
        #expect(DashboardToday.leadRoute([tuesday, monday], lastRuns: lastRuns) === monday)
    }

    /// A route that's been run beats a newer one that hasn't.
    @Test func aRunRouteBeatsANewerOneNeverRun() {
        let old = route("Old", createdDaysAgo: 60)
        let new = route("New", createdDaysAgo: 0)
        let lastRuns = [old.id.uuidString: now.addingTimeInterval(-7 * 86_400)]
        #expect(DashboardToday.leadRoute([new, old], lastRuns: lastRuns) === old)
    }

    @Test func withNoRunsTheNewestLeads() {
        let old = route("Old", createdDaysAgo: 60)
        let new = route("New", createdDaysAgo: 2)
        #expect(DashboardToday.leadRoute([old, new], lastRuns: [:]) === new)
    }

    @Test func noRoutesNoLead() {
        #expect(DashboardToday.leadRoute([], lastRuns: [:]) == nil)
    }

    /// Money late first, then money to bill, to send, to chase, then records
    /// to check; nothing with a count of zero.
    @Test func whatNeedsYouIsInOrderAndOnlyWhatsThere() {
        let items = DashboardToday.attention(overdue: (2, 640), paymentsDue: (0, 0), readyToSend: (3, 300),
                                             followUps: 1, billedTwice: 0, overpaid: 1)
        #expect(items.map(\.kind) == [.overdue, .readyToSend, .followUps, .overpaid])
        #expect(items.first?.amount == 640)
        #expect(items.first?.title == "2 invoices overdue")
    }

    @Test func nothingWaitingIsAnEmptyList() {
        #expect(DashboardToday.attention(overdue: (0, 0), paymentsDue: (0, 0), readyToSend: (0, 0),
                                         followUps: 0, billedTwice: 0, overpaid: 0).isEmpty)
    }

    @Test func oneOfEachReadsInTheSingular() {
        let items = DashboardToday.attention(overdue: (1, 10), paymentsDue: (1, 10), readyToSend: (1, 10),
                                             followUps: 1, billedTwice: 1, overpaid: 1)
        #expect(items.map(\.title) == ["1 invoice overdue", "1 contract payment due", "1 invoice ready to send",
                                       "1 quote to follow up", "1 contract payment billed twice",
                                       "1 invoice paid more than its total"])
    }
}

/// The plan and the day's run decide the Today card's button.
@MainActor
struct DashboardLeadStateTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// On the free tier only the oldest route runs: it leads even when a
    /// newer one was run more recently (during Pro).
    @Test func theFreeRouteLeadsOnTheFreeTier() {
        let oldest = PlowRoute(name: "Oldest", operatorID: "op")
        oldest.createdAt = now.addingTimeInterval(-90 * 86_400)
        let newer = PlowRoute(name: "Newer", operatorID: "op")
        newer.createdAt = now.addingTimeInterval(-10 * 86_400)
        let lastRuns = [newer.id.uuidString: now.addingTimeInterval(-3_600)]
        #expect(DashboardToday.leadRoute([oldest, newer], lastRuns: lastRuns, canStart: { $0 === oldest }) === oldest)
        // Read only, nothing can start: still the day's route, so the card shows it.
        #expect(DashboardToday.leadRoute([oldest, newer], lastRuns: lastRuns, canStart: { _ in false }) === newer)
    }

    @Test func notRunTodayIsReady() {
        let yesterday = now.addingTimeInterval(-86_400)
        #expect(DashboardToday.leadState(done: 5, total: 5, isDone: true, lastRun: yesterday, canStart: true,
                                         now: now) == .ready)
        #expect(DashboardToday.leadState(done: 0, total: 5, isDone: false, lastRun: nil, canStart: true,
                                         now: now) == .ready)
    }

    @Test func runTodayIsDoneOrPartlyDone() {
        let earlier = now.addingTimeInterval(-600)
        #expect(DashboardToday.leadState(done: 5, total: 5, isDone: true, lastRun: earlier, canStart: true,
                                         now: now) == .doneToday)
        #expect(DashboardToday.leadState(done: 3, total: 5, isDone: false, lastRun: earlier, canStart: true,
                                         now: now) == .partlyDone(done: 3, total: 5))
    }

    @Test func aRouteThePlanWontStartIsLocked() {
        #expect(DashboardToday.leadState(done: 0, total: 5, isDone: false, lastRun: nil, canStart: false,
                                         now: now) == .locked)
    }

    /// Contract payments due add up to the cent, in ContractInstallments.
    @Test func paymentsDueAddUpToTheCent() {
        let contract = Contract(name: "Season", startDate: now, endDate: now, operatorID: "op")
        let due = (0..<3).map {
            (contract: contract, installment: ContractInstallments.Installment(index: $0 + 1, date: now, amount: 0.1))
        }
        #expect(ContractInstallments.amountDue(due) == 0.3)
    }
}
