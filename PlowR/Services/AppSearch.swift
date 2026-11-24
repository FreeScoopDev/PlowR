import Foundation

/// Home's Search: one typed search across clients, documents, routes and
/// Service Log jobs, each kind found by the clients' rule (`ClientSearch`:
/// every word somewhere, capitals and accents ignored), so a word finds
/// the same things here as in the Clients and Documents lists.
///
/// Clients match as on the Clients list, documents as on the Documents
/// list (`DocumentList.matches`), a route by its name, and a job by its
/// client, its notes and its address. Matching is done in memory: the
/// rule (every word, any field, digits in a phone) is `ClientSearch`'s,
/// which a store predicate can't express, and one business's records are
/// few.
enum AppSearch {
    /// How many of each kind the search page lists before "Show All".
    static let shownPerKind = 5

    /// What a search found, one list per kind, each in its own order.
    struct Results {
        /// By name, A to Z; inactive clients too.
        var clients: [Client] = []
        /// Newest first; paid and void ones too.
        var documents: [Proposal] = []
        /// By name, A to Z.
        var routes: [PlowRoute] = []
        /// Newest job first.
        var records: [ServiceRecord] = []

        var isEmpty: Bool {
            clients.isEmpty && documents.isEmpty && routes.isEmpty && records.isEmpty
        }
    }

    /// Everything of `operatorID`'s that `typed` finds. A search of only
    /// spaces finds nothing (unlike a list's own search, which then shows
    /// the whole list).
    static func results(query typed: String, clients: [Client], documents: [Proposal],
                        routes: [PlowRoute], records: [ServiceRecord], operatorID: String) -> Results {
        guard !ClientSearch.words(typed).isEmpty else { return Results() }
        let foundClients = clients.filter { $0.operatorID == operatorID && ClientSearch.matches($0, query: typed) }
        let foundDocuments = documents.filter { $0.operatorID == operatorID && DocumentList.matches($0, query: typed) }
        let foundRoutes = routes.filter { $0.operatorID == operatorID && matches($0, query: typed) }
        let foundRecords = records.filter { $0.operatorID == operatorID && matches($0, query: typed) }
        return Results(
            clients: foundClients.sorted { byName($0.name, $0.id, $1.name, $1.id) },
            documents: foundDocuments.sorted { newest($0.createdAt, $0.id, $1.createdAt, $1.id) },
            routes: foundRoutes.sorted { byName($0.name, $0.id, $1.name, $1.id) },
            records: foundRecords.sorted { newest($0.performedAt, $0.id, $1.performedAt, $1.id) }
        )
    }

    /// Whether `typed` finds a route: by its name.
    static func matches(_ route: PlowRoute, query typed: String) -> Bool {
        ClientSearch.matches(typed, in: [route.name])
    }

    /// Whether `typed` finds a job: by its client, its notes and its address.
    static func matches(_ record: ServiceRecord, query typed: String) -> Bool {
        ClientSearch.matches(typed, in: [record.clientName, record.notes, record.propertyAddress])
    }

    /// The first few of a kind's results, as the search page lists them.
    static func shown<T>(_ found: [T]) -> [T] {
        Array(found.prefix(shownPerKind))
    }

    /// Whether a kind has more than the page lists ("Show All (N)").
    static func hasMore<T>(_ found: [T]) -> Bool {
        found.count > shownPerKind
    }

    // MARK: - Order

    /// A to Z, capitals and accents aside; ties by ID so the order never shuffles.
    private static func byName(_ a: String, _ aID: UUID, _ b: String, _ bID: UUID) -> Bool {
        let order = a.compare(b, options: [.caseInsensitive, .diacriticInsensitive, .numeric], locale: .current)
        if order != .orderedSame { return order == .orderedAscending }
        return aID.uuidString < bID.uuidString
    }

    /// Latest first; ties by ID.
    private static func newest(_ a: Date, _ aID: UUID, _ b: Date, _ bID: UUID) -> Bool {
        if a != b { return a > b }
        return aID.uuidString < bID.uuidString
    }
}
