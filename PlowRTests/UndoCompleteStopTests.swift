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

    /// What Record Services saves: Clear at a typed $55, and a note.
    private func recordServices(_ h: Harness, _ store: ActiveRouteStore, at stop: RouteStop, client: Client,
                                service: ServiceItem) throws -> ServiceRecord {
        let screen = StopRecording(services: [.init(id: service.id.uuidString, name: service.name,
                                                     unitType: service.unitType, pricePerUnit: service.pricePerUnit)],
                                   zones: [], selectedIDs: [service.id.uuidString],
                                   typedPrices: [service.id.uuidString: "55"])
        let run = try #require(store.runID)
        let startedAt = try #require(store.stopStartedAt)
        return ServiceLog.saveRecording(screen, notes: "Icy drive", for: stop, of: client, run: run, operatorID: "op",
                                        startedAt: startedAt, in: h.context)
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
    // bills the record on that invoice; undo puts it back unbilled at the
    // same $55, as it was.
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
        #expect(record.invoiceID.isEmpty)
        #expect(record.isBillable)
        #expect(record.lines.map(\.price) == [55])
        #expect(ServiceLog.total(of: record) == 55)
        #expect(ServiceLog.billingStatus(of: record, in: h.context) == .notBilled)
        #expect(!ServiceLog.isVisitBilled(visit, in: h.context))
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

    // Not kept across a relaunch: the completion stands.
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
}
