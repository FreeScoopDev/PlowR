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
@MainActor
@Suite(.serialized)
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
        #expect(await Subscription.readStoreKit() == .init(active: false, everSubscribed: false))

        let bought = try await session.buyProduct(identifier: Subscription.productID)
        // StoreKit's lists take a moment to show it (Subscription holds a
        // purchase made in the app meanwhile; AccessTests covers that).
        #expect(await eventually(.init(active: true, everSubscribed: true)))

        // Cancelled, then its period ends.
        try session.disableAutoRenewForTransaction(identifier: UInt(bought.id))
        try session.expireSubscription(productIdentifier: Subscription.productID)
        #expect(await eventually(.init(active: false, everSubscribed: true)))

        // A refunded purchase is as if never made.
        try session.refundTransaction(identifier: UInt(bought.id))
        #expect(await eventually(.init(active: false, everSubscribed: false)))
    }

    /// StoreKit's test store applies a change a moment after it's made.
    private func eventually(_ expected: Subscription.Entitlements) async -> Bool {
        for _ in 0..<50 {
            if await Subscription.readStoreKit() == expected { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }
}
