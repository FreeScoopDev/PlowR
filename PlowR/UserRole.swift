import Foundation

/// The role chosen at first launch, kept in preferences under `key`. A
/// business runs routes; a client finds a business and requests work. Empty
/// until chosen, which shows the role screen.
nonisolated enum UserRole {
    static let key = "userRole"
    /// Stored on every business's device since the first version: a new
    /// value would send them all back to the role screen.
    static let business = "operator"
    static let client = "client"
}
