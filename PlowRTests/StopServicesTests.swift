//
//  StopServicesTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// A route stop's expected services: the client's usual ones until the stop
/// gets its own on its route; changing them applies to this route only, or to
/// the client's usual services, which every route's stop then follows.
@MainActor
struct StopServicesTests {
    typealias Harness = ActiveRouteStoreTests.Harness

    @Test func aStopFollowsItsClientUntilItHasItsOwn() throws {
        let h = try Harness(stopCount: 1)
        let stop = try #require(h.route.sortedStops.first)
        h.client.expectedServiceIDs = ["clear"]
        #expect(StopServices.expected(for: stop, client: h.client) == ["clear"])
        h.client.expectedServiceIDs = ["clear", "salt"]
        #expect(StopServices.expected(for: stop, client: h.client) == ["clear", "salt"])
    }

    @Test func onlyThisRouteLeavesTheClientAndOtherRoutesAlone() throws {
        let h = try Harness(stopCount: 1)
        let stop = try #require(h.route.sortedStops.first)
        let otherRoute = PlowRoute(name: "Ice", operatorID: "op")
        h.context.insert(otherRoute)
        let otherStop = RouteStop(order: 0, client: h.client)
        otherStop.route = otherRoute
        h.context.insert(otherStop)
        h.client.expectedServiceIDs = ["clear"]

        StopServices.setForThisRoute(["salt"], on: stop)
        #expect(StopServices.expected(for: stop, client: h.client) == ["salt"])
        #expect(StopServices.expected(for: otherStop, client: h.client) == ["clear"])
        #expect(h.client.expectedServiceIDs == ["clear"])
    }

    // All routes: the client's usual services change, and every route's stop
    // for them follows, even one that had its own list.
    @Test func allRoutesChangesTheClientAndEveryStopFollows() throws {
        let h = try Harness(stopCount: 1)
        let stop = try #require(h.route.sortedStops.first)
        let otherRoute = PlowRoute(name: "Ice", operatorID: "op")
        h.context.insert(otherRoute)
        let otherStop = RouteStop(order: 0, client: h.client)
        otherStop.route = otherRoute
        h.context.insert(otherStop)
        try h.context.save()
        StopServices.setForThisRoute(["salt"], on: otherStop)

        StopServices.setForAllRoutes(["clear", "shovel"], for: h.client, in: h.context)
        #expect(h.client.expectedServiceIDs == ["clear", "shovel"])
        #expect(StopServices.expected(for: stop, client: h.client) == ["clear", "shovel"])
        #expect(StopServices.expected(for: otherStop, client: h.client) == ["clear", "shovel"])
        #expect(!otherStop.hasOwnServices)
    }

    // A custom stop (fuel, the depot) has no client: a change is for this
    // route, even if "all routes" was asked for.
    @Test func aCustomStopsChangeIsForThisRoute() throws {
        let h = try Harness(stopCount: 0)
        let custom = RouteStop(order: 0, customName: "Depot")
        h.context.insert(custom)
        #expect(StopServices.expected(for: custom, client: nil).isEmpty)
        StopServices.apply(["load"], to: custom, client: nil, allRoutes: true, in: h.context)
        #expect(custom.hasOwnServices)
        #expect(StopServices.expected(for: custom, client: nil) == ["load"])
    }

    @Test func applyGoesWhereTheUserChose() throws {
        let h = try Harness(stopCount: 1)
        let stop = try #require(h.route.sortedStops.first)
        h.client.expectedServiceIDs = ["clear"]
        StopServices.apply(["salt"], to: stop, client: h.client, allRoutes: false, in: h.context)
        #expect(h.client.expectedServiceIDs == ["clear"])
        #expect(stop.hasOwnServices)
        StopServices.apply(["shovel"], to: stop, client: h.client, allRoutes: true, in: h.context)
        #expect(h.client.expectedServiceIDs == ["shovel"])
        #expect(!stop.hasOwnServices)
    }

    @Test func directionsGoToThePinOrElseTheAddress() throws {
        let pinned = RouteStop(order: 0, customName: "A", customAddress: "1 Main St")
        pinned.latitude = 42.5
        pinned.longitude = -71.25
        #expect(pinned.appleMapsDirectionsURL?.absoluteString == "maps://?daddr=42.5,-71.25&dirflg=d")
        let unpinned = RouteStop(order: 0, customName: "B", customAddress: "1 Main St")
        #expect(unpinned.appleMapsDirectionsURL?.absoluteString == "maps://?daddr=1%20Main%20St")
        #expect(RouteStop(order: 0, customName: "C").appleMapsDirectionsURL == nil)
    }

    // Saving the stop's page with its services unchanged (only a note, say)
    // mustn't give the stop a list of its own.
    @Test func unchangedServicesAreLeftFollowingTheClient() throws {
        let h = try Harness(stopCount: 1)
        let stop = try #require(h.route.sortedStops.first)
        h.client.expectedServiceIDs = ["clear", "salt"]
        StopServices.apply(["salt", "clear"], to: stop, client: h.client, allRoutes: false,
                           openedWith: ["clear", "salt"], in: h.context)
        #expect(!stop.hasOwnServices)
    }

    @Test func aStopWithoutItsOwnTargetUsesTheClientsGoal() throws {
        let h = try Harness(stopCount: 1)
        let stop = try #require(h.route.sortedStops.first)
        h.client.goalMinutes = 20
        #expect(RouteFacts.targetMinutes(of: stop, client: h.client) == 20)
        stop.targetMinutes = 35
        #expect(RouteFacts.targetMinutes(of: stop, client: h.client) == 35)
        stop.targetMinutes = 0
        #expect(RouteFacts.targetMinutes(of: stop, client: nil) == 0)
    }
}
