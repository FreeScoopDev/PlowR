import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The route screen's "Done:" button: when the current stop expects services
/// and nothing is recorded for it yet, the copper button names them and
/// completing with it records exactly those, as Record Services' Add
/// Expected and Save would. Anything else keeps the ordinary Complete.
@MainActor
struct OneTapServicesTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    /// Mow (flat), Edge (per square foot) and Aerate (switched off), every
    /// client measured at 1,234 sq ft and expecting all three, Edge first.
    struct Catalog {
        var mow: ServiceItem
        var edge: ServiceItem
        var aerate: ServiceItem
    }

    @discardableResult
    private func catalog(_ h: Harness) throws -> Catalog {
        let mow = ServiceItem(name: "Mow", category: "lawn", unitType: "flat", pricePerUnit: 40, operatorID: "op",
                              sortOrder: 1)
        let edge = ServiceItem(name: "Edge", category: "lawn", unitType: "perSqFt", pricePerUnit: 0.0173,
                               operatorID: "op", sortOrder: 2)
        let aerate = ServiceItem(name: "Aerate", category: "lawn", unitType: "flat", pricePerUnit: 30,
                                 operatorID: "op", sortOrder: 3)
        aerate.isActive = false
        [mow, edge, aerate].forEach { h.context.insert($0) }
        for client in h.clients {
            for (label, area) in [("Front", 1_000.0), ("Back", 234.0)] {
                let zone = PropertyZone(label: label)
                zone.areaSquareFeet = area
                h.context.insert(zone)
                zone.client = client
            }
            client.expectedServiceIDs = [edge.id.uuidString, mow.id.uuidString, aerate.id.uuidString]
        }
        try h.context.save()
        return Catalog(mow: mow, edge: edge, aerate: aerate)
    }

    private func allServices(_ h: Harness) throws -> [ServiceItem] {
        try h.context.fetch(FetchDescriptor<ServiceItem>())
    }

    /// The button the route screen draws for the store's current stop.
    private func button(_ h: Harness, _ store: ActiveRouteStore, skipsText: Bool = false) throws -> OneTapServices.MainButton {
        let stop = try #require(store.currentStop)
        let client = stop.isCustomStop ? nil : h.clients.first { $0.id == stop.clientID }
        return OneTapServices.mainButton(for: stop, client: client, catalog: try allServices(h), operatorID: "op",
                                         store: store, skipsText: skipsText, in: h.context)
    }

    private func records(_ h: Harness) throws -> [ServiceRecord] {
        try h.context.fetch(FetchDescriptor<ServiceRecord>())
    }

    private func record(_ h: Harness, _ store: ActiveRouteStore, stop: RouteStop) throws -> ServiceRecord? {
        ServiceLog.runRecord(run: try #require(store.runID), stop: stop.id, in: h.context)
    }

    // MARK: - Which button

    @Test func aStopExpectingServicesGetsDoneWithTheirNames() throws {
        let h = try Harness()
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        // Catalog order, active services only: Aerate is switched off.
        #expect(try button(h, store) == .done(serviceIDs: [c.mow.id.uuidString, c.edge.id.uuidString],
                                              names: ["Mow", "Edge"]))
    }

    @Test func otherwiseTheButtonIsTheOrdinaryOne() throws {
        let h = try Harness(stopCount: 2)
        let store = h.makeStore()
        store.start(h.route)
        // No expected services at all.
        #expect(try button(h, store) == .completeAndText)
        #expect(try button(h, store, skipsText: true) == .completeStop)
        store.completeShownStop()
        #expect(try button(h, store) == .completeRoute)
        #expect(OneTapServices.ordinaryTitle(isLastStop: true, skipsText: false) == "Complete Route")
        #expect(OneTapServices.ordinaryTitle(isLastStop: false, skipsText: true) == "Complete Stop")
        #expect(OneTapServices.ordinaryTitle(isLastStop: false, skipsText: false) == "Complete · Text Next Client")
    }

    @Test func theLastStopGetsDoneToo() throws {
        let h = try Harness(stopCount: 1)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        #expect(try button(h, store).recordedServiceIDs.count == 2)
    }

    @Test func onlyServicesStillInTheCatalogAreNamed() throws {
        let h = try Harness(stopCount: 1)
        let c = try catalog(h)
        c.mow.isActive = false
        h.context.delete(c.edge)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        // Nothing expected is still offered: the ordinary button.
        #expect(try button(h, store) == .completeRoute)
        // Another business's service with an expected ID isn't named either.
        let theirs = ServiceItem(name: "Theirs", category: "lawn", unitType: "flat", pricePerUnit: 9,
                                 operatorID: "other")
        h.context.insert(theirs)
        h.client.expectedServiceIDs.append(theirs.id.uuidString)
        #expect(try button(h, store) == .completeRoute)
    }

    @Test func aCustomStopNeverGetsDone() throws {
        let h = try Harness(stopCount: 1)
        let c = try catalog(h)
        let custom = RouteStop(order: 1, customName: "Depot")
        custom.route = h.route
        h.context.insert(custom)
        #expect(custom.isCustomStop)
        StopServices.setForThisRoute([c.mow.id.uuidString], on: custom)
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        store.completeShownStop()
        #expect(store.currentStopID == custom.id)
        #expect(try button(h, store) == .completeRoute)
        // Even handed services, completing a custom stop records none.
        store.completeCurrentStop(expecting: custom.id, recordingServices: [c.mow.id.uuidString])
        #expect(custom.completedServiceIDs.isEmpty)
        #expect(OneTapServices.servicesToName(expected: [c.mow.id.uuidString],
                                              active: ServiceLog.activeServices(try allServices(h), operatorID: "op"),
                                              hasClient: false, nothingRecorded: true).isEmpty)
    }

    @Test func servicesRecordedAlreadyKeepTheOrdinaryButton() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        // Record Services saved Mow at a typed price.
        let recording = StopRecording(services: ServiceLog.activeServices(try allServices(h), operatorID: "op"),
                                      zones: [], selectedIDs: [c.mow.id.uuidString],
                                      typedPrices: [c.mow.id.uuidString: "55"])
        ServiceLog.saveRecording(recording, notes: "", for: stop, of: h.client, run: try #require(store.runID),
                                 operatorID: "op", startedAt: try #require(store.stopStartedAt), in: h.context)
        #expect(try button(h, store) == .completeAndText)
        // Handed the services anyway, completing neither adds to nor replaces them.
        store.completeCurrentStop(expecting: stop.id, recordingServices: [c.mow.id.uuidString, c.edge.id.uuidString])
        #expect(stop.completedServiceIDs == [c.mow.id.uuidString])
        let saved = try #require(try record(h, store, stop: stop))
        #expect(saved.lines.map(\.name) == ["Mow"])
        #expect(saved.lines.map(\.price) == [55])
    }

    @Test func aRecordWithServicesFromTheScheduleKeepsTheOrdinaryButton() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        visit.expectedServiceIDs = [c.mow.id.uuidString]
        h.context.insert(visit)
        _ = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        #expect(try button(h, store) == .completeAndText)
        store.completeCurrentStop(expecting: stop.id, recordingServices: [c.edge.id.uuidString])
        #expect(stop.completedServiceIDs.isEmpty)
        #expect(try records(h).flatMap(\.lines).map(\.name) == ["Mow"])
    }

    @Test func workAlreadyOnAnInvoiceKeepsTheOrdinaryButton() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0040"
        h.context.insert(invoice)
        visit.proposalID = invoice.id.uuidString
        try h.context.save()
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        #expect(try button(h, store) == .completeAndText)
        store.completeCurrentStop(expecting: stop.id, recordingServices: [c.mow.id.uuidString])
        #expect(stop.completedServiceIDs.isEmpty)
        let saved = try #require(try record(h, store, stop: stop))
        #expect(saved.invoiceID == invoice.id.uuidString)
        #expect(saved.lines.isEmpty)
    }

    // MARK: - The label

    @Test func theLabelShortensToFewerNamesAndMore() {
        #expect(OneTapServices.doneTitles(["Mow"]) == ["Done: Mow"])
        #expect(OneTapServices.doneTitles(["Mow", "Trim", "Edge"]) == [
            "Done: Mow, Trim, Edge",
            "Done: Mow, Trim +1 more",
            "Done: Mow +2 more",
        ])
        #expect(OneTapServices.doneTitles([]).isEmpty)
    }

    @Test func voiceOverReadsEveryName() {
        let label = OneTapServices.doneAccessibilityLabel(["Mow", "Trim", "Edge"])
        for name in ["Mow", "Trim", "Edge"] { #expect(label.contains(name)) }
        #expect(!label.contains("more"))
    }

    // MARK: - What it records

    /// The same stop's work, recorded two ways: the one tap, and Record
    /// Services' Add Expected then Save, followed by an ordinary Complete.
    /// The records' lines are identical, at the same prices.
    @Test func oneTapRecordsWhatAddExpectedAndSaveWould() throws {
        let h = try Harness(stopCount: 3)
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops

        // Stop 0: the one tap.
        let tap = try button(h, store)
        store.completeCurrentStop(expecting: stops[0].id, recordingServices: tap.recordedServiceIDs)

        // Stop 1: Record Services as the sheet builds it, Add Expected, Save.
        let client = h.clients[1]
        let active = ServiceLog.activeServices(try allServices(h), operatorID: "op")
        let zones = Place.of(client, propertyID: stops[1].propertyID)?.zones ?? []
        var sheet = StopRecording(services: active, zones: zones)
        OneTapServices.expectedInCatalog(StopServices.expected(for: stops[1], client: client), active: active)
            .forEach { sheet.selectedIDs.insert($0.id) }
        ServiceLog.saveRecording(sheet, notes: "", for: stops[1], of: client, run: try #require(store.runID),
                                 operatorID: "op", startedAt: try #require(store.stopStartedAt), in: h.context)
        store.completeCurrentStop(expecting: stops[1].id)

        let tapped = try #require(try record(h, store, stop: stops[0]))
        let saved = try #require(try record(h, store, stop: stops[1]))
        #expect(!tapped.lines.isEmpty)
        #expect(tapped.lines == saved.lines)
        #expect(tapped.lines.map(\.name) == ["Mow", "Edge"])
        #expect(tapped.lines.map(\.price) == [40, 21.35])   // 1,234 sq ft at $0.0173
        #expect(stops[0].completedServiceIDs == stops[1].completedServiceIDs)
        #expect(stops[0].completedServiceIDs == [c.mow.id.uuidString, c.edge.id.uuidString])
        // No invoice made.
        #expect(try h.context.fetch(FetchDescriptor<Proposal>()).isEmpty)
        #expect(tapped.invoiceID.isEmpty)
    }

    /// Send or Skip in the text-next-client sheet: NotifyAdvance completes
    /// the stop with the services the button named.
    @Test func sendOrSkipRecordsTheNamedServices() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let named = try button(h, store).recordedServiceIDs
        #expect(NotifyAdvance.run(completing: stop.id, recording: named, store: store) == .movedOn)
        #expect(stop.completedServiceIDs == named)
        #expect(try record(h, store, stop: stop)?.lines.count == 2)
    }

    /// Cancel in the sheet calls nothing: the button staged nothing before
    /// the completion, so nothing is recorded and it still reads "Done:".
    @Test func cancelRecordsNothing() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let before = try button(h, store)
        // The sheet opens with the named services held by the screen, then is cancelled.
        _ = before.recordedServiceIDs
        #expect(store.currentStopID == stop.id)
        #expect(stop.completedServiceIDs.isEmpty)
        #expect(try records(h).isEmpty)
        #expect(try button(h, store) == before)
        // A heads-up (no stop to complete) records nothing either.
        #expect(NotifyAdvance.run(completing: nil, recording: before.recordedServiceIDs, store: store) == .confirmed)
        #expect(stop.completedServiceIDs.isEmpty)
        #expect(try records(h).isEmpty)
    }

    /// iCloud changed the current stop underneath: nothing is recorded, on
    /// either stop.
    @Test func aChangedStopRecordsNothing() throws {
        let h = try Harness(stopCount: 3)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        let named = try button(h, store).recordedServiceIDs
        // Stop 0 removed on another device while its button showed.
        h.context.delete(stops[0])
        try h.context.save()
        #expect(store.completeCurrentStop(expecting: stops[0].id, recordingServices: named) == .stopChanged)
        #expect(NotifyAdvance.run(completing: stops[0].id, recording: named, store: store) == .stopChanged)
        #expect(stops[1].completedServiceIDs.isEmpty)
        #expect(try records(h).isEmpty)
    }

    @Test func undoTakesTheServicesBackOff() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let before = try button(h, store)
        h.clock += 300
        store.completeCurrentStop(expecting: stop.id, recordingServices: before.recordedServiceIDs)
        #expect(!stop.completedServiceIDs.isEmpty)
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(store.currentStopID == stop.id)
        #expect(stop.completedServiceIDs.isEmpty)
        #expect(try records(h).isEmpty)
        #expect(try button(h, store) == before)
    }

    /// A record made before the stop was completed (Record Services saved a
    /// note, no services): Undo puts it back with no services.
    @Test func undoLeavesAnEarlierRecordWithoutServices() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let sheet = StopRecording(services: ServiceLog.activeServices(try allServices(h), operatorID: "op"), zones: [])
        ServiceLog.saveRecording(sheet, notes: "Gate code 1234", for: stop, of: h.client,
                                 run: try #require(store.runID), operatorID: "op",
                                 startedAt: try #require(store.stopStartedAt), in: h.context)
        let before = try button(h, store)
        #expect(before.recordedServiceIDs.count == 2)
        store.completeCurrentStop(expecting: stop.id, recordingServices: before.recordedServiceIDs)
        let saved = try #require(try record(h, store, stop: stop))
        #expect(saved.lines.count == 2)
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(saved.lines.isEmpty)
        #expect(saved.notes == "Gate code 1234")
        #expect(stop.completedServiceIDs.isEmpty)
        #expect(try button(h, store) == before)
    }

    @Test func undoAfterAnOrdinaryCompletionIsUnchanged() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        store.completeCurrentStop(expecting: stop.id)
        let saved = try #require(try record(h, store, stop: stop))
        #expect(saved.lines.isEmpty)
        #expect(stop.completedServiceIDs.isEmpty)
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(try records(h).isEmpty)
        #expect(store.currentStopID == stop.id)
    }

    // MARK: - Completions from outside the route screen

    @Test func siriAndControlCenterRecordNoServices() throws {
        let h = try Harness(stopCount: 3)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        #expect(CompleteStopAction.siri(in: store, role: UserRole.business).completed)
        #expect(CompleteStopAction.controlCenter(stopID: stops[1].id, in: store, role: UserRole.business) == nil)
        #expect(store.currentStopID == stops[2].id)
        #expect(stops[0].completedServiceIDs.isEmpty && stops[1].completedServiceIDs.isEmpty)
        let made = try records(h)
        #expect(made.count == 2)
        #expect(made.allSatisfy { $0.lines.isEmpty })
    }

    @Test func belowTriggerRecordsNoServices() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let outcome = TriggerChecks.passBelowTrigger(stop, of: h.client, store: store, routeName: "Tuesday",
                                                     operatorID: "op", note: "", photos: [], in: h.context,
                                                     now: h.clock)
        #expect(outcome == .movedOn)
        #expect(stop.completedServiceIDs.isEmpty)
        #expect(try records(h).isEmpty)
    }
}
