import Foundation

/// What a business with little or no data is offered, decided here rather
/// than in the views so each choice is tested.
enum FirstRunOffers {
    /// What Home's "Nothing on today" card offers.
    enum NothingToday: Equatable {
        /// No active clients: a route or a visit has nobody to be for, so the
        /// one useful step is adding a client.
        case addClient
        /// Clients exist: make a route or schedule a visit.
        case routeOrVisit
    }

    /// `clientCount` is the business's active clients (leads included): only
    /// they can be put on a route or booked.
    static func nothingToday(clientCount: Int) -> NothingToday {
        clientCount == 0 ? .addClient : .routeOrVisit
    }

    /// The same, from the business's clients: leads count as active, as
    /// everywhere; an inactive client (or lead) comes off routes and can't
    /// be put on one, so a business with only those starts again at adding one.
    static func nothingToday(clients: [Client]) -> NothingToday {
        nothingToday(clientCount: clients.filter(\.isActive).count)
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
        let searched = searchQuery(search)
        return searched.isEmpty ? .noMatchesForFilter : .noMatchesForSearch(searched)
    }

    /// What a typed search looks for: the text without the spaces around it.
    /// The keyboard adds a space after a word it suggests, and "Smith " used
    /// to match nobody. Only spaces is no search. The list and its
    /// no-matches message both use this, so they can't disagree.
    static func searchQuery(_ typed: String) -> String {
        typed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a client with these details is found by `typed`: in their
    /// name, address, phone or a tag, whatever the capitals. No search finds
    /// everyone.
    static func search(_ typed: String, finds name: String, address: String, phone: String, tags: [String]) -> Bool {
        let query = searchQuery(typed).lowercased()
        if query.isEmpty { return true }
        return name.lowercased().contains(query) || address.lowercased().contains(query)
            || phone.lowercased().contains(query) || tags.contains { $0.lowercased().contains(query) }
    }
}
