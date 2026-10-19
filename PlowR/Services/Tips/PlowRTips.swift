import Foundation
import os
import SwiftUI
import TipKit
import WidgetKit

/// PlowR's tips (TipKit, since 1.8): a feature taught once, when it's
/// useful. Their copy is in the one help source, `HelpGuide.json` (a topic's
/// `tips`), by the tip's id, so the website, the guide and the tips never
/// say different things.
///
/// The house rules, as TipKit rules on the parameters below: at most one tip
/// a day (`.daily`) and one on a screen (a `TipGroup` per screen); none while
/// Get Started has steps left or a route runs (except Record Services on the
/// first route); editing tips not while read only; Mac-irrelevant tips not on
/// a Mac. Tips never sell: no price, no paywall.
nonisolated enum PlowRTips {
    /// Delete Account & Data, and Show Tips Again, set this: the tips store
    /// can be reset only before TipKit is configured, so at the next launch.
    static let resetKey = "resetTipsAtLaunch"
    #if DEBUG
    /// `-PlowRShowTips YES`: every tip, for checking them by eye.
    static let showAllKey = "PlowRShowTips"
    #endif

    /// The Dashboard's Get Started card is showing (steps left). Quiet until
    /// the Dashboard says otherwise.
    @Parameter static var gettingStarted: Bool = true
    /// Not read only (`access.canEdit`): editing tips need it.
    @Parameter static var canEdit: Bool = true
    /// PlowR Pro or its trial (`access.tier == .pro`), for Pro-only tips.
    @Parameter static var isPro: Bool = false
    /// Running on a Mac (`OnMac`): no GPS, texting, widgets or Control Center tips.
    @Parameter static var onMac: Bool = false
    /// A route has been run (this device's count, or any visit in the Service
    /// Log, so an upgrading business isn't taught its first route).
    @Parameter static var hasRunRoute: Bool = false
    /// The Today's Route widget is on a Home Screen.
    @Parameter static var hasRouteWidget: Bool = false
    /// The route page on screen has two pinned stops, the least Optimize
    /// Order works on.
    @Parameter static var pinnedStopsReady: Bool = false
    /// This business's active clients (the client list), for tips that
    /// wait until there are a few.
    @Parameter static var clientCount: Int = 0
    /// The client list shows the Pipeline (there are leads or quotes).
    @Parameter static var hasPipeline: Bool = false
    /// The client page on screen has a visit with a GPS arrival time, what
    /// the Service Report is best at showing.
    @Parameter static var clientHasArrivals: Bool = false

    /// Called with a tip's id when `done` runs, configured or not: lets
    /// tests see an action finish its tip.
    nonisolated(unsafe) static var onDone: ((String) -> Void)?

    /// Set once, on the main actor, at launch; read anywhere after.
    nonisolated(unsafe) private(set) static var isConfigured = false
    private static let log = Logger(subsystem: "Scoops.PlowR", category: "Tips")

    /// From `PlowRApp.init`, before any view. Not under tests (their host is
    /// the app, and a test must not leave tips in its store).
    @MainActor
    static func configure(defaults: UserDefaults = .standard, hasRunRoute ranRoute: Bool = false) {
        guard !PlowRApp.isRunningUnderTests, !isConfigured else { return }
        if takeReset(defaults) {
            do { try Tips.resetDatastore() } catch {
                log.error("The tips store couldn't be reset: \(error.localizedDescription, privacy: .public)")
            }
        }
        #if DEBUG
        // Screenshots show no tips; -PlowRShowTips shows every one (with
        // the demo's data too).
        if defaults.bool(forKey: showAllKey) {
            Tips.showAllTipsForTesting()
        } else if DemoLaunch.isOn || DemoLaunch.isNew {
            Tips.hideAllTipsForTesting()
        }
        #endif
        do {
            // The app's own container: not the app group (the widget has no
            // tips), not iCloud (a tip seen on one device is for that device).
            try Tips.configure([.displayFrequency(.daily), .datastoreLocation(.applicationDefault)])
            isConfigured = true
            onMac = OnMac.isMac
            if ranRoute { hasRunRoute = true }
        } catch {
            log.error("Tips couldn't be configured: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Whether this business has run a route before: what launch tells
    /// `configure`.
    static func hasRunRoute(completedRoutes: Int, serviceRecords: Int) -> Bool {
        completedRoutes > 0 || serviceRecords > 0
    }

    /// Changes rule parameters, only once TipKit is configured (never under
    /// tests, where views and the route store still run).
    static func update(_ change: () -> Void) {
        guard isConfigured else { return }
        change()
    }

    /// A route ended: the next isn't the first.
    static func routeRan() {
        update { hasRunRoute = true }
    }

    /// Looks for the Today's Route widget on a Home Screen.
    @MainActor
    static func checkRouteWidget() async {
        guard isConfigured,
              let widgets = try? await WidgetCenter.shared.currentConfigurations() else { return }
        let has = widgets.contains { $0.kind == WidgetDataStore.widgetKind }
        update { hasRouteWidget = has }
    }

    /// Tips come back (and the store is erased) at the next launch.
    static func scheduleReset(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: resetKey)
    }

    static func isResetPending(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: resetKey)
    }

    /// Whether a reset was asked for, clearing the ask.
    static func takeReset(_ defaults: UserDefaults) -> Bool {
        guard defaults.bool(forKey: resetKey) else { return false }
        defaults.removeObject(forKey: resetKey)
        return true
    }

    /// Records that the user did the thing an event stands for. Only once
    /// TipKit is configured, so tests and previews leave no store behind.
    static func donate(_ event: Tips.Event<Tips.EmptyDonation>) {
        guard isConfigured else { return }
        Task { await event.donate() }
    }

    /// The user did what `tip` teaches: it never shows again, nor do tips
    /// whose rules wait on `event`.
    static func done<T: PlowRTip>(_ tip: T, _ event: Tips.Event<Tips.EmptyDonation>) {
        onDone?(T.helpID)
        guard isConfigured else { return }
        donate(event)
        tip.invalidate(reason: .actionPerformed)
    }

    /// A tip's copy from the help guide. A missing id shows nothing rather
    /// than a placeholder (TipsTests fails a tip whose id isn't there).
    static func copy(_ id: String, in guide: HelpGuide = .shared) -> HelpTip? {
        guide.topics.lazy.flatMap(\.tips).first { $0.id == id }
    }
}

/// A PlowR tip: its id names its copy in `HelpGuide.json`.
nonisolated protocol PlowRTip: Tip {
    static var helpID: String { get }
}

nonisolated extension PlowRTip {
    var id: String { Self.helpID }

    var title: Text {
        Text(HelpText.attributed(PlowRTips.copy(Self.helpID)?.title ?? ""))
    }

    var message: Text? {
        PlowRTips.copy(Self.helpID).map { Text(HelpText.attributed($0.message)) }
    }
}

/// Tells the tips what `access` says, for the rules (`MainTabView`, inside
/// `.providesAccess()`).
struct TipsAccessFeed: ViewModifier {
    @Environment(\.access) private var access

    func body(content: Content) -> some View {
        content
            .onChange(of: access.canEdit, initial: true) { _, canEdit in PlowRTips.update { PlowRTips.canEdit = canEdit } }
            .onChange(of: access.tier == .pro, initial: true) { _, isPro in PlowRTips.update { PlowRTips.isPro = isPro } }
    }
}

extension View {
    /// See `TipsAccessFeed`. Goes inside `.providesAccess()`.
    func feedsTips() -> some View {
        modifier(TipsAccessFeed())
    }
}
