import TipKit

/// The route tips (1.8, B1). Copy in `HelpGuide.json`, rules in
/// `PlowRTips`. Each goes away for good once the user does the thing (an
/// event), and is shown once (twice for a swipe, which is easy to miss).

/// Route page, first: a stop opens its services.
nonisolated struct StopServicesTip: PlowRTip {
    static let helpID = "tip-stop-services"
    static let servicesSaved = Tips.Event(id: "stopServicesSaved")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$canEdit) { $0 == true }
        #Rule(Self.servicesSaved) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Route page: a stop can sit out today's run.
nonisolated struct SkipTodayTip: PlowRTip {
    static let helpID = "tip-skip-today"
    static let stopSkipped = Tips.Event(id: "stopSkipped")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$canEdit) { $0 == true }
        #Rule(Self.stopSkipped) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(2)] }
}

/// Route page: PlowR can put the stops in order, with two or more pinned
/// stops, the least Optimize Order works on (the page says).
nonisolated struct OptimizeOrderTip: PlowRTip {
    static let helpID = "tip-optimize-order"
    static let routeOptimized = Tips.Event(id: "routeOptimized")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$canEdit) { $0 == true }
        #Rule(Self.routeOptimized) { $0.donations.count == 0 }
        #Rule(PlowRTips.$pinnedStopsReady) { $0 == true }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Route screen, inline, on the first route only: the one tip shown while a
/// route runs. Not held back by Get Started, which a first route nearly
/// always has steps left on, nor by the day's tip: there's one first route.
nonisolated struct RecordServicesTip: PlowRTip {
    static let helpID = "tip-record-services"
    static let servicesRecorded = Tips.Event(id: "servicesRecorded")

    var rules: [Rule] {
        #Rule(PlowRTips.$hasRunRoute) { $0 == false }
        #Rule(Self.servicesRecorded) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1), IgnoresDisplayFrequency(true)] }
}

/// Route Recap: Siri and Control Center finish a stop without the app.
/// Not on a Mac (no Control Center for an iPhone app there).
nonisolated struct SiriTip: PlowRTip {
    static let helpID = "tip-siri"
    /// A stop completed from Siri or Control Center (CompleteStopAction).
    static let completedFromOutside = Tips.Event(id: "stopCompletedFromOutside")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$onMac) { $0 == false }
        #Rule(Self.completedFromOutside) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Route Recap, after Siri: the widget, unless it's on a Home Screen
/// already (the Recap looks). Not on a Mac.
nonisolated struct WidgetTip: PlowRTip {
    static let helpID = "tip-widget"

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$onMac) { $0 == false }
        #Rule(PlowRTips.$hasRouteWidget) { $0 == false }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

nonisolated extension PlowRTips {
    /// Every tip's copy id, for TipsTests.
    static let routeTipIDs = [StopServicesTip.helpID, SkipTodayTip.helpID, OptimizeOrderTip.helpID,
                              RecordServicesTip.helpID, SiriTip.helpID, WidgetTip.helpID]
}
