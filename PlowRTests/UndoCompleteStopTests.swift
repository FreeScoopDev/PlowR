import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Undo after Complete Stop: everything completing changed is put back
/// exactly, and only for the stop just completed, inside the window.
@MainActor
struct UndoCompleteStopTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    /// The fields completing can write on a record, read one by one (not
    /// through the store's own snapshot, so a field it forgets shows here).
    struct RecordValues: Equatable {
        var startedAt: Date?
        var performedAt: Date
        var minutes: Double
        var arrivedAt: Date?
        var leftAt: Date?
        var lines: [ServiceRecord.Line]
        var notes: String
        var visitID: String
        var source: ServiceRecordSource
        var invoiceID: String
        var isBillable: Bool
        var clientName: String
        var propertyID: String
        var propertyAddress: String
        var routeID: String
        var routeName: String
        var runID: String
        var stopID: String

        init(_ r: ServiceRecord) {
            startedAt = r.startedAt
            performedAt = r.performedAt
            minutes = r.minutes
            arrivedAt = r.arrivedAt
            leftAt = r.leftAt
            lines = r.lines
            notes = r.notes
            visitID = r.visitID
            source = r.source
            invoiceID = r.invoiceID
            isBillable = r.isBillable
            clientName = r.clientName
            propertyID = r.propertyID
            propertyAddress = r.propertyAddress
            routeID = r.routeID
            routeName = r.routeName
            runID = r.runID
            stopID = r.stopID
        }
    }

    private func pin(_ h: Harness) {
        for (i, stop) in h.route.sortedStops.enumerated() {
            stop.latitude = 43 + Double(i) / 100
            stop.longitude = -79
        }
    }

    private func records(_ h: Harness) throws -> [ServiceRecord] {
        try h.context.fetch(FetchDescriptor<ServiceRecord>())
    }

    private func checkpoint(_ h: Harness) throws -> ActiveRouteStore.Checkpoint {
        let data = try #require(h.defaults.data(forKey: ActiveRouteStore.checkpointKey))
        return try JSONDecoder().decode(ActiveRouteStore.Checkpoint.self, from: data)
    }

    private func clear(_ h: Harness) -> ServiceItem {
        let item = ServiceItem(name: "Clear", category: "snow", unitType: "flat", pricePerUnit: 40, operatorID: "op",
                               sortOrder: 0)
        h.context.insert(item)
        return item
    }

    /// What Record Services shows: `service` at a typed price.
    private func screen(_ service: ServiceItem, price: String = "55") -> StopRecording {
        StopRecording(services: [.init(id: service.id.uuidString, name: service.name,
                                       unitType: service.unitType, pricePerUnit: service.pricePerUnit)],
                      zones: [], selectedIDs: [service.id.uuidString], typedPrices: [service.id.uuidString: price])
    }

    /// What Record Services saves: Clear at a typed $55 (or `price`), and a
    /// note. As the sheet does, for a stop already completed it dates the
    /// work by the run's start (StopServiceRecorderView).
    private func recordServices(_ h: Harness, _ store: ActiveRouteStore, at stop: RouteStop, client: Client,
                                service: ServiceItem, price: String = "55",
                                notes: String = "Icy drive") throws -> ServiceRecord {
        let run = try #require(store.runID)
        let startedAt = try #require(stop.id == store.currentStopID ? store.stopStartedAt : store.runStartedAt)
        return ServiceLog.saveRecording(screen(service, price: price), notes: notes, for: stop, of: client, run: run,
                                        operatorID: "op", startedAt: startedAt, in: h.context)
    }

    // A plain completion, undone: the route, the stop, the client, the record
    // (made by completing, so deleted), departures and the checkpoint are
    // back as they were.
    @Test func undoAfterAPlainCompletionRestoresEveryField() throws {
        let h = try Harness()
        pin(h)
        let stops = h.route.sortedStops
        let client = h.clients[1]
        let lastService = Date(timeIntervalSince1970: 1_700_000_000)
        client.totalVisits = 4
        client.totalServiceMinutes = 33.5
        client.lastServiceDate = lastService
        try h.context.save()
        let surfaces = FakeRouteSurfaces()
        let store = h.makeStore(surfaces)
        store.start(h.route)
        // Stop 0, completed without being seen leaving: its departure is awaited.
        h.clock += 600
        store.completeShownStop()
        let awaited = store.departures
        #expect(awaited.map(\.stopID) == [stops[0].id])
        // At stop 1: seen leaving its area (no arrival seen), timer running.
        let startedAtStop1 = try #require(store.stopStartedAt)
        h.clock += 300
        store.siteExited(stops[1].id.uuidString, at: h.clock)
        let siteAtStop1 = store.site
        #expect(siteAtStop1 != SiteTimes())
        let before = try checkpoint(h)
        let recordsBefore = try records(h).map(\.id)

        h.clock += 900
        #expect(store.completeShownStop() == .advanced(nextStopIndex: 2))
        #expect(client.totalVisits == 5)
        #expect(try records(h).count == 2)
        #expect(store.undoOffer?.stopID == stops[1].id)
        #expect(store.undoOffer?.clientName == "Client 1")

        h.clock += 29
        #expect(store.undoLastCompletion(expecting: stops[1].id) == .undone)
        #expect(store.currentStopIndex == 1)
        #expect(store.currentStopID == stops[1].id)
        #expect(store.stopStartedAt == startedAtStop1)
        #expect(store.site == siteAtStop1)
        #expect(stops[1].actualMinutes == 0)
        #expect(stops[0].actualMinutes == 10)                   // the stop before stays done
        #expect(store.departures == awaited)
        #expect(SiteDepartures.load(from: h.defaults) == awaited)
        #expect(client.totalVisits == 4)
        #expect(client.totalServiceMinutes == 33.5)
        #expect(client.lastServiceDate == lastService)
        #expect(try records(h).map(\.id) == recordsBefore)       // the one completing made is gone
        #expect(try checkpoint(h) == before)
        #expect(surfaces.last?.currentStopID == stops[1].id)
        #expect(surfaces.last?.completedStops == 1)
        #expect(store.undoOffer == nil)
        #expect(!h.context.hasChanges)                           // saved
        // A relaunch comes back at the restored stop.
        let relaunched = h.makeStore()
        #expect(relaunched.currentStopID == stops[1].id)
        #expect(relaunched.stopStartedAt == startedAtStop1)
    }

    // Record Services made the record before the stop was completed: undo
    // puts its fields back and keeps it, with its services and notes.
    @Test func undoKeepsARecordRecordServicesMadeAndRestoresIt() throws {
        let h = try Harness()
        let service = clear(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        h.clock += 120
        let record = try recordServices(h, store, at: stop, client: h.client, service: service)
        try h.context.save()
        let before = RecordValues(record)
        #expect(before.lines.map(\.price) == [55])

        h.clock += 1200
        store.completeShownStop()
        #expect(record.minutes > 0 && record.startedAt != nil)    // completing wrote its times
        #expect(RecordValues(record) != before)

        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(try records(h).map(\.id) == [record.id])
        #expect(RecordValues(record) == before)
        #expect(stop.completedServiceIDs == [service.id.uuidString])  // the recorded services stand
        #expect(store.currentStopID == stop.id)
    }

    // The day's visit the stop completed is due again, and the next visit
    // its series added on completion is gone.
    @Test func undoRestoresTheScheduledVisit() throws {
        let h = try Harness()
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        visit.isRecurring = true
        visit.recurrenceType = .weekly
        h.context.insert(visit)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        h.clock += 900
        store.completeShownStop()
        #expect(visit.status == .completed)
        #expect(visit.serviceLogged)
        #expect(try h.context.fetch(FetchDescriptor<ScheduledVisit>()).count == 2)

        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(visit.status == .scheduled)
        #expect(visit.completedAt == nil)
        #expect(!visit.serviceLogged)
        #expect(try h.context.fetch(FetchDescriptor<ScheduledVisit>()).map(\.id) == [visit.id])
        #expect(try records(h).isEmpty)
    }

    // Money: work recorded at $55, then the visit was invoiced (Schedule →
    // Invoice, another device) before the stop was completed. Completing
    // bills the record on that invoice (its invoiceID: the one money field
    // completing changes here; its lines stand, Record Services made them);
    // undo puts it back unbilled. The amounts are checked to show they
    // didn't move either way.
    @Test func undoPutsAVisitBilledRecordBackToItsExactAmounts() throws {
        let h = try Harness()
        let service = clear(h)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let record = try recordServices(h, store, at: stop, client: h.client, service: service)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0007"
        h.context.insert(invoice)
        visit.proposalID = invoice.id.uuidString
        try h.context.save()
        let before = RecordValues(record)
        #expect(ServiceLog.total(of: record) == 55)
        #expect(record.invoiceID.isEmpty)
        #expect(ServiceLog.billingStatus(of: record, in: h.context) == .notBilled)

        h.clock += 900
        store.completeShownStop()
        #expect(record.invoiceID == invoice.id.uuidString)       // completing billed it
        #expect(ServiceLog.billingStatus(of: record, in: h.context) == .invoiced)

        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(RecordValues(record) == before)
        // The real check: unbilled again.
        #expect(record.invoiceID.isEmpty)
        #expect(ServiceLog.billingStatus(of: record, in: h.context) == .notBilled)
        #expect(!ServiceLog.isVisitBilled(visit, in: h.context))
        // Unchanged by completing, so unchanged by undo.
        #expect(record.isBillable)
        #expect(record.lines.map(\.price) == [55])
        #expect(ServiceLog.total(of: record) == 55)
    }

    // MARK: - Refused

    @Test func undoIsRefusedAfterTheNextCompletion() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        store.completeShownStop()
        store.completeShownStop()
        #expect(store.undoLastCompletion(expecting: stops[0].id) == .stopChanged)
        #expect(store.currentStopIndex == 2)
        #expect(h.clients[0].totalVisits == 1)
        #expect(h.clients[1].totalVisits == 1)
        #expect(try records(h).count == 2)
        // The second one can still be undone, and only it.
        #expect(store.undoLastCompletion(expecting: stops[1].id) == .undone)
        #expect(store.currentStopID == stops[1].id)
        #expect(h.clients[0].totalVisits == 1)
    }

    @Test func undoIsRefusedAfterEnd() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStopID)
        store.completeShownStop()
        store.end()
        #expect(store.undoOffer == nil)
        #expect(store.undoLastCompletion(expecting: first) == .nothingToUndo)
        #expect(h.client.totalVisits == 1)
        #expect(try records(h).count == 1)
        #expect(!store.isActive)
    }

    @Test func undoIsRefusedAfterTheWindow() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStopID)
        store.completeShownStop()
        let expires = try #require(store.undoOffer?.expiresAt)
        h.clock += ActiveRouteStore.undoWindow + 0.5
        #expect(h.clock > expires)
        #expect(store.undoLastCompletion(expecting: first) == .expired)
        #expect(store.currentStopIndex == 1)
        #expect(h.client.totalVisits == 1)
        #expect(try records(h).count == 1)
        #expect(store.undoOffer == nil)
    }

    @Test func undoIsRefusedForADifferentStop() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStopID)
        store.completeShownStop()
        let current = try #require(store.currentStopID)
        #expect(store.undoLastCompletion(expecting: current) == .stopChanged)
        #expect(store.undoLastCompletion(expecting: UUID()) == .stopChanged)
        #expect(store.currentStopIndex == 1)
        #expect(h.client.totalVisits == 1)
        // A wrong caller doesn't take the chance away from the right one.
        #expect(store.undoLastCompletion(expecting: first) == .undone)
    }

    @Test func aSecondUndoIsRefused() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStopID)
        h.client.totalVisits = 2
        store.completeShownStop()
        #expect(store.undoLastCompletion(expecting: first) == .undone)
        #expect(store.undoLastCompletion(expecting: first) == .nothingToUndo)
        #expect(store.currentStopIndex == 0)
        #expect(h.client.totalVisits == 2)
    }

    // MARK: - When there's nothing to undo

    @Test func theLastStopCantBeUndone() throws {
        let h = try Harness(stopCount: 1)
        let store = h.makeStore()
        store.start(h.route)
        let only = try #require(store.currentStopID)
        #expect(store.completeShownStop() == .finishedLastStop)
        #expect(store.undoOffer == nil)
        #expect(store.undoLastCompletion(expecting: only) == .nothingToUndo)
        #expect(try records(h).count == 1)
    }

    @Test func passingBelowTriggerEndsTheChanceToUndo() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStopID)
        store.completeShownStop()
        store.passCurrentStop(expecting: try #require(store.currentStopID))
        #expect(store.undoOffer == nil)
        #expect(store.undoLastCompletion(expecting: first) == .nothingToUndo)
        #expect(store.currentStopIndex == 2)
    }

    // Another device reordered the stops: undoing could put back the wrong one.
    @Test func aRouteChangeEndsTheChanceToUndo() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStopID)
        store.completeShownStop()
        let stops = h.route.sortedStops
        stops[0].order = 5           // moved to the end elsewhere
        try h.context.save()         // validate() runs on the save
        #expect(store.undoOffer == nil)
        #expect(store.undoLastCompletion(expecting: first) == .nothingToUndo)
    }

    // Documents the design: the chance to undo is in memory only, never in
    // the checkpoint, so after a relaunch the completion stands.
    @Test func aRelaunchKeepsTheCompletion() throws {
        let h = try Harness()
        let before = h.makeClosedAppStore()
        before.start(h.route)
        let first = try #require(before.currentStopID)
        before.completeShownStop()
        try h.context.save()
        let after = h.makeStore()
        #expect(after.undoOffer == nil)
        #expect(after.undoLastCompletion(expecting: first) == .nothingToUndo)
        #expect(after.currentStopIndex == 1)
    }

    // MARK: - Work saved after completing

    // Record Services left open on a stop Siri or Control Center completed:
    // services saved and invoiced in it after. Undo would delete an invoiced
    // record, so it's refused and the bar closes.
    @Test func undoIsRefusedOnceTheRecordWasInvoicedAfterCompleting() throws {
        let h = try Harness()
        let service = clear(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        h.clock += 600
        store.completeShownStop()
        #expect(store.undoOffer != nil)
        let record = try recordServices(h, store, at: stop, client: h.client, service: service)
        #expect(store.undoOffer == nil)                          // the bar closes on the save
        let invoice = ServiceLog.invoice(record, lines: screen(service).invoiceLines, contractCharge: 0,
                                         client: h.client, operatorID: "op", notes: "", now: h.clock, in: h.context)
        try h.context.save()

        #expect(store.undoLastCompletion(expecting: stop.id) == .recordChanged)
        #expect(try records(h).map(\.id) == [record.id])
        #expect(record.invoiceID == invoice.id.uuidString)
        #expect(ServiceLog.billingStatus(of: record, in: h.context) == .invoiced)
        #expect(record.lines.map(\.price) == [55])
        #expect(store.currentStopIndex == 1)
        #expect(h.client.totalVisits == 1)
        #expect(store.undoLastCompletion(expecting: stop.id) == .nothingToUndo)
    }

    // The same with a record Record Services made before completing: the
    // services saved after completing survive.
    @Test func servicesSavedAfterCompletingSurviveARefusedUndo() throws {
        let h = try Harness()
        let service = clear(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let record = try recordServices(h, store, at: stop, client: h.client, service: service)
        h.clock += 600
        store.completeShownStop()
        _ = try recordServices(h, store, at: stop, client: h.client, service: service, price: "70",
                               notes: "Second pass")
        #expect(store.undoLastCompletion(expecting: stop.id) == .recordChanged)
        #expect(record.lines.map(\.price) == [70])
        #expect(record.notes == "Second pass")
        #expect(record.minutes == 10)                            // completing's times stand too
        #expect(store.currentStopIndex == 1)
    }

    // A photo taken for the record after completing: refused, photo kept on it.
    @Test func undoIsRefusedOnceAPhotoWasTakenForTheRecord() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        store.completeShownStop()
        let record = try #require(try records(h).first)
        let photo = StopPhoto(operatorID: "op", clientID: h.client.id.uuidString, routeID: h.route.id.uuidString,
                              isBefore: false, imageData: Data())
        photo.recordID = record.id.uuidString
        h.context.insert(photo)
        try h.context.save()
        #expect(store.undoLastCompletion(expecting: stop.id) == .recordChanged)
        #expect(photo.recordID == record.id.uuidString)
        #expect(try records(h).count == 1)
    }

    // Seen leaving after completing (GPS writes the departure on the record):
    // still undoable, and the departure goes with it.
    @Test func aDepartureAfterCompletingDoesntBlockUndo() throws {
        let h = try Harness()
        pin(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        h.clock += 600
        store.completeShownStop()
        h.clock += 10
        store.siteExited(stop.id.uuidString, at: h.clock)
        #expect(try records(h).first?.leftAt == h.clock)
        #expect(store.undoOffer != nil)
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(try records(h).isEmpty)
    }

    // MARK: - Client totals

    // A change synced from another device inside the window stands: undo
    // takes back only what this completion added.
    @Test func undoTakesBackOnlyWhatCompletingAddedToTheClient() throws {
        let h = try Harness()
        h.client.totalVisits = 4
        h.client.totalServiceMinutes = 10
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStopID)
        h.clock += 15 * 60
        store.completeShownStop()
        #expect(h.client.totalVisits == 5)
        #expect(h.client.totalServiceMinutes == 25)
        // Another device's visit, synced in.
        let synced = h.clock + 5
        h.client.totalVisits += 1
        h.client.totalServiceMinutes += 20
        h.client.lastServiceDate = synced
        #expect(store.undoLastCompletion(expecting: first) == .undone)
        #expect(h.client.totalVisits == 5)
        #expect(h.client.totalServiceMinutes == 30)
        #expect(h.client.lastServiceDate == synced)
    }

    // MARK: - A record completing made and billed

    // The visit was invoiced before the work (Schedule → Invoice): completing
    // makes the record and bills it on that invoice (billFromVisit). Undo
    // deletes the record and leaves the invoice and the visit's link to it;
    // completing again bills the new record on it again.
    @Test func undoDeletesARecordCompletingMadeAndBilledAndCompletingAgainRebillsIt() throws {
        let h = try Harness()
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0009"
        h.context.insert(invoice)
        visit.proposalID = invoice.id.uuidString
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        h.clock += 600
        store.completeShownStop()
        let made = try #require(try records(h).first)
        #expect(made.invoiceID == invoice.id.uuidString)

        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(try records(h).isEmpty)
        #expect(visit.proposalID == invoice.id.uuidString)
        #expect(try h.context.fetch(FetchDescriptor<Proposal>()).map(\.id) == [invoice.id])
        #expect(invoice.invoiceNumber == "INV-0009")

        h.clock += 60
        store.completeShownStop()
        let again = try #require(try records(h).first)
        #expect(again.id != made.id)
        #expect(again.invoiceID == invoice.id.uuidString)
    }
}

