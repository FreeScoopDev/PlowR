import TipKit

/// The snow-only tips (1.8, B4), apart from the shared ones: the service-
/// language guard keeps snow wording off shared screens, and these are for
/// the storm card only. Copy in `HelpGuide.json` (a snow-only topic).

/// Home's storm card: text the clients whose contract trigger the forecast
/// reaches. PlowR Pro (storm texts are).
nonisolated struct StormTextTip: PlowRTip {
    static let helpID = "tip-storm-text"
    static let stormTexted = Tips.Event(id: "stormTexted")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$isPro) { $0 == true }
        #Rule(Self.stormTexted) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

nonisolated extension PlowRTips {
    /// Every snow-only tip, for TipsTests (which fails a PlowRTip not listed).
    static let snowTipTypes: [any PlowRTip.Type] = [StormTextTip.self]
    static var snowTipIDs: [String] { snowTipTypes.map { $0.helpID } }
}
