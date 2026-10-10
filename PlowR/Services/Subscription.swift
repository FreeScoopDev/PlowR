import Foundation
import StoreKit

/// The business's PlowR Pro subscription, as StoreKit reports it: the plan
/// `Access` works from.
///
/// Apple keeps the purchase on the device and with the Apple ID, so it
/// follows the user to their other devices and works offline in the truck.
/// Nothing is stored in iCloud. The last plan read is kept in preferences,
/// so the app starts with it before StoreKit answers; Delete Account & Data
/// removes it with the rest of the preferences.
@MainActor
@Observable
final class Subscription {
    /// The monthly subscription, in App Store Connect's "PlowR Pro" group.
    nonisolated static let productID = "Scoops.PlowR.pro.monthly"
    static let planKey = "subscriptionPlan"

    /// What StoreKit says, reduced to what the plan needs.
    nonisolated struct Entitlements: Equatable, Sendable {
        /// Subscribed now: StoreKit's current entitlements include the free
        /// trial and Apple's billing grace period.
        var active: Bool
        /// Any purchase of it, ever, the trial included.
        var everSubscribed: Bool
    }

    /// Never asks StoreKit under tests.
    static let shared = Subscription(read: {
        if PlowRApp.isRunningUnderTests { return Entitlements(active: false, everSubscribed: false) }
        return await readStoreKit()
    })

    private(set) var plan: Access.Plan

    @ObservationIgnored private let read: () async -> Entitlements
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var updates: Task<Void, Never>?
    /// Bumped by every read, so one that answers late can't overwrite a newer one.
    @ObservationIgnored private var generation = 0

    init(read: @escaping () async -> Entitlements, defaults: UserDefaults = .standard) {
        self.read = read
        self.defaults = defaults
        plan = defaults.string(forKey: Self.planKey).flatMap(Access.Plan.init) ?? .free
    }

    static func plan(for entitlements: Entitlements) -> Access.Plan {
        if entitlements.active { return .pro }
        return entitlements.everSubscribed ? .lapsed : .free
    }

    /// Reads the plan now: at launch, when the app comes back (a subscription
    /// that ran out sends no update), and after every purchase.
    func refresh() async {
        generation += 1
        let mine = generation
        let entitlements = await read()
        guard mine == generation else { return }
        plan = Self.plan(for: entitlements)
        defaults.set(plan.rawValue, forKey: Self.planKey)
    }

    /// Reads the plan and follows StoreKit's updates (renewals, refunds, a
    /// purchase on another device). Never under tests.
    func start() {
        guard updates == nil, !PlowRApp.isRunningUnderTests else { return }
        Task { await refresh() }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await transaction.finish()
                }
                await self?.refresh()
            }
        }
    }

    /// One transaction, as far as the plan cares.
    nonisolated struct Purchase: Equatable, Sendable {
        var verified: Bool
        var productID: String
        var revoked: Bool
        /// When the period it paid for (or the trial) ends.
        var expires: Date?
    }

    /// What the plan needs from StoreKit's transactions: only a verified,
    /// unrefunded purchase of PlowR Pro counts, now or ever. A refunded
    /// purchase is as if never made, so it leaves the free tier, never read
    /// only.
    ///
    /// Subscribed now: in StoreKit's current entitlements (which carry the
    /// grace period), or a purchase whose period hasn't ended yet. The
    /// entitlements reach a just-made purchase a moment after the history
    /// does (StoreKit's test store, 2026-10-10), and a read in that moment
    /// would say "not subscribed" to someone who had just paid.
    nonisolated static func entitlements(current: [Purchase], history: [Purchase],
                                         now: Date = .now) -> Entitlements {
        func counts(_ purchase: Purchase) -> Bool {
            purchase.verified && purchase.productID == productID && !purchase.revoked
        }
        let active = current.contains(where: counts)
            || history.contains { counts($0) && ($0.expires ?? .distantPast) > now }
        return Entitlements(active: active, everSubscribed: active || history.contains(where: counts))
    }

    /// StoreKit's answer: its current entitlements, and every purchase ever.
    nonisolated static func readStoreKit() async -> Entitlements {
        func purchase(_ result: VerificationResult<Transaction>) -> Purchase {
            let transaction = result.unsafePayloadValue
            let verified = if case .verified = result { true } else { false }
            return Purchase(verified: verified, productID: transaction.productID,
                            revoked: transaction.revocationDate != nil, expires: transaction.expirationDate)
        }
        var current: [Purchase] = []
        for await result in Transaction.currentEntitlements { current.append(purchase(result)) }
        var history: [Purchase] = []
        for await result in Transaction.all { history.append(purchase(result)) }
        return entitlements(current: current, history: history)
    }
}
