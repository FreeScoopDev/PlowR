//
//  AccessTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// PlowR Pro's rules, in the one place they live, and the plan read from
/// StoreKit. Joe's decisions (2026-10-09): free is 10 clients and one route;
/// cancelling with 10 or fewer is the free tier; with more, read only; money
/// owed and exporting are never locked.
@MainActor
struct AccessTests {
    // MARK: Tiers

    @Test func proIsProWhateverTheCount() {
        #expect(Access(plan: .pro, clientCount: 0).tier == .pro)
        #expect(Access(plan: .pro, clientCount: 500).tier == .pro)
    }

    @Test func neverSubscribedIsFreeWhateverTheCount() {
        // Over the limit without ever paying (an import before step 2's
        // gates): free, so they're never worse off than read only.
        #expect(Access(plan: .free, clientCount: 0).tier == .free)
        #expect(Access(plan: .free, clientCount: 25).tier == .free)
    }

    @Test func cancelledAtTheLimitIsFreeAndToldSo() {
        let access = Access(plan: .lapsed, clientCount: 10)
        #expect(access.tier == .free)
        #expect(access.isFreeAfterCancelling)
    }

    @Test func cancelledOverTheLimitIsReadOnly() {
        let access = Access(plan: .lapsed, clientCount: 11)
        #expect(access.tier == .readOnly)
        #expect(!access.isFreeAfterCancelling)
    }

    @Test func onlyCancellingIsFreeAfterCancelling() {
        #expect(!Access(plan: .free, clientCount: 3).isFreeAfterCancelling)
        #expect(!Access(plan: .pro, clientCount: 3).isFreeAfterCancelling)
    }

    // MARK: Clients

    @Test func freeAddsUpToTenClients() {
        #expect(Access(plan: .free, clientCount: 9).canAddClient)
        #expect(!Access(plan: .free, clientCount: 10).canAddClient)
        #expect(Access(plan: .lapsed, clientCount: 9).canAddClient)
        #expect(!Access(plan: .lapsed, clientCount: 10).canAddClient)
    }

    @Test func proAddsAnyNumber() {
        #expect(Access(plan: .pro, clientCount: 10).canAddClient)
        #expect(Access(plan: .pro, clientCount: 1_000).canAddClient)
    }

    @Test func readOnlyAddsAndEditsNothing() {
        let access = Access(plan: .lapsed, clientCount: 40)
        #expect(!access.canAddClient)
        #expect(!access.canEdit)
        #expect(!access.canMakeDocuments)
        #expect(!access.canUseProFeatures)
        #expect(!access.canCreateRoute(routes: [], operatorID: "op"))
    }

    // MARK: Never locked

    @Test(arguments: [(Access.Plan.pro, 0), (.free, 0), (.free, 50), (.lapsed, 5), (.lapsed, 50)])
    func paymentsAndExportAreNeverLocked(plan: Access.Plan, count: Int) {
        let access = Access(plan: plan, clientCount: count)
        #expect(access.canRecordPayment)
        #expect(access.canExport)
    }

    // MARK: Features

    @Test func proToolsAreProOnly() {
        #expect(Access(plan: .pro, clientCount: 0).canUseProFeatures)
        #expect(!Access(plan: .free, clientCount: 0).canUseProFeatures)
        #expect(!Access(plan: .lapsed, clientCount: 2).canUseProFeatures)
    }

    @Test func documentsCarryTheLineOnlyOnFree() {
        let pro = Access(plan: .pro, clientCount: 0)
        let free = Access(plan: .free, clientCount: 0)
        let cancelledSmall = Access(plan: .lapsed, clientCount: 4)
        #expect(pro.canMakeDocuments && !pro.showsMadeWithPlowR)
        #expect(free.canMakeDocuments && free.showsMadeWithPlowR)
        #expect(cancelledSmall.canMakeDocuments && cancelledSmall.showsMadeWithPlowR)
        // Read only, the invoices still shared carry the line too.
        #expect(Access(plan: .lapsed, clientCount: 40).showsMadeWithPlowR)
    }

