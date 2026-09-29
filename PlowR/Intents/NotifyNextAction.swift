import Foundation

/// Siri's "Notify next client": a text to the client you're driving to, the
/// route's current stop. It completes nothing. Say "Complete current stop"
/// first; after it, the current stop is the next client.
///
/// It used to open the route screen's own prompt, whose Send and Skip also
/// complete the current stop: after "Complete current stop", that offered
/// to text the client after next and marked a stop not yet reached as done.
enum NotifyNextAction {
    struct Reply: Equatable {
        var text: String
        /// The stop whose client to text, or nil when there's none.
        var stopID: UUID?
    }

    static func siri(in store: ActiveRouteStore, role: String?) -> Reply {
        guard role == UserRole.business else { return noRoute }
        store.validate()
        guard store.isActive else { return noRoute }
        guard let stop = store.currentStop else {
            return Reply(text: "Every stop on this route is already done.", stopID: nil)
        }
        let name = stop.clientName.isEmpty ? "This stop" : stop.clientName
        guard !stop.clientPhone.isEmpty else {
            return Reply(text: "\(name) has no phone number in PlowR.", stopID: nil)
        }
        return Reply(text: "Opening a text to \(name).", stopID: stop.id)
    }

    private static let noRoute = Reply(text: "No route is in progress.", stopID: nil)
}
