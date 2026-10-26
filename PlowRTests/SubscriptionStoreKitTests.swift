//
//  SubscriptionStoreKitTests.swift
//  PlowRTests
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import PlowR

/// PlowR Pro against StoreKit itself: Apple's local test store, loaded from
/// `PlowR.storekit` (the file the PlowR scheme's Run action uses), never the
/// real App Store. Buying, running out and a refund each reach the plan
/// through `Subscription.readStoreKit`, the part `AccessTests` can't reach.
///
/// Local runs only (`scripts/test.sh` turns them on): on Xcode Cloud the
/// test store finds no products (PR #133's CI run, 2026-10-10).
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PLOWR_STOREKIT_TESTS"] != nil,
                             "Apple's local StoreKit test store: local runs only"))
struct SubscriptionStoreKitTests {
    private final class BundleToken {}

    let session: SKTestSession

    init() throws {
        let url = try #require(Bundle(for: BundleToken.self).url(forResource: "PlowR", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
    }

    @Test func theProductIsMonthlyWithAOneMonthFreeTrial() async throws {
        let product = try #require(try await Product.products(for: [Subscription.productID]).first)
        #expect(product.type == .autoRenewable)
        #expect(product.price == Decimal(string: "8.99"))
        let subscription = try #require(product.subscription)
        #expect(subscription.subscriptionPeriod.value == 1 && subscription.subscriptionPeriod.unit == .month)
        let trial = try #require(subscription.introductoryOffer)
        #expect(trial.paymentMode == .freeTrial)
        #expect(trial.period.value == 1 && trial.period.unit == .month)
    }

    @Test func buyingRunningOutAndARefund() async throws {
        // Cleared in init, but the app's copy of the transactions can lag that too.
        let none = Subscription.Entitlements(active: false, everSubscribed: false)
        let atStart = await read(until: none)
        #expect(atStart == none)

        let bought = try await session.buyProduct(identifier: Subscription.productID)
        // StoreKit's lists take a moment to show it (Subscription holds a
        // purchase made in the app meanwhile; AccessTests covers that).
        let subscribed = Subscription.Entitlements(active: true, everSubscribed: true)
        let afterPurchase = await read(until: subscribed)
        #expect(afterPurchase == subscribed)

        // Cancelled, then its period ends.
        try session.disableAutoRenewForTransaction(identifier: UInt(bought.id))
        try session.expireSubscription(productIdentifier: Subscription.productID)
        let lapsed = Subscription.Entitlements(active: false, everSubscribed: true)
        let afterExpiry = await read(until: lapsed)
        #expect(afterExpiry == lapsed)

        // A refunded purchase is as if never made.
        try session.refundTransaction(identifier: UInt(bought.id))
        let afterRefund = await read(until: none)
        #expect(afterRefund == none)
    }

    /// Reads the plan until it is `expected` or 30 seconds have passed, and
    /// returns the last read, so a failure shows what StoreKit said (bind
    /// it first: `#expect` doesn't show the value of an `await`).
    ///
    /// The test store applies a change at once, but the app's copy of the
    /// transactions catches up when StoreKit gets to it, still showing the
    /// old 31-day expiry until then: an expiry showed within 0.03 to 3.2
    /// seconds in 21 local runs (2026-10-19), and two full runs hadn't seen
    /// it after 5.7. Nothing tells the app when it has caught up (a
    /// subscription running out sends no update), so this waits by the
    /// clock, not by a count of reads: 50 reads came to about 5 seconds when
    /// each answered fast.
    private func read(until expected: Subscription.Entitlements) async -> Subscription.Entitlements {
        let deadline = ContinuousClock.now + .seconds(30)
        var last = await Subscription.readStoreKit()
        while last != expected, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            last = await Subscription.readStoreKit()
        }
        return last
    }
}
