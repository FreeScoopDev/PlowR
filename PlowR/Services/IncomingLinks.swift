import Foundation
import Observation

/// An Add to PlowR link (RequestLink) that opened the app, kept until it can
/// be acted on: at launch, Apple's sign-in check answers after the link
/// arrives, and a signed-out business signs in first. Decided by `route`
/// whenever what it depends on changes; cleared once the New Lead screen
/// closes or an alert about it is dismissed.
@MainActor
@Observable
final class IncomingLinks {
    static let shared = IncomingLinks()

    var pending: URL?

    /// What to do with an Add to PlowR link now.
    enum Route: Equatable {
        /// Sign-in is still being checked: decide when it answers.
        case wait
        /// The New Lead screen, for the business signed in here.
        case request(RequestLink.Request)
        /// Cut short or changed: nothing to add.
        case damaged
        /// A business that isn't signed in: it opens once they do.
        case signIn
        /// This device is set up for finding a service, not for a business.
        case notBusiness
        /// This device's data is about to be removed (Remove from This Device).
        case unavailable

        /// Shown in a window of its own (LeadRequestWindow): the New Lead
        /// screen, or why the link can't be read.
        var opensWindow: Bool {
            switch self {
            case .request, .damaged: true
            case .wait, .signIn, .notBusiness, .unavailable: false
            }
        }
    }

    /// The route for `url`; nil if it isn't an Add to PlowR link.
    static func route(for url: URL, role: String, isChecking: Bool, isSignedIn: Bool,
                      removalPending: Bool) -> Route? {
        guard RequestLink.isLeadLink(url) else { return nil }
        if removalPending { return .unavailable }
        guard role == UserRole.business else { return .notBusiness }
        guard isSignedIn else { return isChecking ? .wait : .signIn }
        return RequestLink.request(from: url).map { .request($0) } ?? .damaged
    }
}
