import SwiftData
import TipKit

/// The client and lead tips (1.8, B2). Copy in `HelpGuide.json`, rules in
/// `PlowRTips`. Each goes away for good once the user does the thing.

/// Client list, first: the Pipeline, once it shows (there are leads or quotes).
nonisolated struct PipelineTip: PlowRTip {
    static let helpID = "tip-pipeline"
    static let pipelineOpened = Tips.Event(id: "pipelineOpened")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$hasPipeline) { $0 == true }
        #Rule(Self.pipelineOpened) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Client list: a whole list comes in from a spreadsheet, once a few
/// clients have been added. PlowR Pro (an import is a Pro feature).
nonisolated struct ImportClientsTip: PlowRTip {
    static let helpID = "tip-import-clients"
    static let clientsImported = Tips.Event(id: "clientsImported")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$canEdit) { $0 == true }
        #Rule(PlowRTips.$isPro) { $0 == true }
        #Rule(PlowRTips.$clientCount) { $0 >= 3 }
        #Rule(Self.clientsImported) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Client page: the Service Report, once the client has a visit with a GPS
/// arrival time. PlowR Pro.
nonisolated struct ServiceReportTip: PlowRTip {
    static let helpID = "tip-service-report"
    static let reportOpened = Tips.Event(id: "serviceReportOpened")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$isPro) { $0 == true }
        #Rule(PlowRTips.$clientHasArrivals) { $0 == true }
        #Rule(Self.reportOpened) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

/// Settings: the Request Link, once there are a few clients. PlowR Pro.
nonisolated struct RequestLinkTip: PlowRTip {
    static let helpID = "tip-request-link"
    static let linkOpened = Tips.Event(id: "requestLinkOpened")

    var rules: [Rule] {
        #Rule(PlowRTips.$gettingStarted) { $0 == false }
        #Rule(PlowRTips.$canEdit) { $0 == true }
        #Rule(PlowRTips.$isPro) { $0 == true }
        #Rule(PlowRTips.$clientCount) { $0 >= 5 }
        #Rule(Self.linkOpened) { $0.donations.count == 0 }
    }

    var options: [any TipOption] { [MaxDisplayCount(1)] }
}

extension PlowRTips {
    /// Whether the client has a visit with a GPS arrival time (the Service
    /// Report's tip waits for one).
    @MainActor
    static func hasArrivals(clientID: String, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<ServiceRecord>(
            predicate: #Predicate { $0.clientID == clientID && $0.arrivedAt != nil })
        descriptor.fetchLimit = 1
        return ((try? context.fetchCount(descriptor)) ?? 0) > 0
    }
}

nonisolated extension PlowRTips {
    /// Every client and lead tip, for TipsTests (which fails a PlowRTip not listed).
    static let clientTipTypes: [any PlowRTip.Type] = [PipelineTip.self, ImportClientsTip.self,
                                                      ServiceReportTip.self, RequestLinkTip.self]
    static var clientTipIDs: [String] { clientTipTypes.map { $0.helpID } }
    /// Every tip there is.
    static var allTipIDs: [String] { routeTipIDs + clientTipIDs }
}
