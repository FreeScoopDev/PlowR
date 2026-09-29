//
//  RoutableClientsTests.swift
//  PlowRTests
//

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

    @Test func onlyThisOperatorsClientsByName() {
        let clients = [client("Drew"), client("Emery", operatorID: "someone-else"), client("Addison")]
        #expect(Client.routable(from: clients, operatorID: "op").map(\.name) == ["Addison", "Drew"])
    }
}