// From the test audit (2026-11-07).
extension UndoCompleteStopTests {
    @Test func gapScheduleMadeRecordFilledByRouteIsPutBack() throws {
        let h = try Harness()
        pin(h)
        let service = clear(h)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: "9 Other St", scheduledDate: h.clock)
        h.context.insert(visit)
        let ticked = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        h.client.name = "Renamed"
        try h.context.save()
        let before = RecordValues(ticked)
        #expect(before.runID.isEmpty && before.stopID.isEmpty && before.routeID.isEmpty && before.lines.isEmpty
                && before.notes.isEmpty && before.arrivedAt == nil && before.leftAt == nil)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        stop.completedServiceIDs = [service.id.uuidString]
        stop.completedNotes = "Icy drive"
        h.clock += 120
        store.siteEntered(stop.id.uuidString, at: h.clock)
        h.clock += 600
        store.siteExited(stop.id.uuidString, at: h.clock)
        store.completeShownStop()
        let after = RecordValues(ticked)
        #expect(after.runID == store.runID?.uuidString && after.stopID == stop.id.uuidString)
        #expect(!after.lines.isEmpty && after.notes == "Icy drive" && after.arrivedAt != nil && after.leftAt != nil)
        #expect(try records(h).count == 1)
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(RecordValues(ticked) == before)
    }

    @Test func gapUnseenChangeFlagComesBack() throws {
        let h = try Harness()
        let store = h.makeStore()
        store.start(h.route)
        h.context.delete(h.route.sortedStops[0])    // the current stop deleted elsewhere
        try h.context.save()
        #expect(store.stopChangedUnseen)
        let stop = try #require(store.currentStop)
        store.completeShownStop()
        #expect(!store.stopChangedUnseen)
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(store.stopChangedUnseen)
    }

    @Test func gapWindowIsThirtySecondsNotTheConstant() throws {
        let a = try Harness()
        let sa = a.makeStore()
        sa.start(a.route)
        let fa = try #require(sa.currentStopID)
        sa.completeShownStop()
        a.clock += 29.9
        #expect(sa.undoLastCompletion(expecting: fa) == .undone)
        let b = try Harness()
        let sb = b.makeStore()
        sb.start(b.route)
        let fb = try #require(sb.currentStopID)
        sb.completeShownStop()
        b.clock += 30.1
        #expect(sb.undoLastCompletion(expecting: fb) == .expired)
    }

    @Test func gapUndoLeavesTheInvoiceItself() throws {
        let h = try Harness()
        let service = clear(h)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        _ = try recordServices(h, store, at: stop, client: h.client, service: service)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0007"
        h.context.insert(invoice)
        visit.proposalID = invoice.id.uuidString
        try h.context.save()
        store.completeShownStop()
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        let invoices = try h.context.fetch(FetchDescriptor<Proposal>())
        #expect(invoices.map(\.id) == [invoice.id])
        #expect(invoices.first?.invoiceNumber == "INV-0007")
        #expect(visit.proposalID == invoice.id.uuidString)
    }
}
