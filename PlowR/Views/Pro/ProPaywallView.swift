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

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            // Large text: the store's own close button floats over its
            // scrolled text. Hidden, and a close button of ours on a line above.
            if typeSize.isAccessibilitySize {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // the mark stays inside its circle
                            .foregroundStyle(PlowRColor.ink)
                            .frame(width: PlowRLayout.minTapTarget, height: PlowRLayout.minTapTarget)
                            .background(PlowRColor.raised, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, PlowRLayout.space4)
                .padding(.top, PlowRLayout.space3)
            }
            store
        }
    }

    private var store: some View {
        SubscriptionStoreView(productIDs: [Subscription.productID]) {
            ProPitch()
        }
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .policies)
        .storeButton(typeSize.isAccessibilitySize ? .hidden : .visible, for: .cancellation)
        .modifier(PolicyLinks())
        .onInAppPurchaseCompletion { _, result in
            guard case .success(.success(let verification)) = result else {
                // Cancelled, pending (Ask to Buy) or failed: Apple says so.
                return
            }
            if case .verified(let transaction) = verification {
                await transaction.finish()
            }
            await subscription.purchased(Subscription.purchase(verification))
        }
        // Restore Purchases isn't a purchase and doesn't come through the
        // completion above: read the plan whenever the entitlement changes.
        .currentEntitlementTask(for: Subscription.productID) { _ in
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
    /// Wide enough for the widest icon at the user's text size, so the text
    /// lines start at one place without an icon running into them.
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 40
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
                if typeSize.isAccessibilitySize {
                    // The icon above its text: beside it, the text had a
                    // sliver of the width.
                    Label {
                        Text(feature.text)
                    } icon: {
                        Image(systemName: feature.icon)
                            .foregroundStyle(PlowRColor.accent)
                    }
                    .labelStyle(IconAboveTitleLabelStyle())
                } else {
                    Label {
                        Text(feature.text)
                    } icon: {
                        Image(systemName: feature.icon)
                            .foregroundStyle(PlowRColor.accent)
                            .frame(width: iconWidth)
                    }
                }
            }
            Text("Cancel any time. Your records stay, and you can always export them.")
                .font(.footnote)
                .foregroundStyle(PlowRColor.inkSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A label's icon above its title, for accessibility text sizes (a Label
/// keeps its accessibility: the icon isn't a stop of its own).
struct IconAboveTitleLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            configuration.icon
            configuration.title
        }
    }
}
