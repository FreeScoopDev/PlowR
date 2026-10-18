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

/// Route page: PlowR can put the stops in order. The page shows it only with
/// two or more pinned stops, the least Optimize Order works on.
nonisolated struct OptimizeOrderTip: PlowRTip {
    static let helpID = "tip-optimize-order"
    static let routeOptimized = Tips.Event(id: "routeOptimized")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$canEdit) { $0 == true }
        #Rule(Self.routeOptimized) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Route screen, inline, on the first route only: the one tip shown while a
/// route runs. Not held back by Get Started, which a first route nearly
/// always has steps left on.
nonisolated struct RecordServicesTip: PlowRTip {
    static let helpID = "tip-record-services"
    static let servicesRecorded = Tips.Event(id: "servicesRecorded")
    /// A route ended: the next one isn't the first.
    static let routeEnded = Tips.Event(id: "routeEnded")

    var rules: [Rule] {
        #Rule(Self.routeEnded) { $0.donations.count == 0 }
        #Rule(Self.servicesRecorded) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Route Recap: Siri and Control Center finish a stop without the app.
/// Not on a Mac (no Control Center for an iPhone app there).
nonisolated struct SiriTip: PlowRTip {
    static let helpID = "tip-siri"

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$onMac) { $0 == false }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Route Recap, after Siri: the widget. Not on a Mac.
nonisolated struct WidgetTip: PlowRTip {
    static let helpID = "tip-widget"

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$onMac) { $0 == false }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

nonisolated extension PlowRTips {
    /// Every tip's copy id, for TipsTests.
    static let routeTipIDs = [StopServicesTip.helpID, SkipTodayTip.helpID, OptimizeOrderTip.helpID,
                              RecordServicesTip.helpID, SiriTip.helpID, WidgetTip.helpID]
}
