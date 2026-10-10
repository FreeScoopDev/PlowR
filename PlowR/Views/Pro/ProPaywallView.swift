import StoreKit
import SwiftUI

/// PlowR Pro's subscribe screen. Apple's own subscription view shows the
/// price, the free trial to those who can have it, the renewal terms and the
/// buttons, so they're always right and in the form App Review expects; PlowR
/// adds what Pro is for above them.
struct ProPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    private let subscription = Subscription.shared

    static let termsURL = URL(string: "https://getplowr.app/terms-of-service.html")
    static let privacyURL = URL(string: "https://getplowr.app/privacy-policy.html")

    var body: some View {
        SubscriptionStoreView(productIDs: [Subscription.productID]) {
            ProPitch()
        }
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .modifier(PolicyLinks())
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success(let verification)) = result,
               case .verified(let transaction) = verification {
                await transaction.finish()
            }
            await subscription.refresh()
        }
        .onChange(of: subscription.plan) { _, plan in
            if plan == .pro { dismiss() }
        }
        .tint(PlowRColor.accent)
    }
}

/// The Terms of Use and Privacy Policy, linked under the purchase button.
private struct PolicyLinks: ViewModifier {
    func body(content: Content) -> some View {
        if let terms = ProPaywallView.termsURL, let privacy = ProPaywallView.privacyURL {
            content
                .subscriptionStorePolicyDestination(url: terms, for: .termsOfService)
                .subscriptionStorePolicyDestination(url: privacy, for: .privacyPolicy)
        } else {
            content
        }
    }
}

/// What Pro adds, above Apple's purchase controls.
struct ProPitch: View {
    static let features: [(icon: String, text: String)] = [
        ("person.3.fill", "Unlimited clients and routes"),
        ("checkmark.seal.fill", "Service Reports: arrival and departure times, timed photos and the weather for every visit"),
        ("cloud.bolt.rain.fill", "Storm and trigger tools for snow contracts"),
        ("square.and.arrow.down.on.square", "Import your client list from a spreadsheet"),
        ("link", "A Request Link for new customers"),
        ("doc.text.fill", "Invoices and proposals without the PlowR line")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PlowR Pro")
                .font(.largeTitle.bold())
            ForEach(Self.features, id: \.text) { feature in
                Label {
                    Text(feature.text)
                } icon: {
                    Image(systemName: feature.icon)
                        .foregroundStyle(PlowRColor.accent)
                }
            }
            Text("Cancel any time. Your records stay, and you can always export them.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
