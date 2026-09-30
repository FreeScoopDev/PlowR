//
//  TextLogTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// Texts sent to clients from PlowR, kept for their Timeline.
@MainActor
struct TextLogTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    @Test func aTextIsKeptForEachClientOnFileOnce() throws {
        let h = try Harness(stopCount: 2)
        let stops = h.route.sortedStops
        let oneTime = UUID()                                                      // a one-time stop: no client
        TextLog.record(.routeMessage, body: "  Running late  ", to: stops.map(\.clientID) + [stops[0].clientID, oneTime],
                       in: h.context, now: h.clock)
        let texts = try h.context.fetch(FetchDescriptor<SentText>())
        #expect(texts.count == 2)
        #expect(Set(texts.map(\.clientID)) == Set(stops.map(\.clientID.uuidString)))
        #expect(texts.allSatisfy { $0.body == "Running late" && $0.kind == "routeMessage" && $0.sentAt == h.clock })
        #expect(texts.allSatisfy { $0.operatorID == "op" })
        let names = Dictionary(uniqueKeysWithValues: texts.map { ($0.clientID, $0.clientName) })
        for stop in stops { #expect(names[stop.clientID.uuidString] == stop.clientName) }
    }

    @Test func textsAreOnTheClientsTimelineNewestFirst() throws {
        let h = try Harness(stopCount: 0)
        TextLog.record(.invoiceReminder, body: "Hi, a reminder that invoice INV-0003 is due.", to: [h.client.id],
                       in: h.context, now: h.clock.addingTimeInterval(-60))
        TextLog.record(.text, body: "", to: [h.client.id], in: h.context, now: h.clock)
        let texts = ClientTimeline.events(for: h.client, now: h.clock, in: h.context).filter { $0.kind == .text }
        #expect(texts.map(\.title) == ["Text sent", "Invoice reminder sent"])
        #expect(texts.last?.detail == "Hi, a reminder that invoice INV-0003 is due.")
        #expect(texts.first?.detail == "")
    }

    @Test func aLongTextIsShortenedOnTheTimeline() throws {
        let h = try Harness(stopCount: 0)
        TextLog.record(.heading, body: "first line\n" + String(repeating: "a", count: 100), to: [h.client.id],
                       in: h.context, now: h.clock)
        let text = try #require(ClientTimeline.events(for: h.client, now: h.clock, in: h.context).first { $0.kind == .text })
        #expect(text.detail.count == 80)
        #expect(text.detail.hasSuffix("…"))
        #expect(!text.detail.contains("\n"))
        #expect(text.title == "Heads-up sent")
    }

    // The texts sent a client go with them, as their photos do.
    @Test func deletingAClientDeletesTheTextsSentThem() throws {
        let h = try Harness(stopCount: 1)
        let other = Client(name: "Bo", phone: "", address: "", operatorID: "op")
        h.context.insert(other)
        TextLog.record(.text, body: "", to: [h.client.id, other.id], in: h.context, now: h.clock)
        ClientRemoval.delete(h.client, keepingRecords: true, in: h.context)
        #expect(try h.context.fetch(FetchDescriptor<SentText>()).map(\.clientID) == [other.id.uuidString])
    }

    // Message All one at a time: each text sent is its recipient's client's;
    // one not sent is nobody's.
    @Test func aRunsTextIsItsRecipientsClients() {
        let client = UUID()
        let run = MessageRun([MessageRun.Recipient(id: UUID(), phone: "555-0100", clientID: client)])
        #expect(run.textedClient(.sent) == client)
        #expect(run.textedClient(.cancelled) == nil)
        #expect(run.textedClient(.failed) == nil)
    }
}
