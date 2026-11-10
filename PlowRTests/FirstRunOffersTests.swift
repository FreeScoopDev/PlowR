import Foundation
import Testing
@testable import PlowR

/// What a business with no data yet is offered: Home's empty day, the PRO
/// mark on import, and what the Clients list says when it has nothing to show.
struct FirstRunOffersTests {
    // MARK: Home, nothing on today

    @Test func withNoClientsHomeOffersAddClient() {
        #expect(FirstRunOffers.nothingToday(clientCount: 0) == .addClient)
    }

    @Test func withClientsHomeIsUnchanged() {
        #expect(FirstRunOffers.nothingToday(clientCount: 1) == .routeOrVisit)
        #expect(FirstRunOffers.nothingToday(clientCount: 40) == .routeOrVisit)
    }

    // MARK: The PRO mark

    @Test func theProMarkShowsOnEveryPlanButPro() {
        #expect(FirstRunOffers.showsProMark(Access(plan: .free, clientCount: 0)))
        #expect(FirstRunOffers.showsProMark(Access(plan: .lapsed, clientCount: 3)))
        #expect(FirstRunOffers.showsProMark(Access(plan: .lapsed, clientCount: 30)))
        #expect(!FirstRunOffers.showsProMark(Access(plan: .pro, clientCount: 0)))
    }

    // MARK: The Clients list

    @Test func noClientsAtAllKeepsTheEmptyState() {
        #expect(FirstRunOffers.clientListState(clientCount: 0, shownCount: 0, search: "") == .noClients)
        #expect(FirstRunOffers.clientListState(clientCount: 0, shownCount: 0, search: "smith") == .noClients)
    }

    @Test func aSearchWithNoMatchesNamesWhatWasSearched() {
        #expect(FirstRunOffers.clientListState(clientCount: 5, shownCount: 0, search: "  smith ") == .noMatchesForSearch("smith"))
    }

    @Test func aFilterWithNoMatchesSaysSo() {
        #expect(FirstRunOffers.clientListState(clientCount: 5, shownCount: 0, search: "") == .noMatchesForFilter)
        #expect(FirstRunOffers.clientListState(clientCount: 5, shownCount: 0, search: "   ") == .noMatchesForFilter)
    }

    @Test func clientsShownIsNotAnEmptyState() {
        #expect(FirstRunOffers.clientListState(clientCount: 5, shownCount: 2, search: "sm") == .showing)
    }
}
