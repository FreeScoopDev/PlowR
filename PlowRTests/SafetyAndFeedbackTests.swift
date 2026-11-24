import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Actions that change records ask first and say what they did: deleting a
/// scheduled visit (one or the rest of its series), Mark Paid's prompt, a
/// PDF that couldn't be written, and Get Started brought back after Hide.
@MainActor
struct SafetyAndFeedbackTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    // MARK: - Deleting a visit

    /// A weekly series of `count` visits for the harness's client, a week apart.
    private func series(_ h: Harness, count: Int, from start: Date) -> [ScheduledVisit] {
        let id = UUID().uuidString
        return (0..<count).map { week in
            let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                       clientAddress: h.client.address,
                                       scheduledDate: start.addingTimeInterval(Double(week) * 7 * 86_400))
            visit.isRecurring = true
            visit.recurrenceType = .weekly
            visit.seriesID = id
            h.context.insert(visit)
            return visit
        }
    }

    private func visits(_ h: Harness) throws -> [ScheduledVisit] {
        try h.context.fetch(FetchDescriptor<ScheduledVisit>(sortBy: [SortDescriptor(\.scheduledDate)]))
    }

    @Test func deletingOneVisitOfASeriesLeavesTheRest() throws {
        let h = try Harness(stopCount: 0)
        let all = series(h, count: 4, from: h.clock)
        VisitDeletion.delete(all[1], scope: .thisVisit, among: all, in: h.context)
        try h.context.save()
        let left = try visits(h)
        #expect(left.map(\.id) == [all[0].id, all[2].id, all[3].id])
        #expect(left.allSatisfy { $0.recurrenceEndDate == nil })              // the series goes on
    }

    @Test func deletingThisAndFutureEndsTheSeriesThere() throws {
        let h = try Harness(stopCount: 0)
        let calendar = Calendar.current
        let all = series(h, count: 5, from: h.clock)
        all[3].status = .completed                                            // a record: kept
        all[4].status = .skipped
        let other = series(h, count: 2, from: h.clock)                        // another series
        let everyone = all + other
        #expect(VisitDeletion.offersSeries(all[1], among: everyone))
        VisitDeletion.delete(all[1], scope: .thisAndFuture, among: everyone, in: h.context, calendar: calendar)
        try h.context.save()
        let left = try visits(h)
        #expect(Set(left.map(\.id)) == Set([all[0].id, all[3].id] + other.map(\.id)))
        // Completing the first doesn't add the deleted ones back.
        let end = try #require(all[0].recurrenceEndDate)
        #expect(calendar.startOfDay(for: end) < calendar.startOfDay(for: all[1].scheduledDate))
        #expect(all[0].continuation(among: left, calendar: calendar) == nil)
        #expect(other.allSatisfy { $0.recurrenceEndDate == nil })
    }

    @Test func deletingTheLastVisitOfASeriesEndsIt() throws {
        let h = try Harness(stopCount: 0)
        let calendar = Calendar.current
        let all = series(h, count: 2, from: h.clock)
        #expect(!VisitDeletion.offersSeries(all[1], among: all))              // the single "Delete Visit"
        let scope = VisitDeletion.singleDeleteScope(for: all[1], among: all)
        #expect(scope == .thisAndFuture)
        #expect(VisitDeletion.singleDeleteScope(for: all[0], among: all) == .thisVisit)   // not the last
        // Its dialog says the series ends, and points to Skip; the others don't.
        #expect(VisitDeletion.message(for: all[1], among: all).contains("the series ends here"))
        #expect(VisitDeletion.message(for: all[1], among: all).contains("use Skip instead"))
        #expect(!VisitDeletion.message(for: all[0], among: all).contains("series ends"))
        let oneOff = ScheduledVisit(operatorID: "op", clientID: "c", clientName: "Pat", clientAddress: "",
                                    scheduledDate: h.clock)
        #expect(VisitDeletion.message(for: oneOff, among: all + [oneOff]) == "A deleted visit can't be brought back.")
        VisitDeletion.delete(all[1], scope: scope, among: all, in: h.context, calendar: calendar)
        try h.context.save()
        let left = try visits(h)
        #expect(left.map(\.id) == [all[0].id])
        // Completing the first doesn't add the deleted one back.
        #expect(all[0].continuation(among: left, calendar: calendar) == nil)
    }

    @Test func theSeriesChoiceIsOfferedOnlyWithVisitsStillToCome() throws {
        let h = try Harness(stopCount: 0)
        let all = series(h, count: 3, from: h.clock)
        #expect(VisitDeletion.offersSeries(all[0], among: all))
        #expect(!VisitDeletion.offersSeries(all[2], among: all))              // the last one
        all[2].status = .completed
        #expect(!VisitDeletion.offersSeries(all[1], among: all))              // only a record after it
        let oneOff = ScheduledVisit(operatorID: "op", clientID: "c", clientName: "Pat", clientAddress: "",
                                    scheduledDate: h.clock)
        oneOff.seriesID = all[0].seriesID                                    // not repeating: never a series
        #expect(!VisitDeletion.offersSeries(oneOff, among: all + [oneOff]))
    }

    @Test func theDeleteTitleNamesTheClientAndDay() throws {
        let h = try Harness(stopCount: 0)
        let visit = series(h, count: 1, from: h.clock)[0]
        let title = VisitDeletion.title(for: visit)
        #expect(title.hasPrefix("Delete Client 0's visit on "))
        #expect(title.contains(visit.scheduledDate.formatted(.dateTime.day())))
    }

    // MARK: - Mark Paid

    @Test func markPaidSaysWhatItWillRecord() throws {
        let h = try Harness(stopCount: 0)
        let bill = Proposal(operatorID: "op", client: h.client)
        bill.invoiceNumber = "INV-0042"
        bill.invoiceSentAt = h.clock
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: 1_250.5)
        h.context.insert(item)
        h.context.insert(bill)
        bill.lineItems = [item]
        #expect(MarkPaidPrompt.title(for: bill) == "Mark INV-0042 Paid?")
        #expect(MarkPaidPrompt.message(for: bill) == "Records a payment of \(Money.text(bill.balanceDue)) today.")
        #expect(MarkPaidPrompt.message(for: bill).contains("$1,250.50"))
        Payments.record(bill.balanceDue, method: "Cash", receivedAt: h.clock, on: bill, in: h.context, now: h.clock)
        #expect(MarkPaidPrompt.message(for: bill) == "Nothing is owed on it, so it's simply marked paid.")
        bill.invoiceNumber = ""
        #expect(MarkPaidPrompt.title(for: bill) == "Mark This Invoice Paid?")
    }

    // MARK: - Writing a file to share

    private struct DiskFull: LocalizedError {
        var errorDescription: String? { "There isn't enough space.\nFree some up and try again." }
    }

    @Test func aFileIsSharedOnlyOnceWritten() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShareFileTest-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let written = ShareFile.write(Data([1, 2, 3]), to: url)
        #expect((try? written.get()) == url)
        #expect(try Data(contentsOf: url) == Data([1, 2, 3]))

        let failed = ShareFile.write(Data([1]), to: url, kind: .pdf) { _, _ in throw DiskFull() }
        guard case .failure(let failure) = failed else {
            Issue.record("a failed write was offered to share")
            return
        }
        #expect(failure.title == "Couldn't Make the PDF")
        #expect(failure.message == "There isn't enough space. Free some up and try again.")    // one line
        #expect(ShareFile.failure(DiskFull(), kind: .file).title == "Couldn't Save the File")
    }

    // MARK: - Get Started

    @Test func showGetStartedIsOfferedOnlyWhileHiddenWithStepsLeft() {
        let stepsLeft = FirstRun.Checklist(profileDone: true, clientAdded: false, routeMade: false, invoiceSent: false,
                                           alertsUndecided: false)
        let allDone = FirstRun.Checklist(profileDone: true, clientAdded: true, routeMade: true, invoiceSent: true,
                                         alertsUndecided: false)
        #expect(FirstRun.offersShowAgain(completedSetup: true, hidden: true, checklist: stepsLeft))
        #expect(!FirstRun.offersShowAgain(completedSetup: true, hidden: false, checklist: stepsLeft))   // showing
        #expect(!FirstRun.offersShowAgain(completedSetup: true, hidden: true, checklist: allDone))     // nothing to show
        #expect(!FirstRun.offersShowAgain(completedSetup: false, hidden: true, checklist: stepsLeft))  // never set up here
    }

    @Test func showGetStartedClearsTheHiddenFlag() throws {
        let defaults = try #require(UserDefaults(suiteName: "SafetyAndFeedbackTests-\(UUID().uuidString)"))
        defaults.set(true, forKey: FirstRun.checklistHiddenKey("op"))
        defaults.set(true, forKey: FirstRun.checklistHiddenKey("other"))
        FirstRun.showChecklistAgain(operatorID: "op", defaults: defaults)
        #expect(!defaults.bool(forKey: FirstRun.checklistHiddenKey("op")))
        #expect(defaults.bool(forKey: FirstRun.checklistHiddenKey("other")))   // another business's stays
        // Home's one read of the flag (body, on appearing, when Settings closes).
        #expect(!FirstRun.isChecklistHidden(operatorID: "op", defaults: defaults))
        #expect(FirstRun.isChecklistHidden(operatorID: "other", defaults: defaults))
        // Home's Hide sets it again, for that business only.
        FirstRun.hideChecklist(operatorID: "op", defaults: defaults)
        #expect(FirstRun.isChecklistHidden(operatorID: "op", defaults: defaults))
        FirstRun.showChecklistAgain(operatorID: "other", defaults: defaults)
        FirstRun.hideChecklist(operatorID: "op", defaults: defaults)
        #expect(!FirstRun.isChecklistHidden(operatorID: "other", defaults: defaults))
    }

    @Test func theStoredChecklistMatchesHomes() throws {
        let h = try Harness(stopCount: 1)                                     // a client and a route for "op"
        let read = FirstRun.checklist(operatorID: "op", in: h.context, alertsUndecided: true)
        #expect(read == FirstRun.Checklist(profileDone: false, clientAdded: true, routeMade: true, invoiceSent: false,
                                           alertsUndecided: true))
        let nobody = FirstRun.checklist(operatorID: "someone else", in: h.context, alertsUndecided: false)
        #expect(!nobody.clientAdded && !nobody.routeMade)
    }
}