    // MARK: Routes

    @Test func freeMakesOneRoute() {
        let mine = PlowRoute(name: "Monday", operatorID: "op")
        let theirs = PlowRoute(name: "Other", operatorID: "other")
        for plan in [Access.Plan.free, .lapsed] {
            let access = Access(plan: plan, clientCount: 3)
            #expect(access.canCreateRoute(routes: [], operatorID: "op"))
            // Another sign-in's route on this device doesn't use it up.
            #expect(access.canCreateRoute(routes: [theirs], operatorID: "op"))
            #expect(!access.canCreateRoute(routes: [mine, theirs], operatorID: "op"))
        }
        #expect(Access(plan: .pro, clientCount: 3).canCreateRoute(routes: [mine, mine], operatorID: "op"))
    }

    @Test(arguments: [(Access.Plan.pro, 0), (.pro, 300), (.free, 0), (.free, 30), (.lapsed, 0), (.lapsed, 10)])
    func everyoneButReadOnlyEdits(plan: Access.Plan, count: Int) {
        #expect(Access(plan: plan, clientCount: count).canEdit)
    }

    @Test func freeStartsOnlyTheOldestRoute() {
        let old = PlowRoute(name: "Monday", operatorID: "op")
        old.createdAt = Date(timeIntervalSinceReferenceDate: 100)
        let new = PlowRoute(name: "Tuesday", operatorID: "op")
        new.createdAt = Date(timeIntervalSinceReferenceDate: 200)
        // Another sign-in's route on this device, older still.
        let theirs = PlowRoute(name: "Other", operatorID: "other")
        theirs.createdAt = Date(timeIntervalSinceReferenceDate: 1)
        let routes = [new, theirs, old]

        for plan in [Access.Plan.free, .lapsed] {
            let free = Access(plan: plan, clientCount: 8)
            #expect(free.canStartRoute(old, among: routes, operatorID: "op"))
            #expect(!free.canStartRoute(new, among: routes, operatorID: "op"))
        }

        let pro = Access(plan: .pro, clientCount: 8)
        #expect(pro.canStartRoute(new, among: routes, operatorID: "op"))

        let readOnly = Access(plan: .lapsed, clientCount: 30)
        #expect(!readOnly.canStartRoute(old, among: routes, operatorID: "op"))
    }

    @Test func routesMadeTogetherPickTheSameOneEverywhere() {
        let when = Date(timeIntervalSinceReferenceDate: 100)
        let a = PlowRoute(name: "A", operatorID: "op")
        let b = PlowRoute(name: "B", operatorID: "op")
        a.createdAt = when
        b.createdAt = when
        let expected = a.id.uuidString < b.id.uuidString ? a.id : b.id
        #expect(Access.freeRoute(in: [a, b], operatorID: "op")?.id == expected)
        #expect(Access.freeRoute(in: [b, a], operatorID: "op")?.id == expected)
        #expect(Access.freeRoute(in: [], operatorID: "op") == nil)
        #expect(Access.freeRoute(in: [a, b], operatorID: "other") == nil)
    }

    // MARK: Counting clients

