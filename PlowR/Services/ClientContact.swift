import Foundation

/// The ways the client page's Contact tile offers to reach a client, decided
/// here so a test can check them.
nonisolated enum ClientContact {
    enum Option: Equatable {
        case call, message, email, directions
    }

    /// What to say in the menu when there's no way to reach them.
    static let nothingToUse = "No phone, email or address"

    /// Call and Message need a number with something to dial ("n/a" has
    /// none, and a text to it goes nowhere either); Message also needs a
    /// device that can text. `canDrive`: somewhere to give directions to.
    static func options(phone: String, canText: Bool, hasEmail: Bool, canDrive: Bool) -> [Option] {
        var options: [Option] = []
        if MapLinks.callLink(phone) != nil {
            options.append(.call)
            if canText { options.append(.message) }
        }
        if hasEmail { options.append(.email) }
        if canDrive { options.append(.directions) }
        return options
    }
}
