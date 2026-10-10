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
/// real App Store. Buying and a refund each reach the plan
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

    @Test func buyingAndARefund() async throws {
        #expect(await Subscription.readStoreKit() == .init(active: false, everSubscribed: false))

        let bought = try await session.buyProduct(identifier: Subscription.productID)
        // At once: before StoreKit's entitlements have caught up.
        #expect(await Subscription.readStoreKit() == .init(active: true, everSubscribed: true))

        // Not "expire now": the test store ends the subscription without
        // changing the purchase's end date, which the real App Store never
        // does (a period ends at its date, or early only by a refund).
        // Running out is the history-only case in AccessTests.

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
