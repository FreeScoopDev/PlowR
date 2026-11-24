import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The Undo toast's center: deletes held back for the window and done when
/// it ends, Skip, and the Schedule's Complete taken back, or refused when
/// what they changed was changed since.
@MainActor
struct UndoCenterTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func center(_ h: Harness) -> UndoCenter {
        let center = UndoCenter(now: { h.clock }, sleep: nil, announce: { _ in })
        center.configure(context: h.context)
        return center
    }

    /// A center whose timer runs, on a sleep that moves the test's clock and returns at once.
    private func timedCenter(_ h: Harness) -> UndoCenter {
        let center = UndoCenter(now: { h.clock }, sleep: { h.clock += $0 }, announce: { _ in })
        center.configure(context: h.context)
        return center
    }

    @discardableResult
    private func visit(_ h: Harness, day: Int = 0) -> ScheduledVisit {
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address,
                                   scheduledDate: h.clock.addingTimeInterval(Double(day) * 86_400))
        h.context.insert(visit)
        return visit
    }

    /// A weekly series of `count` visits, a week apart.
    private func series(_ h: Harness, count: Int) -> [ScheduledVisit] {
        let id = UUID().uuidString
        return (0..<count).map { week in
            let visit = visit(h, day: week * 7)
            visit.isRecurring = true
            visit.recurrenceType = .weekly
            visit.seriesID = id
            return visit
        }
    }

    private func visits(_ h: Harness) throws -> [ScheduledVisit] {
        try h.context.fetch(FetchDescriptor<ScheduledVisit>(sortBy: [SortDescriptor(\.scheduledDate)]))
    }

    private func records(_ h: Harness) throws -> [ServiceRecord] {
        try h.context.fetch(FetchDescriptor<ServiceRecord>())
    }

    // MARK: - Pending deletes

    @Test func aPendingDeleteIsHiddenThenDoneWhenTheWindowEnds() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h), other = visit(h, day: 1)
        try h.context.save()
        center.delete(one, scope: .thisVisit, among: [one, other])
        #expect(center.isPendingDeletion(one))
        #expect(!center.isPendingDeletion(other))
        #expect(try visits(h).count == 2)                                       // not deleted yet
        #expect(center.offer?.title == "Deleted Client 0's visit")
        h.clock += UndoCenter.window
        center.endIfExpired()
        #expect(center.offer != nil)                                            // the window's last moment
        h.clock += 1
        center.endIfExpired()
        #expect(center.offer == nil)
        #expect(center.pendingDeletions.isEmpty)
        #expect(try visits(h).map(\.id) == [other.id])
        #expect(!h.context.hasChanges)                                          // saved
    }

    @Test func aNewOfferDoesThePendingDelete() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h), other = visit(h, day: 1)
        try h.context.save()
        center.delete(one, scope: .thisVisit, among: [one, other])
        center.skip(other)
        #expect(try visits(h).map(\.id) == [other.id])
        #expect(center.offer?.title == "Skipped Client 0")
        #expect(center.pendingDeletions.isEmpty)
    }

    // The center's own timer: it sleeps out the window, then ends the offer.
    @Test func theTimerDoesThePendingDeleteWhenTheWindowEnds() async throws {
        let h = try Harness(stopCount: 0)
        let center = timedCenter(h)
        let one = visit(h), other = visit(h, day: 1)
        try h.context.save()
        let start = h.clock
        center.delete(one, scope: .thisVisit, among: [one, other])
        let timer = try #require(center.expiry)
        await timer.value
        #expect(h.clock > start.addingTimeInterval(UndoCenter.window))         // it waited the window out
        #expect(center.offer == nil && center.pendingDeletions.isEmpty)
        #expect(try visits(h).map(\.id) == [other.id])
        #expect(!h.context.hasChanges)
    }

    // An offer's timer that wakes after a newer offer took its place leaves
    // the newer one alone (the `current.id == offer.id` guard, behind the
    // timer's cancellation). A's timer is held asleep until B is offered.
    @Test func anOldTimerLeavesANewerOfferAlone() async throws {
        let h = try Harness(stopCount: 0)
        let gate = SleepGate()
        let center = UndoCenter(now: { h.clock },
                                sleep: { seconds in
                                    await withCheckedContinuation { gate.waiting.append($0) }
                                    h.clock += seconds
                                },
                                announce: { _ in })
        center.configure(context: h.context)
        let a = visit(h), b = visit(h, day: 1)
        try h.context.save()
        center.delete(a, scope: .thisVisit, among: [a, b])
        let timerA = try #require(center.expiry)
        while gate.waiting.isEmpty { await Task.yield() }                               // A's timer is asleep
        h.clock += 3
        center.delete(b, scope: .thisVisit, among: [a, b])
        #expect(try visits(h).map(\.id) == [b.id])                             // A done when B replaced it
        gate.waiting.removeFirst().resume()                                              // A's timer wakes up
        await timerA.value
        #expect(center.isPendingDeletion(b))
        #expect(center.offer?.title == "Deleted Client 0's visit")
        #expect(try visits(h).map(\.id) == [b.id])                             // B still there
        center.discardAll()
        gate.waiting.forEach { $0.resume() }
    }

    // PlowRApp calls this when the scene goes to the background.
    @Test func goingToTheBackgroundDoesThePendingDelete() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        try h.context.save()
        center.delete(one, scope: .thisVisit, among: [one])
        center.sceneDidEnterBackground()
        #expect(try visits(h).isEmpty)
        #expect(center.offer == nil)
    }

    // Starting a route does a held-back delete first: a stop never claims
    // the visit (ServiceLog.visitForStop) and then loses it.
    @Test func startingARouteDoesThePendingDelete() throws {
        let h = try Harness(stopCount: 1)
        let center = center(h)
        let one = visit(h)
        try h.context.save()
        center.delete(one, scope: .thisVisit, among: [one])
        let store = ActiveRouteStore(defaults: h.defaults, surfaces: FakeRouteSurfaces(), undo: center,
                                     now: { h.clock })
        store.configure(context: h.context)
        store.start(h.route)
        #expect(center.offer == nil)
        #expect(try visits(h).isEmpty)
        let stop = try #require(store.currentStop)
        #expect(ServiceLog.visitForStop(stop, of: h.client, run: UUID(), on: h.clock, in: h.context) == nil)
    }

    @Test func undoingADeleteLeavesTheVisitUntouched() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        one.notes = "Gate code 12"
        try h.context.save()
        let id = one.persistentModelID
        center.delete(one, scope: .thisVisit, among: [one])
        #expect(center.undo(center.offer?.id) == .undone)
        #expect(!center.isPendingDeletion(one))
        #expect(!h.context.hasChanges)                                          // nothing changed, nothing to sync
        let left = try visits(h)
        #expect(left.count == 1 && left[0].persistentModelID == id && left[0].notes == "Gate code 12")
        // And the window ending later doesn't delete it.
        h.clock += 60
        center.endIfExpired()
        center.end()
        #expect(try visits(h).count == 1)
    }

    @Test func discardAllDropsThePendingDeleteWithoutDoingIt() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        try h.context.save()
        center.delete(one, scope: .thisVisit, among: [one])
        center.discardAll()
        #expect(center.offer == nil && center.pendingDeletions.isEmpty)
        center.end()
        #expect(try visits(h).count == 1)
    }

    @Test func aSeriesDeleteHoldsEveryVisitAndUndoBringsThemAllBack() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let all = series(h, count: 4)
        try h.context.save()
        center.delete(all[1], scope: .thisAndFuture, among: all)
        #expect(center.offer?.title == "Deleted 3 visits")
        #expect(all[1...].allSatisfy { center.isPendingDeletion($0) })
        #expect(!center.isPendingDeletion(all[0]))
        #expect(all[0].recurrenceEndDate == nil)                                // the series isn't ended yet
        #expect(center.undo() == .undone)
        #expect(try visits(h).map(\.id) == all.map(\.id))
        #expect(all.allSatisfy { $0.recurrenceEndDate == nil })
        #expect(!h.context.hasChanges)
    }

    @Test func aSeriesDeleteIsDoneWhenTheWindowEnds() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let all = series(h, count: 4)
        try h.context.save()
        center.delete(all[1], scope: .thisAndFuture, among: all)
        h.clock += UndoCenter.window + 1
        center.endIfExpired()
        #expect(try visits(h).map(\.id) == [all[0].id])
        let end = try #require(all[0].recurrenceEndDate)
        #expect(end < all[1].scheduledDate)
        #expect(all[0].continuation(among: [all[0]]) == nil)                    // doesn't grow back
    }

    // Deleted meanwhile by sync: skipped at commit, nothing traps.
    @Test func aVisitDeletedMeanwhileIsSkipped() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        try h.context.save()
        center.delete(one, scope: .thisVisit, among: [one])
        h.context.delete(one)
        try h.context.save()
        center.end()
        #expect(try visits(h).isEmpty)
    }

    // MARK: - Skip

    @Test func undoingSkipSchedulesItAgain() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        center.skip(one)
        #expect(one.status == .skipped)
        #expect(center.undo() == .undone)
        #expect(one.status == .scheduled)
    }

    // Deleted on another context (as sync does) and saved: the visit then
    // reads not deleted, but has no context.
    @Test func skipIsntUndoneAfterTheVisitWasDeletedElsewhere() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        try h.context.save()
        center.skip(one)
        try h.context.save()
        let elsewhere = ModelContext(h.container)
        elsewhere.autosaveEnabled = false
        let id = one.id
        let copy = try #require(try elsewhere.fetch(FetchDescriptor<ScheduledVisit>(predicate: #Predicate { $0.id == id })).first)
        elsewhere.delete(copy)
        try elsewhere.save()
        #expect(center.undo() == .changed)
    }

    @Test func skipIsntUndoneAfterTheStatusChanged() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        center.skip(one)
        one.status = .completed                                                 // another device
        #expect(center.undo() == .changed)
        #expect(one.status == .completed)
        #expect(center.offer == nil)
    }

    // MARK: - Complete

    @Test func undoingCompleteDeletesTheRecordItMade() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        try h.context.save()
        center.complete(one, among: [one], now: h.clock)
        #expect(one.status == .completed && one.serviceLogged)
        #expect(try records(h).count == 1)
        #expect(center.offer?.title == "Completed Client 0")
        #expect(center.undo() == .undone)
        #expect(one.status == .scheduled && one.completedAt == nil && !one.serviceLogged)
        #expect(try records(h).isEmpty)
    }

    @Test func undoingCompletePutsAnExistingRecordBack() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h, day: -1)
        let record = ServiceRecord(operatorID: "op", sourceKey: ServiceLog.visitKey(one.id), source: .visit)
        record.clientID = h.client.id.uuidString
        record.notes = "Saved before"
        record.performedAt = h.clock.addingTimeInterval(-5_000)
        h.context.insert(record)
        try h.context.save()
        let before = ServiceRecord.Fields(of: record)
        center.complete(one, among: [one], now: h.clock)
        #expect(ServiceRecord.Fields(of: record) != before)                     // completing wrote to it
        #expect(center.undo() == .undone)
        #expect(try records(h).count == 1)
        #expect(ServiceRecord.Fields(of: record) == before)
        #expect(one.status == .scheduled)
    }

    @Test func undoingCompleteRemovesTheSeriesNextVisit() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let only = series(h, count: 1)[0]
        try h.context.save()
        center.complete(only, among: [only], now: h.clock)
        let grown = try visits(h)
        #expect(grown.count == 2)                                               // the series went on
        #expect(center.undo() == .undone)
        #expect(try visits(h).map(\.id) == [only.id])
        #expect(only.status == .scheduled)
    }

    @Test func aNextVisitWorkedOnSinceStays() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let only = series(h, count: 1)[0]
        try h.context.save()
        center.complete(only, among: [only], now: h.clock)
        let next = try #require(try visits(h).first { $0.id != only.id })
        next.scheduledDate = next.scheduledDate.addingTimeInterval(3_600)       // moved meanwhile
        #expect(center.undo() == .undone)
        #expect(try visits(h).count == 2)
    }

    @Test func aNextVisitNoLongerScheduledStays() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let only = series(h, count: 1)[0]
        try h.context.save()
        center.complete(only, among: [only], now: h.clock)
        let next = try #require(try visits(h).first { $0.id != only.id })
        next.status = .skipped                                                  // skipped meanwhile
        #expect(center.undo() == .undone)
        #expect(try visits(h).count == 2)
    }

    @Test func aNextVisitPutOnAnInvoiceStays() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let only = series(h, count: 1)[0]
        try h.context.save()
        center.complete(only, among: [only], now: h.clock)
        let next = try #require(try visits(h).first { $0.id != only.id })
        next.proposalID = UUID().uuidString                                     // invoiced meanwhile
        #expect(center.undo() == .undone)
        #expect(try visits(h).count == 2)
    }

    @Test func completeIsntUndoneAfterTheRecordWasEdited() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        center.complete(one, among: [one], now: h.clock)
        let record = try #require(try records(h).first)
        record.notes = "Edited on the record's page"
        #expect(center.undo() == .changed)
        #expect(one.status == .completed)
        #expect(try records(h).count == 1)
    }

    @Test func completeIsntUndoneAfterAPhotoWasAdded() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        center.complete(one, among: [one], now: h.clock)
        let record = try #require(try records(h).first)
        let photo = StopPhoto(operatorID: "op", clientID: h.client.id.uuidString, routeID: "", isBefore: false,
                              imageData: Data([1]))
        photo.recordID = record.id.uuidString
        h.context.insert(photo)
        #expect(center.undo() == .changed)
        #expect(one.status == .completed)
        #expect(try records(h).count == 1)
    }

    @Test func completeIsntUndoneAfterTheVisitChanged() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        center.complete(one, among: [one], now: h.clock)
        one.completedAt = h.clock.addingTimeInterval(60)                        // completed again elsewhere
        #expect(center.undo() == .changed)
        #expect(one.status == .completed)
    }

    @Test func undoIsRefusedAfterTheWindow() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        center.complete(one, among: [one], now: h.clock)
        h.clock += UndoCenter.window + 1
        #expect(center.undo() == .expired)
        #expect(one.status == .completed)
        #expect(try records(h).count == 1)
    }

    @Test func undoingTwiceIsRefused() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        center.skip(one)
        let id = center.offer?.id
        #expect(center.undo(id) == .undone)
        one.status = .skipped
        #expect(center.undo(id) == .nothingToUndo)
        #expect(one.status == .skipped)
    }

    // A record billed on the invoice already made for its visit: the invoice
    // is the visit's, and stays, still linked to the visit.
    @Test func aVisitBilledRecordKeepsItsInvoice() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = visit(h)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0001"
        h.context.insert(invoice)
        one.proposalID = invoice.id.uuidString
        try h.context.save()
        center.complete(one, among: [one], now: h.clock)
        let record = try #require(try records(h).first)
        #expect(record.invoiceID == invoice.id.uuidString)
        #expect(center.undo() == .undone)
        #expect(try records(h).isEmpty)
        #expect(try h.context.fetch(FetchDescriptor<Proposal>()).map(\.id) == [invoice.id])
        #expect(one.proposalID == invoice.id.uuidString)
    }
    // MARK: - Mark Paid

    @Test func markPaidOffersUndoNamingTheInvoiceAndAmount() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let bill = invoice(h, total: 120)
        center.markPaid(bill, now: h.clock)
        #expect(bill.invoicePaidAt == h.clock)
        #expect(center.offer?.title == "Marked INV-0007 Paid · \(Money.text(120))")
        #expect(!h.context.hasChanges)                                          // saved
        #expect(center.undo() == .undone)
        #expect(bill.invoicePaidAt == nil && bill.sortedPayments.isEmpty)
        #expect(bill.balanceDue == 120)
    }

    @Test func markPaidOnAPaidInvoiceOffersNothing() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let bill = invoice(h, total: 120)
        bill.invoicePaidAt = h.clock
        center.markPaid(bill, now: h.clock)
        #expect(center.offer == nil)
    }

    // MARK: - Client photos

    @Test func aDeletedPhotoIsHiddenThenDeletedWhenTheWindowEnds() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = photo(h), other = photo(h)
        try h.context.save()
        center.delete(one)
        #expect(center.isPendingDeletion(one) && !center.isPendingDeletion(other))
        #expect(center.offer?.title == "Deleted photo")
        #expect(try photos(h).count == 2)                                       // not deleted yet
        h.clock += UndoCenter.window + 1
        center.endIfExpired()
        #expect(center.offer == nil && center.pendingDeletions.isEmpty)
        #expect(try photos(h).map(\.id) == [other.id])
        #expect(!h.context.hasChanges)
    }

    @Test func undoingAPhotoDeleteKeepsThePhoto() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = photo(h)
        try h.context.save()
        let id = one.persistentModelID
        center.delete(one)
        #expect(center.undo() == .undone)
        #expect(!center.isPendingDeletion(one))
        #expect(!h.context.hasChanges)
        center.end()
        h.clock += 60
        center.endIfExpired()
        #expect(try photos(h).map(\.persistentModelID) == [id])                // the same photo, never re-made
    }

    @Test func aPendingPhotoIsDeletedByANewOfferOrTheBackground() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = photo(h), two = photo(h)
        try h.context.save()
        center.delete(one)
        center.delete(two)                                                       // replaces the first
        #expect(try photos(h).map(\.id) == [two.id])
        center.sceneDidEnterBackground()
        #expect(try photos(h).isEmpty)
    }

    @Test func discardAllKeepsAPendingPhoto() throws {
        let h = try Harness(stopCount: 0)
        let center = center(h)
        let one = photo(h)
        try h.context.save()
        center.delete(one)
        center.discardAll()
        center.end()
        #expect(try photos(h).count == 1)
    }

    // MARK: - Optimize

    @Test func undoingOptimizePutsTheOrderBack() throws {
        let h = try Harness(stopCount: 3)
        let center = center(h)
        let before = StopOrderSnapshot(h.route.sortedStops)
        let ids = h.route.sortedStops.map(\.id)
        optimize(h, to: [2, 0, 1])
        center.optimized(h.route, from: before)
        #expect(center.offer?.title == "Optimized Tuesday")
        #expect(!h.context.hasChanges)
        #expect(center.undo() == .undone)
        #expect(h.route.sortedStops.map(\.id) == ids)
        #expect(StopOrderSnapshot(h.route.sortedStops) == before)
        #expect(!h.context.hasChanges)                                          // saved
    }

    @Test func optimizeThatChangedNothingOffersNothing() throws {
        let h = try Harness(stopCount: 3)
        let center = center(h)
        center.optimized(h.route, from: StopOrderSnapshot(h.route.sortedStops))
        #expect(center.offer == nil)
    }

    @Test func optimizeIsntUndoneAfterAStopWasMoved() throws {
        let h = try Harness(stopCount: 3)
        let center = center(h)
        let before = StopOrderSnapshot(h.route.sortedStops)
        optimize(h, to: [2, 0, 1])
        center.optimized(h.route, from: before)
        let moved = h.route.sortedStops
        moved[0].order = 1                                                       // moved by hand
        moved[1].order = 0
        let after = StopOrderSnapshot(h.route.sortedStops)
        #expect(center.undo() == .changed)
        #expect(StopOrderSnapshot(h.route.sortedStops) == after)                // left as it was
    }

    @Test func optimizeIsntUndoneAfterAStopWasAdded() throws {
        let h = try Harness(stopCount: 3)
        let center = center(h)
        let before = StopOrderSnapshot(h.route.sortedStops)
        optimize(h, to: [2, 0, 1])
        center.optimized(h.route, from: before)
        let stop = RouteStop(order: 3, client: h.client)
        stop.route = h.route
        h.context.insert(stop)
        let after = StopOrderSnapshot(h.route.sortedStops)
        #expect(center.undo() == .changed)
        #expect(StopOrderSnapshot(h.route.sortedStops) == after)
    }

    // MARK: - Hidden while a delete is held back

    // A lead whose only visit is pending deletion has no work booked.
    @Test func aPendingVisitIsntWorkForThePipeline() throws {
        let h = try Harness(stopCount: 0)
        let one = visit(h)
        try h.context.save()
        let id = h.client.id.uuidString
        #expect(Pipeline.Facts(documents: [], records: [], visits: [one], stops: []).withWork.contains(id))
        let hidden = Pipeline.Facts(documents: [], records: [], visits: [one], stops: [],
                                    hiding: [one.persistentModelID])
        #expect(!hidden.withWork.contains(id))
    }

    @Test func aPendingVisitIsLeftOffTheTimeline() throws {
        let h = try Harness(stopCount: 0)
        let one = visit(h, day: 1), other = visit(h, day: 2)
        try h.context.save()
        let events = ClientTimeline.events(for: h.client, now: h.clock, hiding: [one.persistentModelID], in: h.context)
        #expect(!events.contains { $0.id == "visit-\(one.id)" })
        #expect(events.contains { $0.id == "visit-\(other.id)" })
    }

    // MARK: - Helpers for these

    private func invoice(_ h: Harness, total: Double) -> Proposal {
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0007"
        invoice.invoiceSentAt = h.clock.addingTimeInterval(-86_400)
        let item = ProposalLineItem(serviceName: "Clear", zoneLabel: "", quantity: 1, unitType: "flat", unitPrice: total)
        h.context.insert(item)
        h.context.insert(invoice)
        invoice.lineItems = [item]
        return invoice
    }

    private func photo(_ h: Harness) -> StopPhoto {
        let photo = StopPhoto(operatorID: "op", clientID: h.client.id.uuidString, routeID: "", isBefore: true,
                              imageData: Data([1]))
        h.context.insert(photo)
        return photo
    }

    private func photos(_ h: Harness) throws -> [StopPhoto] {
        try h.context.fetch(FetchDescriptor<StopPhoto>())
    }

    /// Gives the route's stops (as sorted now) these orders, as Optimize does.
    private func optimize(_ h: Harness, to orders: [Int]) {
        for (stop, order) in zip(h.route.sortedStops, orders) { stop.order = order }
    }
}

/// Holds a timer's sleep until the test lets it go.
@MainActor
private final class SleepGate {
    var waiting: [CheckedContinuation<Void, Never>] = []
}
