//
//  ClientTimelineTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A client's timeline: jobs, visits, quotes, invoices and photos, newest first.
@MainActor
struct ClientTimelineTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    private func visit(_ h: Harness, hours: Double, _ status: VisitStatus) -> ScheduledVisit {
        let visit = ScheduledVisit(operatorID: "op", clientID: h.client.id.uuidString, clientName: h.client.name,
                                   clientAddress: h.client.address, scheduledDate: h.clock.addingTimeInterval(hours * 3_600))
        visit.status = status
        h.context.insert(visit)
        return visit
    }

    @Test func eachKindOfEventNewestFirst() throws {
        let h = try Harness(stopCount: 1)
        let job = ServiceRecord(operatorID: "op", sourceKey: "a", source: .route)
        job.clientID = h.client.id.uuidString
        job.performedAt = h.clock.addingTimeInterval(-3 * 3_600)
        job.lines = [.init(serviceID: "c", name: "Clear", unitType: "flat", price: 40)]
        job.routeName = "Tuesday"
        h.context.insert(job)
        _ = visit(h, hours: 48, .scheduled)                 // upcoming
        _ = visit(h, hours: -72, .scheduled)                // missed
        _ = visit(h, hours: -96, .skipped)
        _ = visit(h, hours: -120, .completed)               // its job stands for it: not an event
        let invoice = Proposal(operatorID: "op", client: h.client)
        invoice.invoiceNumber = "INV-0004"
        invoice.createdAt = h.clock.addingTimeInterval(-2 * 3_600)
        invoice.invoiceSentAt = h.clock.addingTimeInterval(-3_600)
        invoice.invoicePaidAt = h.clock.addingTimeInterval(-60)
        let quote = Proposal(operatorID: "op", client: h.client)
        quote.createdAt = h.clock.addingTimeInterval(-10 * 86_400)
        [invoice, quote].forEach { h.context.insert($0) }
        let photo = StopPhoto(operatorID: "op", clientID: h.client.id.uuidString, routeID: "", isBefore: true,
                              imageData: Data([1]))
        photo.takenAt = h.clock.addingTimeInterval(-3 * 3_600 - 60)
        h.context.insert(photo)
        let otherClients = ServiceRecord(operatorID: "op", sourceKey: "z", source: .manual)
        otherClients.clientID = UUID().uuidString
        h.context.insert(otherClients)

        let events = ClientTimeline.events(for: h.client, now: h.clock, in: h.context)
        // Typed up front: inferring the literal inside #expect timed out on Xcode Cloud.
        let expected: [ClientTimelineKind] = [
            .upcomingVisit,
            .invoicePaid(documentID: invoice.id), .invoiceSent(documentID: invoice.id),
            .invoiceMade(documentID: invoice.id),
            .job(recordID: job.id), .photos(count: 1),
            .missedVisit, .skippedVisit,
            .quote(documentID: quote.id),
        ]
        let kinds: [ClientTimelineKind] = events.map(\.kind)
        #expect(kinds == expected)
        let jobKind = ClientTimelineKind.job(recordID: job.id)
        let jobEvent = try #require(events.first { $0.kind == jobKind })
        #expect(jobEvent.title == "Clear")
        #expect(jobEvent.detail == "On Tuesday")
        #expect(jobEvent.amount == 40)
    }

    // Photos on one day are one event.
    @Test func aDaysPhotosAreOneEvent() throws {
        let h = try Harness(stopCount: 1)
        for minutes in [0.0, 5, 10] {
            let photo = StopPhoto(operatorID: "op", clientID: h.client.id.uuidString, routeID: "", isBefore: false,
                                  imageData: Data([1]))
            photo.takenAt = h.clock.addingTimeInterval(minutes * 60)
            h.context.insert(photo)
        }
        let events = ClientTimeline.events(for: h.client, now: h.clock, in: h.context)
        #expect(events.map(\.kind) == [.photos(count: 3)])
    }

    @Test func aNewClientHasNothing() throws {
        let h = try Harness(stopCount: 1)
        #expect(ClientTimeline.events(for: h.client, now: h.clock, in: h.context).isEmpty)
    }
}
