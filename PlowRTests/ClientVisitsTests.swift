//
//  ClientVisitsTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A client's upcoming visits follow the client's name and address, as
/// their route stops do; past visits keep where the work was done. A visit
/// used to keep the address it was booked with.
@MainActor
struct ClientVisitsTests {
    /// Kept: a container that goes away resets its context, and every model
    /// in it is destroyed.
    let container: ModelContainer
    let context: ModelContext
    let pat: Client
    let sam: Client

    init() throws {
        container = try ModelContainer(
            for: Client.self, PlowRoute.self, RouteStop.self, ScheduledVisit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        context = container.mainContext
        pat = Client(name: "Pat Doe", phone: "555-0100", address: "1 Main St", operatorID: "op")
        sam = Client(name: "Sam Roe", phone: "555-0200", address: "2 Elm St", operatorID: "op")
        context.insert(pat)
        context.insert(sam)
        try context.save()
    }

    @discardableResult
    private func visit(_ client: Client, _ status: VisitStatus = .scheduled, daysFromNow days: Double) -> ScheduledVisit {
        let visit = ScheduledVisit(operatorID: "op", clientID: client.id.uuidString, clientName: client.name,
                                   clientAddress: client.address, scheduledDate: Date().addingTimeInterval(days * 86_400))
        visit.status = status
        context.insert(visit)
        return visit
    }

    @Test func upcomingVisitsTakeTheNewNameAndAddress() throws {
        let next = visit(pat, daysFromNow: 3)
        let later = visit(pat, daysFromNow: 10)
        let done = visit(pat, .completed, daysFromNow: -7)
        let missed = visit(pat, daysFromNow: -2)              // dated in the past: a record
        let doneEarly = visit(pat, .completed, daysFromNow: 1)
        let sams = visit(sam, daysFromNow: 3)
        pat.name = "Pat Doe-Smith"
        pat.address = "12 Pleasant St"
        ClientStops.update(for: pat)                          // every place a client changes calls this
        for upcoming in [next, later] {
            #expect(upcoming.clientName == "Pat Doe-Smith")
            #expect(upcoming.clientAddress == "12 Pleasant St")
        }
        for record in [done, missed, doneEarly] {
            #expect(record.clientName == "Pat Doe")
            #expect(record.clientAddress == "1 Main St")
        }
        #expect(sams.clientAddress == "2 Elm St")
    }

    // In the sweeps (launch, back to the front, iCloud changes): visits that
    // fell behind catch up, and it's saved.
    @Test func visitsThatFellBehindCatchUpInTheSweep() throws {
        let next = visit(pat, daysFromNow: 3)
        let past = visit(pat, daysFromNow: -3)
        try context.save()
        pat.address = "12 Pleasant St"                        // changed without update(for:)
        ClientStops.updateAll(in: context)
        #expect(next.clientAddress == "12 Pleasant St")
        #expect(past.clientAddress == "1 Main St")
        #expect(!context.hasChanges)                          // saved
    }

    @Test func anUnchangedVisitIsntWritten() throws {
        let next = visit(pat, daysFromNow: 3)
        try context.save()
        #expect(!ClientVisits.follow(next, pat))
        #expect(!ClientVisits.updateAll(in: context))
        ClientStops.update(for: pat)
        #expect(!context.hasChanges)
    }
}
