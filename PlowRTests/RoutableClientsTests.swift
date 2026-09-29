//
//  RoutableClientsTests.swift
//  PlowRTests
//

import Foundation
import Testing
@testable import PlowR

/// Which clients the route pickers offer. The 1.1.0 notes promised inactive
/// clients are hidden from route building; the pickers listed them anyway.
@MainActor
struct RoutableClientsTests {

    private func client(_ name: String, operatorID: String = "op", active: Bool = true) -> Client {
        let c = Client(name: name, phone: "", address: "", operatorID: operatorID)
        c.isActive = active
        return c
    }

    @Test func inactiveClientsAreNotOffered() {
        let clients = [client("Avery"), client("Blake", active: false), client("Casey")]
        #expect(Client.routable(from: clients, operatorID: "op").map(\.name) == ["Avery", "Casey"])
    }

    // Schedule > Create Route: a visit still scheduled for a client marked
    // inactive afterwards put them on the new route.
    @Test func aScheduledVisitForAnInactiveClientIsLeftOffAndCounted() {
        let avery = client("Avery"), blake = client("Blake", active: false), casey = client("Casey")
        let other = client("Drew", operatorID: "someone-else")
        let visits = [casey, blake, avery, other].map {
            ScheduledVisit(operatorID: "op", clientID: $0.id.uuidString, clientName: $0.name,
                           clientAddress: "", scheduledDate: Date())
        }
        let (chosen, skipped) = Client.routeClients(for: visits, from: [avery, blake, casey, other], operatorID: "op")
        #expect(chosen.map(\.name) == ["Casey", "Avery"])      // the visits' order
        #expect(skipped == 1)
    }

    @Test func onlyThisOperatorsClientsByName() {
        let clients = [client("Drew"), client("Emery", operatorID: "someone-else"), client("Addison")]
        #expect(Client.routable(from: clients, operatorID: "op").map(\.name) == ["Addison", "Drew"])
    }
}
