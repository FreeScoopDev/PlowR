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

    /// StoreKit's answer. Only verified transactions count, and a refunded
    /// one isn't a subscription.
    nonisolated static func readStoreKit() async -> Entitlements {
        var active = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == productID,
                  transaction.revocationDate == nil else { continue }
            active = true
        }
        var ever = active
        if !ever {
            for await result in Transaction.all {
                if case .verified(let transaction) = result, transaction.productID == productID {
                    ever = true
                    break
                }
            }
        }
        return Entitlements(active: active, everSubscribed: ever)
    }
}
