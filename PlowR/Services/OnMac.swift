import Foundation

/// PlowR running on a Mac, as the iPad app (App Store: "iPhone and iPad Apps
/// on Apple Silicon Macs"). It works the same, apart from what a Mac can't
/// do: send texts, follow a route by GPS (arrival and departure times, the
/// offer to text the next client on leaving a stop, arrival estimates from
/// where you are), and show a Live Activity or a Control Center control.
/// Settings and the route screen say so (`limitations`).
nonisolated enum OnMac {
    static var isMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }

    /// What works differently on a Mac, line by line, for Settings.
    static let limitations = [
        "Texting clients isn't available: use PlowR on your iPhone to text, or Message All before a route.",
        "Routes are for planning and records here. GPS arrival and departure times, the offer to text the next client when you leave a stop, and arrival estimates need PlowR on an iPhone on the route.",
        "No Lock Screen Live Activity or Control Center control.",
        "Everything else (clients, the schedule, proposals, invoices, payments, contracts and reports) works the same, and syncs with your iPhone and iPad through iCloud."
    ]
}
