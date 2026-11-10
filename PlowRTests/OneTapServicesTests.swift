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
            "Done: 3 services",
        ])
        #expect(OneTapServices.doneTitles([]).isEmpty)
    }

    /// The last form is the one shown, made smaller, when nothing fits: it
    /// must say how many are recorded, never a name with others hidden.
    @Test func theLastFormStatesTheCount() {
        for names in [["Mow", "Trim"], ["Mow", "Trim", "Edge", "Rake", "Haul"]] {
            let last = OneTapServices.doneTitles(names).last
            #expect(last == "Done: \(names.count) services")
        }
        // One service: its own name, nothing hidden beside it.
        #expect(OneTapServices.doneTitles(["Fertilization"]).last == "Done: Fertilization")
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
        // Trim shares Mow's place in the catalog: the tie is broken by ID,
        // the same way in both paths.
        let trim = ServiceItem(name: "Trim", category: "lawn", unitType: "flat", pricePerUnit: 25, operatorID: "op",
                               sortOrder: 1)
        h.context.insert(trim)
        for client in h.clients { client.expectedServiceIDs.append(trim.id.uuidString) }
        try h.context.save()
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
        let tied = [c.mow, trim].sorted { $0.id.uuidString < $1.id.uuidString }
        #expect(tapped.lines.map(\.name) == tied.map(\.name) + ["Edge"])
        #expect(tapped.lines.map(\.price) == tied.map(\.pricePerUnit) + [21.35])   // 1,234 sq ft at $0.0173
        #expect(stops[0].completedServiceIDs == stops[1].completedServiceIDs)
        #expect(stops[0].completedServiceIDs == tied.map(\.id.uuidString) + [c.edge.id.uuidString])
        // No invoice made.
        #expect(try h.context.fetch(FetchDescriptor<Proposal>()).isEmpty)
        #expect(tapped.invoiceID.isEmpty)
    }

    /// Send or Skip in the text-next-client sheet, opened from the "Done:"
    /// button: the stop drawn on the card is completed with its services.
    @Test func sendOrSkipRecordsTheNamedServices() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let named = try button(h, store).recordedServiceIDs
        let sheet = NotifyAdvance.Completion.button(drawnStop: stop.id, recording: named)
        #expect(sheet.run(store: store) == .movedOn)
        #expect(stop.completedServiceIDs == named)
        #expect(try record(h, store, stop: stop)?.lines.count == 2)
    }

    /// Cancel drops what the sheet would complete: nothing is recorded, the
    /// button still reads "Done:", and the services can't reach a later
    /// sheet, such as the one offered after leaving the stop's area.
    @Test func cancelRecordsNothingAndLeavesNothingBehind() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let before = try button(h, store)
        var sheet = NotifyAdvance.Completion.button(drawnStop: stop.id, recording: before.recordedServiceIDs)
        sheet = sheet.cancelled()
        #expect(sheet == .nothing)
        #expect(sheet.run(store: store) == .confirmed)
        #expect(store.currentStopID == stop.id)
        #expect(stop.completedServiceIDs.isEmpty)
        #expect(try records(h).isEmpty)
        #expect(try button(h, store) == before)
        // Then the exit offer, made anew: it names and records the stop's
        // services by its own reckoning, nothing carried from the cancelled sheet.
        sheet = try exitOffer(h, store)
        #expect(sheet.serviceIDs == before.recordedServiceIDs)
        #expect(sheet.run(store: store) == .movedOn)
        #expect(stop.completedServiceIDs == before.recordedServiceIDs)
    }

    /// Every way of opening the sheet sets both the stop and the services.
    @Test func everyWayOfOpeningTheSheetSetsBoth() {
        let drawn = UUID()
        let fromButton = NotifyAdvance.Completion.button(drawnStop: drawn, recording: ["a", "b"])
        #expect(fromButton.stopID == drawn && fromButton.serviceIDs == ["a", "b"])
        let without = NotifyAdvance.Completion.button(drawnStop: drawn, recording: [])
        #expect(without.stopID == drawn && without.serviceIDs.isEmpty)
        let exit = NotifyAdvance.Completion.exitOffer(leftStop: drawn, clientName: "Client 0",
                                                      main: .done(serviceIDs: ["a", "b"], names: ["A", "B"]))
        #expect(exit.stopID == drawn && exit.serviceIDs == ["a", "b"] && exit.notice != nil)
        let plain = NotifyAdvance.Completion.exitOffer(leftStop: drawn, clientName: "Client 0", main: .completeAndText)
        #expect(plain.stopID == drawn && plain.serviceIDs.isEmpty && plain.notice != nil)
        #expect(NotifyAdvance.Completion.headsUp.stopID == nil && NotifyAdvance.Completion.headsUp.serviceIDs.isEmpty)
        #expect(fromButton.cancelled() == .nothing)
        #expect(exit.cancelled() == .nothing)
    }

    /// The card was drawn for A; by the tap, iCloud had removed A and B was
    /// current. The completion names A, so nothing is recorded, and A's
    /// services never go to B.
    @Test func aTapDrawnForAStopNoLongerCurrentRecordsNothing() throws {
        let h = try Harness(stopCount: 3)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        let drawn = NotifyAdvance.Completion.button(drawnStop: stops[0].id,
                                                    recording: try button(h, store).recordedServiceIDs)
        h.context.delete(stops[0])
        try h.context.save()
        #expect(store.currentStopID == stops[1].id)
        #expect(drawn.run(store: store) == .stopChanged)
        #expect(store.currentStopID == stops[1].id)
        #expect(stops[1].completedServiceIDs.isEmpty)
        #expect(try records(h).isEmpty)
        // Complete Without Services (and the ordinary Complete) the same way.
        #expect(NotifyAdvance.Completion.button(drawnStop: stops[0].id, recording: []).run(store: store) == .stopChanged)
        #expect(store.currentStopID == stops[1].id)
        #expect(try records(h).isEmpty)
    }

    /// Drawn for A, but Siri completed A meanwhile: B isn't completed, and
    /// gets nothing.
    @Test func aTapDrawnForAStopSiriCompletedRecordsNothingOnTheNext() throws {
        let h = try Harness(stopCount: 3)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        let drawn = NotifyAdvance.Completion.button(drawnStop: stops[0].id,
                                                    recording: try button(h, store).recordedServiceIDs)
        #expect(CompleteStopAction.siri(in: store, role: UserRole.business).completed)
        #expect(drawn.run(store: store) == .movedOn)
        #expect(store.currentStopID == stops[1].id)
        #expect(stops[0].completedServiceIDs.isEmpty && stops[1].completedServiceIDs.isEmpty)
        #expect(try records(h).allSatisfy { $0.lines.isEmpty })
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

    /// Record Services saved a service, then the stop was completed the
    /// ordinary way: Undo leaves that service on the stop and its record.
    @Test func undoAfterAnOrdinaryCompletionKeepsServicesRecordedBefore() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let sheet = StopRecording(services: ServiceLog.activeServices(try allServices(h), operatorID: "op"),
                                  zones: [], selectedIDs: [c.mow.id.uuidString],
                                  typedPrices: [c.mow.id.uuidString: "55"])
        ServiceLog.saveRecording(sheet, notes: "", for: stop, of: h.client, run: try #require(store.runID),
                                 operatorID: "op", startedAt: try #require(store.stopStartedAt), in: h.context)
        #expect(try button(h, store) == .completeAndText)
        store.completeCurrentStop(expecting: stop.id)
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(stop.completedServiceIDs == [c.mow.id.uuidString])
        let saved = try #require(try record(h, store, stop: stop))
        #expect(saved.lines.map(\.name) == ["Mow"])
        #expect(saved.lines.map(\.price) == [55])
    }

    /// A service deleted from the catalog after the button named it gets
    /// no line, and isn't counted as recorded on the stop.
    @Test func aServiceDeletedBeforeTheTapIsntCountedAsRecorded() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let named = try button(h, store).recordedServiceIDs
        #expect(named == [c.mow.id.uuidString, c.edge.id.uuidString])
        let mowID = c.mow.id.uuidString
        h.context.delete(c.edge)
        try h.context.save()
        store.completeCurrentStop(expecting: stop.id, recordingServices: named)
        #expect(stop.completedServiceIDs == [mowID])
        #expect(try record(h, store, stop: stop)?.lines.map(\.serviceID) == [mowID])
        // Undo still takes it back off.
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(stop.completedServiceIDs.isEmpty)
    }

    /// The screen redraws on every GPS fix: the database is read again only
    /// when something the button depends on changed.
    @Test func theButtonIsWorkedOutAgainOnlyWhenSomethingChanged() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let memo = MainButtonMemo()
        func draw(_ version: Int) throws -> OneTapServices.MainButton {
            OneTapServices.mainButton(for: stop, client: h.client, catalog: try allServices(h), operatorID: "op",
                                      store: store, skipsText: false, in: h.context, memo: memo, dataVersion: version)
        }
        let first = try draw(0)
        #expect(first.recordedServiceIDs.count == 2)
        _ = try draw(0)
        _ = try draw(0)
        #expect(memo.computed == 1)
        // A record with services, made elsewhere and saved: the next version reads it.
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        visit.expectedServiceIDs = first.recordedServiceIDs
        h.context.insert(visit)
        _ = try #require(ServiceLog.complete(visit, among: [visit], in: h.context, now: h.clock))
        try h.context.save()
        #expect(try draw(1) == .completeAndText)
        #expect(memo.computed == 2)
        // The stop's own services are part of what it depends on.
        stop.completedServiceIDs = ["x"]
        _ = try draw(1)
        #expect(memo.computed == 3)
    }

    // MARK: - The text offered after leaving a stop

    /// The exit offer for the store's current stop, as the route screen
    /// opens it once the phone has left that stop's area.
    /// Built from the card's button, worked out afresh (no memo).
    private func exitOffer(_ h: Harness, _ store: ActiveRouteStore,
                           skipsText: Bool = false) throws -> NotifyAdvance.Completion {
        let stop = try #require(store.currentStop)
        return NotifyAdvance.Completion.exitOffer(leftStop: stop.id, clientName: stop.clientName,
                                                  main: try button(h, store, skipsText: skipsText))
    }

    /// The sentence for a stop whose button records nothing new.
    private func nothingNew(_ name: String) -> String {
        OneTapServices.exitOfferNotice(clientName: name, names: [])
    }

    /// A stop whose button is "Done:": the exit offer names the same
    /// services, every one, for the stop left, and will record those.
    @Test func theExitOfferNamesTheServicesTheButtonWould() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let main = try button(h, store)
        let offer = try exitOffer(h, store)
        #expect(offer.stopID == stop.id)
        #expect(offer.serviceIDs == main.recordedServiceIDs)
        #expect(offer.serviceIDs == [c.mow.id.uuidString, c.edge.id.uuidString])
        #expect(offer.notice == OneTapServices.exitOfferNotice(clientName: "Client 0", names: ["Mow", "Edge"]))
        // Whether the next client skips texts changes nothing recorded.
        #expect(try exitOffer(h, store, skipsText: true) == offer)
    }

    /// Every way the button is the ordinary Complete: the exit offer records
    /// nothing new, and says so.
    @Test func theExitOfferRecordsNothingNewWhereTheButtonIsOrdinary() throws {
        // No expected services.
        do {
            let h = try Harness(stopCount: 2)
            let store = h.makeStore()
            store.start(h.route)
            let offer = try exitOffer(h, store)
            #expect(offer.stopID == store.currentStopID)
            #expect(offer.serviceIDs.isEmpty)
            #expect(offer.notice == nothingNew("Client 0"))
        }
        // Something already recorded.
        do {
            let h = try Harness(stopCount: 2)
            let c = try catalog(h)
            let store = h.makeStore()
            store.start(h.route)
            let stop = try #require(store.currentStop)
            let recording = StopRecording(services: ServiceLog.activeServices(try allServices(h), operatorID: "op"),
                                          zones: [], selectedIDs: [c.mow.id.uuidString])
            ServiceLog.saveRecording(recording, notes: "", for: stop, of: h.client, run: try #require(store.runID),
                                     operatorID: "op", startedAt: try #require(store.stopStartedAt), in: h.context)
            let offer = try exitOffer(h, store)
            #expect(offer.serviceIDs.isEmpty)
            #expect(offer.notice == nothingNew("Client 0"))
            #expect(offer.run(store: store) == .movedOn)
            #expect(stop.completedServiceIDs == [c.mow.id.uuidString])
            #expect(try record(h, store, stop: stop)?.lines.map(\.name) == ["Mow"])
        }
        // Work already on an invoice.
        do {
            let h = try Harness(stopCount: 2)
            try catalog(h)
            let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                       clientAddress: h.client.address, scheduledDate: h.clock)
            h.context.insert(visit)
            let invoice = Proposal(operatorID: "op", client: h.client)
            invoice.invoiceNumber = "INV-0041"
            h.context.insert(invoice)
            visit.proposalID = invoice.id.uuidString
            try h.context.save()
            let store = h.makeStore()
            store.start(h.route)
            let offer = try exitOffer(h, store)
            #expect(offer.serviceIDs.isEmpty)
            #expect(offer.notice == nothingNew("Client 0"))
        }
        // A custom stop.
        do {
            let h = try Harness(stopCount: 1)
            let c = try catalog(h)
            let custom = RouteStop(order: 1, customName: "Depot")
            custom.route = h.route
            h.context.insert(custom)
            StopServices.setForThisRoute([c.mow.id.uuidString], on: custom)
            let last = RouteStop(order: 2, customName: "Yard")
            last.route = h.route
            h.context.insert(last)
            try h.context.save()
            let store = h.makeStore()
            store.start(h.route)
            store.completeShownStop()
            #expect(store.currentStopID == custom.id)
            let offer = try exitOffer(h, store)
            #expect(offer.serviceIDs.isEmpty)
            #expect(offer.notice == nothingNew("Depot"))
        }
    }

    /// Send or Skip on the exit offer records exactly what the "Done:"
    /// button would have, for the same stop's work: identical lines.
    @Test func theExitOfferRecordsWhatTheDoneButtonWould() throws {
        let h = try Harness(stopCount: 3)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        // Stop 0: the "Done:" button, through the text sheet.
        let tapped = NotifyAdvance.Completion.button(drawnStop: stops[0].id,
                                                     recording: try button(h, store).recordedServiceIDs)
        #expect(tapped.notice == nil)
        #expect(tapped.run(store: store) == .movedOn)
        // Stop 1: drove off, then Send or Skip on the exit offer.
        let offer = try exitOffer(h, store)
        #expect(offer.stopID == stops[1].id)
        #expect(offer.run(store: store) == .movedOn)
        #expect(store.currentStopID == stops[2].id)

        let byButton = try #require(try record(h, store, stop: stops[0]))
        let byExit = try #require(try record(h, store, stop: stops[1]))
        #expect(!byExit.lines.isEmpty)
        #expect(byExit.lines == byButton.lines)
        #expect(stops[1].completedServiceIDs == stops[0].completedServiceIDs)
        #expect(stops[1].completedServiceIDs == offer.serviceIDs)
        #expect(try h.context.fetch(FetchDescriptor<Proposal>()).isEmpty)
    }

    /// Cancel on the exit offer completes nothing and records nothing: the
    /// card still has "Done:" and Complete Without Services.
    @Test func cancellingTheExitOfferRecordsNothing() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let before = try button(h, store)
        let sheet = try exitOffer(h, store).cancelled()
        #expect(sheet == .nothing)
        #expect(sheet.run(store: store) == .confirmed)
        #expect(store.currentStopID == stop.id)
        #expect(stop.completedServiceIDs.isEmpty)
        #expect(try records(h).isEmpty)
        #expect(try button(h, store) == before)
        #expect(before.offersCompletingWithout)
    }

    /// The route moved on while the exit offer was up: iCloud removed the
    /// stop left, or Siri completed it. Send or Skip records nothing, on
    /// either stop.
    @Test func anExitOfferForAStopNoLongerCurrentRecordsNothing() throws {
        do {
            let h = try Harness(stopCount: 3)
            try catalog(h)
            let store = h.makeStore()
            store.start(h.route)
            let stops = h.route.sortedStops
            let offer = try exitOffer(h, store)
            #expect(!offer.serviceIDs.isEmpty)
            h.context.delete(stops[0])
            try h.context.save()
            #expect(store.currentStopID == stops[1].id)
            #expect(offer.run(store: store) == .stopChanged)
            #expect(store.currentStopID == stops[1].id)
            #expect(stops[1].completedServiceIDs.isEmpty)
            #expect(try records(h).isEmpty)
        }
        do {
            let h = try Harness(stopCount: 3)
            try catalog(h)
            let store = h.makeStore()
            store.start(h.route)
            let stops = h.route.sortedStops
            let offer = try exitOffer(h, store)
            #expect(CompleteStopAction.siri(in: store, role: UserRole.business).completed)
            #expect(offer.run(store: store) == .movedOn)
            #expect(store.currentStopID == stops[1].id)
            #expect(stops[0].completedServiceIDs.isEmpty && stops[1].completedServiceIDs.isEmpty)
            #expect(try records(h).allSatisfy { $0.lines.isEmpty })
        }
    }

    /// Services recorded in Record Services while the exit offer was up:
    /// the store's re-check records nothing more.
    @Test func servicesRecordedWhileTheExitOfferIsUpAreKept() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let offer = try exitOffer(h, store)
        #expect(offer.serviceIDs.count == 2)
        let recording = StopRecording(services: ServiceLog.activeServices(try allServices(h), operatorID: "op"),
                                      zones: [], selectedIDs: [c.mow.id.uuidString],
                                      typedPrices: [c.mow.id.uuidString: "55"])
        ServiceLog.saveRecording(recording, notes: "", for: stop, of: h.client, run: try #require(store.runID),
                                 operatorID: "op", startedAt: try #require(store.stopStartedAt), in: h.context)
        #expect(offer.run(store: store) == .movedOn)
        #expect(stop.completedServiceIDs == [c.mow.id.uuidString])
        #expect(try record(h, store, stop: stop)?.lines.map(\.price) == [55])
    }

    @Test func undoAfterTheExitOfferTakesTheServicesBackOff() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let before = try button(h, store)
        h.clock += 300
        #expect(try exitOffer(h, store).run(store: store) == .movedOn)
        #expect(stop.completedServiceIDs == before.recordedServiceIDs)
        #expect(store.undoLastCompletion(expecting: stop.id) == .undone)
        #expect(store.currentStopID == stop.id)
        #expect(stop.completedServiceIDs.isEmpty)
        #expect(try records(h).isEmpty)
        #expect(try button(h, store) == before)
    }

    /// The heads-up after Below Trigger completes nothing and says nothing
    /// about services; a sheet opened from a button says nothing more than
    /// the button did.
    @Test func onlyTheExitOfferHasASentence() throws {
        let headsUp = NotifyAdvance.Completion.headsUp
        #expect(headsUp.stopID == nil && headsUp.serviceIDs.isEmpty && headsUp.notice == nil)
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        #expect(headsUp.run(store: store) == .confirmed)
        #expect(store.currentStopID == h.route.sortedStops[0].id)
        #expect(try records(h).isEmpty)
        let stop = try #require(store.currentStop)
        #expect(NotifyAdvance.Completion.button(drawnStop: stop.id, recording: ["a"]).notice == nil)
        #expect(NotifyAdvance.Completion.button(drawnStop: stop.id, recording: []).notice == nil)
    }

    /// What the exit offer's sheet says, word for word.
    @Test func theExitOfferSentence() {
        #expect(OneTapServices.exitOfferNotice(clientName: "Pat Lee", names: ["Mow"])
                == "Send Message or Complete Without Text completes the stop for Pat Lee and records Mow."
                    + " To complete it without that service, tap Cancel and choose on the stop.")
        #expect(OneTapServices.exitOfferNotice(clientName: "Pat Lee", names: ["Mow", "Edge"])
                == "Send Message or Complete Without Text completes the stop for Pat Lee and records Mow and Edge."
                    + " To complete it without them, tap Cancel and choose on the stop.")
        #expect(OneTapServices.exitOfferNotice(clientName: "Pat Lee", names: ["Mow", "Trim", "Edge"])
                == "Send Message or Complete Without Text completes the stop for Pat Lee and records Mow, Trim, and Edge."
                    + " To complete it without them, tap Cancel and choose on the stop.")
        #expect(OneTapServices.exitOfferNotice(clientName: "Pat Lee", names: [])
                == "Send Message or Complete Without Text completes the stop for Pat Lee and adds no services."
                    + " Tap Cancel to stay on that stop.")
        // Every name, however many: nothing shortened to "+N more".
        let many = ["Mow", "Trim", "Edge", "Rake", "Haul", "Blow"]
        let sentence = OneTapServices.exitOfferNotice(clientName: "Pat Lee", names: many)
        for name in many { #expect(sentence.contains(name)) }
        #expect(!sentence.contains("more"))
    }

    /// The app's copy is English only: a list reads in English on a device
    /// set to another language or region, where the system's own list
    /// would not ("Mow, Trim et Edge" in French).
    @Test func listsAreEnglishWhateverTheDevicesRegion() {
        let names = ["Mow", "Trim", "Edge"]
        let french = names.formatted(.list(type: .and).locale(Locale(identifier: "fr_FR")))
        #expect(french != "Mow, Trim, and Edge")
        #expect(OneTapServices.copyLocale.language.languageCode == .english)
        #expect(OneTapServices.englishList(names) == "Mow, Trim, and Edge")
        #expect(OneTapServices.doneAccessibilityLabel(names) == "Done: complete and record Mow, Trim, and Edge")
        #expect(OneTapServices.notRecordedNote(clientName: "Pat Lee", names: names)?
            .hasPrefix("Mow, Trim, and Edge weren't") == true)
    }

    // MARK: - Saying what the exit offer didn't record

    /// The note after Send or Skip, word for word.
    @Test func theNotRecordedNote() {
        #expect(OneTapServices.notRecordedNote(clientName: "Pat Lee", names: []) == nil)
        #expect(OneTapServices.notRecordedNote(clientName: "Pat Lee", names: ["Edge"])
                == "Edge wasn't recorded for Pat Lee. If it was done, add it from the Route Recap"
                    + " when you finish the route.")
        #expect(OneTapServices.notRecordedNote(clientName: "Pat Lee", names: ["Mow", "Edge"])
                == "Mow and Edge weren't recorded for Pat Lee. If they were done, add them from the Route Recap"
                    + " when you finish the route.")
    }

    /// Everything named was recorded: nothing to say.
    @Test func allRecordedLeavesNoNote() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let result = try exitOffer(h, store).runNotingUnrecorded(store: store)
        #expect(result.outcome == .movedOn)
        #expect(result.notRecorded.isEmpty)
    }

    /// A named service deleted from the catalog between the sheet opening
    /// and Send: that one is named as not recorded.
    @Test func aServiceDeletedMeanwhileIsNamedAsNotRecorded() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let offer = try exitOffer(h, store)
        #expect(offer.serviceNames == ["Mow", "Edge"])
        h.context.delete(c.edge)
        try h.context.save()
        let result = offer.runNotingUnrecorded(store: store)
        #expect(result.outcome == .movedOn)
        #expect(result.notRecorded == ["Edge"])
    }

    /// Record Services saved Mow while the sheet was up: the store adds
    /// nothing, and only Edge, which isn't on the stop, is reported. Mow is
    /// recorded, so the note mustn't say it wasn't.
    @Test func aServiceRecordedMeanwhileIsNotReportedAsMissing() throws {
        let h = try Harness(stopCount: 2)
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stop = try #require(store.currentStop)
        let offer = try exitOffer(h, store)
        let recording = StopRecording(services: ServiceLog.activeServices(try allServices(h), operatorID: "op"),
                                      zones: [], selectedIDs: [c.mow.id.uuidString])
        ServiceLog.saveRecording(recording, notes: "", for: stop, of: h.client, run: try #require(store.runID),
                                 operatorID: "op", startedAt: try #require(store.stopStartedAt), in: h.context)
        let result = offer.runNotingUnrecorded(store: store)
        #expect(result.outcome == .movedOn)
        #expect(result.notRecorded == ["Edge"])
    }

    /// Work invoiced while the sheet was up: nothing added, every name reported.
    @Test func workInvoicedMeanwhileNamesThemAll() throws {
        let h = try Harness(stopCount: 2)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let offer = try exitOffer(h, store)
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock)
        h.context.insert(visit)
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0042"
        h.context.insert(invoice)
        visit.proposalID = invoice.id.uuidString
        try h.context.save()
        #expect(offer.runNotingUnrecorded(store: store).notRecorded == ["Mow", "Edge"])
    }

    /// Siri completed the stop while the sheet was up: nothing was added
    /// by Send, so every name is reported.
    @Test func completedBySiriMeanwhileNamesThemAll() throws {
        let h = try Harness(stopCount: 3)
        try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let offer = try exitOffer(h, store)
        #expect(CompleteStopAction.siri(in: store, role: UserRole.business).completed)
        let result = offer.runNotingUnrecorded(store: store)
        #expect(result.outcome == .movedOn)
        #expect(result.notRecorded == ["Mow", "Edge"])
    }

    /// No note from a button's sheet, Cancel, the heads-up, an exit offer
    /// that named nothing, or a stop changed by sync (Route Changed says so).
    @Test func noNoteWhereTheSheetNamedNothingOrTheRouteChanged() throws {
        let h = try Harness(stopCount: 3)
        let c = try catalog(h)
        let store = h.makeStore()
        store.start(h.route)
        let stops = h.route.sortedStops
        let offer = try exitOffer(h, store)
        #expect(offer.cancelled().runNotingUnrecorded(store: store).notRecorded.isEmpty)
        #expect(NotifyAdvance.Completion.headsUp.runNotingUnrecorded(store: store).notRecorded.isEmpty)
        // A service deleted meanwhile, but the sheet came from the button.
        let tapped = NotifyAdvance.Completion.button(drawnStop: stops[0].id, recording: offer.serviceIDs)
        h.context.delete(c.edge)
        try h.context.save()
        let fromButton = tapped.runNotingUnrecorded(store: store)
        #expect(fromButton.outcome == .movedOn)
        #expect(fromButton.notRecorded.isEmpty)
        // Stop 1 expects nothing still in the catalog but Mow; remove the
        // stop under the offer: .stopChanged, no note.
        let second = try exitOffer(h, store)
        #expect(second.stopID == stops[1].id)
        h.context.delete(stops[1])
        try h.context.save()
        let changed = second.runNotingUnrecorded(store: store)
        #expect(changed.outcome == .stopChanged)
        #expect(changed.notRecorded.isEmpty)
        // An exit offer that named nothing.
        let plain = NotifyAdvance.Completion.exitOffer(leftStop: stops[2].id, clientName: "Client 2",
                                                       main: .completeRoute)
        #expect(plain.runNotingUnrecorded(store: store).notRecorded.isEmpty)
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