    @Test func countsThisBusinessesActiveClientsOnly() throws {
        let container = try ModelContainer(for: Schema(PlowRApp.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                              cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false   // see ActiveRouteStoreTests.Harness
        let context = container.mainContext
        let current = Client(name: "Current", phone: "", address: "", operatorID: "op")
        let inactive = Client(name: "Inactive", phone: "", address: "", operatorID: "op")
        inactive.isActive = false
        let lost = Client(name: "Lost", phone: "", address: "", operatorID: "op")
        lost.lostAt = .now
        let lead = Client(name: "Lead", phone: "", address: "", operatorID: "op")
        let someoneElse = Client(name: "Other", phone: "", address: "", operatorID: "other")
        for client in [current, inactive, lost, lead, someoneElse] { context.insert(client) }

        let clients = try context.fetch(FetchDescriptor<Client>())
        // Current, lost and lead: every active one of theirs.
        #expect(Access.countedClients(clients, operatorID: "op") == 3)
    }

    // MARK: The plan from StoreKit

    @Test func planFromWhatStoreKitSays() {
        #expect(Subscription.plan(for: .init(active: true, everSubscribed: true)) == .pro)
        #expect(Subscription.plan(for: .init(active: true, everSubscribed: false)) == .pro)
        #expect(Subscription.plan(for: .init(active: false, everSubscribed: true)) == .lapsed)
        #expect(Subscription.plan(for: .init(active: false, everSubscribed: false)) == .free)
    }

    typealias Purchase = Subscription.Purchase
    let pro = Subscription.productID

    @Test func aVerifiedPurchaseIsPro() {
        let bought = Purchase(verified: true, productID: pro, revoked: false)
        #expect(Subscription.entitlements(current: [bought], history: [bought])
                == .init(active: true, everSubscribed: true))
    }

    @Test func anUnverifiedPurchaseCountsForNothing() {
        let forged = Purchase(verified: false, productID: pro, revoked: false)
        #expect(Subscription.entitlements(current: [forged], history: [forged])
                == .init(active: false, everSubscribed: false))
    }

