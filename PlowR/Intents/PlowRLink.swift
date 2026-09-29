import Foundation

/// PlowR's own links (`plowr://`). Compiled into the app and the widget
/// extension, so what the widgets open and what the app handles can't drift
/// apart.
nonisolated enum PlowRLink: Equatable {
    /// The route in progress.
    case activeRoute

    static let scheme = "plowr"

    var url: URL? {
        var components = URLComponents()
        components.scheme = Self.scheme
        switch self {
        case .activeRoute:
            components.host = "activeRoute"
        }
        return components.url
    }

    init?(_ url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "activeRoute":
            self = .activeRoute
        default:
            return nil
        }
    }
}
