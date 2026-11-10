import Foundation

/// What a business with little or no data is offered, decided here rather
/// than in the views so each choice is tested.
enum FirstRunOffers {
    /// What Home's "Nothing on today" card offers.
    enum NothingToday: Equatable {
        /// No clients yet: a route or a visit has nobody to be for, so the
        /// one useful step is adding a client.
        case addClient
        /// Clients exist: make a route or schedule a visit.
        case routeOrVisit
    }

    static func nothingToday(clientCount: Int) -> NothingToday {
        clientCount == 0 ? .addClient : .routeOrVisit
    }

    /// The PRO mark beside an offer that goes through the Pro gate: shown
    /// to everyone not on Pro, never on Pro.
    static func showsProMark(_ access: Access) -> Bool {
        !access.canUseProFeatures
    }

    /// What the Clients list says when it has nothing to list.
    enum ClientListState: Equatable {
        /// The business has no clients at all.
        case noClients
        /// There are clients, but the search matches none; names what was searched.
        case noMatchesForSearch(String)
        /// There are clients, but the filter (or tag) matches none.
        case noMatchesForFilter
        /// Something to show.
        case showing
    }

    static func clientListState(clientCount: Int, shownCount: Int, search: String) -> ClientListState {
        if clientCount == 0 { return .noClients }
        if shownCount > 0 { return .showing }
        let searched = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return searched.isEmpty ? .noMatchesForFilter : .noMatchesForSearch(searched)
    }
}
