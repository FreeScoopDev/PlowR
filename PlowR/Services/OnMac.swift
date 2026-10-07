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
        "Texting clients isn't available on a Mac: send texts, Message All included, from PlowR on your iPhone.",
        "Routes are for planning and records here: PlowR doesn't follow your location on a Mac, so there are no GPS arrival and departure times, offers to text the next client when you leave a stop, or arrival estimates. Run routes on your iPhone.",
        "No camera: add photos from your library, and scan business cards on your iPhone.",
        "No Lock Screen Live Activity or Control Center control.",
        "Everything else (clients, the schedule, proposals, invoices, payments, contracts and reports) works the same, and syncs with your iPhone and iPad through iCloud."
    ]
}
