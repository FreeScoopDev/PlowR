import Foundation

/// What a business may do on its plan (PlowR Pro). The only place the rules
/// live: every screen, Siri action, link and import that adds, reports or runs
/// a route asks this, so they can't drift apart.
///
/// - Pro (the free trial, paid, or Apple's billing grace period): everything.
/// - Free (never subscribed, or cancelled with 10 clients or fewer): up to
///   10 clients and one route; documents carry "Made with PlowR"; none of the
///   Pro tools.
/// - Read only (cancelled with more than 10 clients): everything stays there
///   to see and export, and payments can still be recorded on invoices
///   already made. Nothing new, no reports, no routes. Subscribing again
///   picks up exactly where they left off.
///
/// Nothing is ever deleted or hidden because of the plan.
struct Access: Equatable {
    enum Plan: String {
        /// Subscribed now: the trial, paid, or in Apple's billing grace period.
        case pro
        /// Never subscribed.
        case free
        /// Subscribed before, not now.
        case lapsed
    }

    enum Tier: Equatable {
        case pro, free, readOnly
    }

    static let freeClientLimit = 10

    let plan: Plan
    /// Clients counted against the free limit (`countedClients`).
    let clientCount: Int

    init(plan: Plan, clientCount: Int) {
        self.plan = plan
        self.clientCount = clientCount
    }

    var tier: Tier {
        switch plan {
        case .pro: .pro
        case .free: .free
        case .lapsed: clientCount <= Self.freeClientLimit ? .free : .readOnly
        }
    }

    /// Cancelled, and small enough for the free tier: PlowR tells them so.
    var isFreeAfterCancelling: Bool { plan == .lapsed && tier == .free }

    var canAddClient: Bool {
        switch tier {
        case .pro: true
        case .free: clientCount < Self.freeClientLimit
        case .readOnly: false
        }
    }

    /// Changing what's there: clients, visits, work, documents, routes.
    var canEdit: Bool { tier != .readOnly }

    /// A new route, given how many this business has.
    func canCreateRoute(existingRoutes: Int) -> Bool {
        switch tier {
        case .pro: true
        case .free: existingRoutes == 0
        case .readOnly: false
        }
    }

    /// Starting a route. On the free tier only one runs: the oldest, so a
    /// business that cancelled with several keeps the first it made, and
    /// none is deleted to get there.
    func canStartRoute(_ route: PlowRoute, among routes: [PlowRoute]) -> Bool {
        switch tier {
        case .pro: true
        case .free: Self.freeRoute(in: routes)?.id == route.id
        case .readOnly: false
        }
    }

    /// Invoices, proposals and contracts as PDFs, to share or print.
    var canMakeDocuments: Bool { tier != .readOnly }

    /// The Service Report, storm tools, Import Clients and the Request Link.
    var canUseProFeatures: Bool { tier == .pro }

    /// A small "Made with PlowR" line on documents.
    var showsMadeWithPlowR: Bool { tier == .free }

    /// Money owed for work already done is never locked away.
    var canRecordPayment: Bool { true }

    /// Their data is theirs, on every plan.
    var canExport: Bool { true }

    /// The route the free tier runs: the oldest, ties broken by ID so every
    /// device picks the same one.
    static func freeRoute(in routes: [PlowRoute]) -> PlowRoute? {
        routes.min { a, b in
            a.createdAt != b.createdAt ? a.createdAt < b.createdAt : a.id.uuidString < b.id.uuidString
        }
    }

    /// The clients counted against the free limit: this business's current
    /// ones. Inactive clients and lost leads are records, not current work.
    static func countedClients(_ clients: [Client], operatorID: String) -> Int {
        clients.count { $0.operatorID == operatorID && $0.isActive && $0.lostAt == nil }
    }
}