    @Test func aRefundedPurchaseCountsForNothing() {
        // As if never bought: the free tier, never read only.
        let refunded = Purchase(verified: true, productID: pro, revoked: true)
        #expect(Subscription.entitlements(current: [refunded], history: [refunded])
                == .init(active: false, everSubscribed: false))
    }

    @Test func anotherProductIsNotPro() {
        let other = Purchase(verified: true, productID: "Scoops.PlowR.other", revoked: false)
        #expect(Subscription.entitlements(current: [other], history: [other])
                == .init(active: false, everSubscribed: false))
    }

    @Test func aPurchaseOnlyInTheHistoryIsCancelled() {
        let past = Purchase(verified: true, productID: pro, revoked: false)
        #expect(Subscription.plan(for: Subscription.entitlements(current: [], history: [past])) == .lapsed)
    }

    // MARK: A purchase just made, before StoreKit's lists show it

    private func bought(expiresIn seconds: TimeInterval, from now: Date, verified: Bool = true,
                        product: String? = nil, revoked: Bool = false) -> Purchase {
        Purchase(verified: verified, productID: product ?? pro, revoked: revoked,
                 expires: now.addingTimeInterval(seconds))
    }

    @Test func aPurchaseIsProWhileStoreKitCatchesUp() async throws {
        let store = try Store()
        let subscription = store.make()
        await subscription.purchased(bought(expiresIn: 30 * 86_400, from: store.now))
        #expect(subscription.plan == .pro)
        // StoreKit's lists still say nothing a minute later.
        store.now += 60
        await subscription.refresh()
        #expect(subscription.plan == .pro)
        #expect(store.defaults.string(forKey: Subscription.planKey) == "pro")
    }

    @Test func theHoldEndsAfterFiveMinutes() async throws {
        let store = try Store()
        let subscription = store.make()
        await subscription.purchased(bought(expiresIn: 30 * 86_400, from: store.now))
        store.now += Subscription.purchaseHold + 1
        await subscription.refresh()
        #expect(subscription.plan == .free)
    }

    @Test func theHoldEndsWithThePeriodIfThatsSooner() async throws {
        let store = try Store()
        let subscription = store.make()
        await subscription.purchased(bought(expiresIn: 60, from: store.now))
        #expect(subscription.plan == .pro)
        store.now += 61
        await subscription.refresh()
        #expect(subscription.plan == .free)
    }

    @Test func theHoldEndsWhenStoreKitShowsThePurchase() async throws {
        let store = try Store()
        let subscription = store.make()
        await subscription.purchased(bought(expiresIn: 30 * 86_400, from: store.now))
        store.answer = .init(active: true, everSubscribed: true)
        await subscription.refresh()
        // Then refunded within the five minutes: StoreKit's word stands.
        store.answer = .init(active: false, everSubscribed: false)
        await subscription.refresh()
        #expect(subscription.plan == .free)
    }

    @Test func onlyARealPurchaseIsHeld() async throws {
        let store = try Store()
        let now = store.now
        for purchase in [bought(expiresIn: 86_400, from: now, verified: false),
                         bought(expiresIn: 86_400, from: now, revoked: true),
                         bought(expiresIn: 86_400, from: now, product: "Scoops.PlowR.other"),
                         bought(expiresIn: -1, from: now),
                         Purchase(verified: true, productID: pro, revoked: false)] {
            let subscription = store.make()
            await subscription.purchased(purchase)
            #expect(subscription.plan == .free)
        }
    }

    // MARK: The plan in words (Settings)

    @Test func settingsSaysThePlan() {
        let pro = Access(plan: .pro, clientCount: 40)
        #expect(ProSettingsSection.title(for: pro) == "PlowR Pro is on")

        let free = Access(plan: .free, clientCount: 3)
        #expect(ProSettingsSection.title(for: free) == "Free")
        #expect(ProSettingsSection.message(for: free).hasPrefix("3 of 10 clients"))

        let overFree = Access(plan: .free, clientCount: 14)
        #expect(ProSettingsSection.message(for: overFree).hasPrefix("14 clients: the free tier adds clients up to 10"))

        let cancelledSmall = Access(plan: .lapsed, clientCount: 10)
        #expect(ProSettingsSection.title(for: cancelledSmall) == "Free since your subscription ended")
        #expect(ProSettingsSection.message(for: cancelledSmall).contains("10 of 10 clients"))

        let cancelledBig = Access(plan: .lapsed, clientCount: 11)
        #expect(ProSettingsSection.title(for: cancelledBig) == "Your subscription ended")
        #expect(ProSettingsSection.message(for: cancelledBig).contains("see and export"))
        #expect(ProSettingsSection.message(for: cancelledBig).contains("record payments"))
    }

    @MainActor
    final class Store {
        let suite = "AccessTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        var answer = Subscription.Entitlements(active: false, everSubscribed: false)
        var now = Date(timeIntervalSinceReferenceDate: 813_000_000)
        var holds = false
        var held: [CheckedContinuation<Subscription.Entitlements, Never>] = []

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
        }

        func make() -> Subscription {
            Subscription(read: { [unowned self] in
                if holds { return await withCheckedContinuation { held.append($0) } }
                return answer
            }, defaults: defaults, now: { [unowned self] in now })
        }

        deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    @Test func startsFreeWithNothingKept() throws {
        let store = try Store()
        #expect(store.make().plan == .free)
    }

    @Test func keepsThePlanForTheNextLaunch() async throws {
        let store = try Store()
        store.answer = .init(active: true, everSubscribed: true)
        let first = store.make()
        await first.refresh()
        #expect(first.plan == .pro)

        // Next launch, before StoreKit answers.
        store.holds = true
        #expect(store.make().plan == .pro)
    }

    @Test func runningOutIsReadOnTheNextRefresh() async throws {
        let store = try Store()
        store.answer = .init(active: true, everSubscribed: true)
        let subscription = store.make()
        await subscription.refresh()
        store.answer = .init(active: false, everSubscribed: true)
        await subscription.refresh()
        #expect(subscription.plan == .lapsed)
        #expect(store.defaults.string(forKey: Subscription.planKey) == "lapsed")
    }

    @Test func aLateAnswerDoesNotOverwriteANewerOne() async throws {
        let store = try Store()
        store.holds = true
        let subscription = store.make()
        let older = Task { await subscription.refresh() }
        while store.held.count < 1 { await Task.yield() }
        let newer = Task { await subscription.refresh() }
        while store.held.count < 2 { await Task.yield() }
        // The newer read answers first: subscribed. Then the older: not.
        store.held[1].resume(returning: .init(active: true, everSubscribed: true))
        await newer.value
        store.held[0].resume(returning: .init(active: false, everSubscribed: false))
        await older.value
        #expect(subscription.plan == .pro)
    }
}
