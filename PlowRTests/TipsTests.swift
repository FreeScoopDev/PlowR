//
//  TipsTests.swift
//  PlowRTests
//

import Foundation
import SwiftData
import Testing
@testable import PlowR

/// The tips (TipKit, 1.8): copy from the one help source, never configured
/// under tests, and erased by Delete Account & Data (App Review 5.1.1(v)),
/// which can only happen at the next launch, before TipKit opens its store.
@MainActor
struct TipsTests {
    typealias Account = AccountEraserTests.Account

    private func defaults() throws -> (UserDefaults, String) {
        let suite = "TipsTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suite)), suite)
    }

    /// Every tip's copy is in HelpGuide.json and keeps the tip rule. A tip
    /// whose id isn't there would show an empty title.
    @Test(arguments: PlowRTips.allTipIDs)
    func everyTipHasItsCopy(_ id: String) throws {
        let tip = try #require(PlowRTips.copy(id, in: try HelpGuide.load(from: .main)), "\(id) isn't in HelpGuide.json")
        #expect(HelpTip.isShort(title: tip.title, message: tip.message), "\(id)")
    }

    @Test func tipIDsAreDistinct() {
        #expect(Set(PlowRTips.allTipIDs).count == PlowRTips.allTipIDs.count)
    }

    @Test func aResetIsTakenOnce() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!PlowRTips.takeReset(defaults))
        PlowRTips.scheduleReset(defaults: defaults)
        #expect(PlowRTips.isResetPending(defaults))
        #expect(PlowRTips.takeReset(defaults))
        #expect(!PlowRTips.isResetPending(defaults))
        #expect(!PlowRTips.takeReset(defaults))
    }

    /// Under tests TipKit is never configured (the host is the app, with the
    /// app's store), so a reset asked for stays asked for, and no event is
    /// donated.
    @Test func testsNeverConfigureTips() throws {
        let (defaults, suite) = try defaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        PlowRTips.scheduleReset(defaults: defaults)
        PlowRTips.configure(defaults: defaults)
        #expect(!PlowRTips.isConfigured)
        #expect(PlowRTips.isResetPending(defaults))
    }

    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appendingPathComponent(path), encoding: .utf8)
    }

    /// Launch configures TipKit (a live line, not a comment) in
    /// `PlowRApp.init`, before any view.
    @Test func launchConfiguresTips() throws {
        let app = try source("PlowR/PlowRApp.swift")
        let configure = try #require(app.firstRange(of: /\n[ \t]*PlowRTips\.configure\(/))
        let initStart = try #require(app.range(of: "    init() {"))
        let initEnd = try #require(app.range(of: "\n    }\n", range: initStart.upperBound..<app.endIndex))
        #expect(initStart.upperBound < configure.lowerBound && configure.lowerBound < initEnd.lowerBound)
    }

    /// Every tip type in Services/Tips is in the list the copy test reads.
    @Test func everyTipTypeIsListed() throws {
        let folder = Self.root.appendingPathComponent("PlowR/Services/Tips")
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }
        var ids: [String] = []
        for file in files {
            let text = try source("PlowR/Services/Tips/\(file)")
            ids += text.matches(of: /static let helpID = "([^"]+)"/).map { String($0.1) }
        }
        #expect(!ids.isEmpty)
        #expect(Set(ids) == Set(PlowRTips.allTipIDs))
    }

    /// The Service Report's tip waits for a visit of this client's with a
    /// GPS arrival; another client's, or one with none, doesn't count.
    @Test func theServiceReportTipWaitsForAnArrival() throws {
        let h = try ActiveRouteStoreTests.Harness(stopCount: 0)
        let id = h.client.id.uuidString
        func record(client: String, arrived: Date?) {
            let record = ServiceRecord(operatorID: "op", sourceKey: "manual:\(UUID().uuidString)", source: .manual)
            record.clientID = client
            record.arrivedAt = arrived
            h.context.insert(record)
        }
        #expect(!PlowRTips.hasArrivals(clientID: id, in: h.context))
        record(client: id, arrived: nil)
        record(client: UUID().uuidString, arrived: h.clock)
        #expect(!PlowRTips.hasArrivals(clientID: id, in: h.context))
        record(client: id, arrived: h.clock)
        #expect(PlowRTips.hasArrivals(clientID: id, in: h.context))
    }

    /// Each client tip's action finishes it, in the screen that does the
    /// thing (a live line, not a comment). The import's only after it saved.
    @Test(arguments: [
        ("PlowR/Views/Clients/PipelineView.swift", "PlowRTips.done(PipelineTip(), PipelineTip.pipelineOpened)"),
        ("PlowR/Views/ServiceLog/ProofOfServiceView.swift", "PlowRTips.done(ServiceReportTip(), ServiceReportTip.reportOpened)"),
        ("PlowR/Views/Settings/RequestLinkView.swift", "PlowRTips.done(RequestLinkTip(), RequestLinkTip.linkOpened)"),
    ])
    func eachClientTipIsFinishedByItsAction(_ file: String, _ call: String) throws {
        let text = try source(file)
        // In the screen's own onAppear, live: not commented or compiled out.
        #expect(text.contains(".onAppear { \(call) }"), "\(file)")
        #expect(!text.contains("#if") && !text.contains("/*"), "\(file) has code that may not compile in")
    }

    /// Import Clients' screen saves through `saveFromScreen`, which finishes
    /// the import tip only once the clients are saved.
    @Test func theImportTipIsFinishedOnlyAfterTheClientsSaved() throws {
        var done: [String] = []
        PlowRTips.onDone = { done.append($0) }
        defer { PlowRTips.onDone = nil }
        let h = try ActiveRouteStoreTests.Harness(stopCount: 0)
        let table = CSVReader.Table(header: ["Name", "Phone", "Address"], rows: [["Pat Rowe", "", "1 Elm St"]])
        let preview = ClientImport.preview(table, fields: [.name, .phone, .address], existing: [],
                                           addressesAsProperties: false)
        struct DiskFull: Error {}
        #expect(throws: DiskFull.self) {
            try ClientImport.saveFromScreen(preview, as: .customers, operatorID: "op", in: h.context) { _ in
                throw DiskFull()
            }
        }
        #expect(done.isEmpty)
        _ = try ClientImport.saveFromScreen(preview, as: .customers, operatorID: "op", in: h.context)
        #expect(done == [ImportClientsTip.helpID])
        let view = try source("PlowR/Views/Clients/ImportClientsView.swift")
        #expect(view.contains("result = try ClientImport.saveFromScreen("))
        #expect(!view.contains("try ClientImport.save(fresh"))
    }

    /// Documents' money tips: an overdue invoice there's a Send Reminder
    /// for, and a sent invoice with no way to pay printed on it.
    @Test func theDocumentsTipsWaitOnTheirInvoices() throws {
        let h = try ActiveRouteStoreTests.Harness(stopCount: 0)
        let pat = h.client.id.uuidString
        func invoice(sent: Bool, dueDaysAgo: Double?, client: String? = nil) -> Proposal {
            let doc = Proposal(operatorID: "op", client: h.client)
            doc.invoiceNumber = "INV-\(Int.random(in: 1_000...9_999))"
            doc.invoiceSentAt = sent ? Date().addingTimeInterval(-40 * 86_400) : nil
            doc.invoiceDueDate = dueDaysAgo.map { Date().addingTimeInterval(-$0 * 86_400) }
            if let client { doc.clientID = client }
            h.context.insert(doc)
            return doc
        }
        func state(_ docs: [Proposal], methods: Int = 0, canText: Bool = true,
                   textable: Set<String>? = nil) -> PlowRTips.DocumentsState {
            PlowRTips.documentsState(invoices: docs, activePaymentMethods: methods, canText: canText,
                                     textable: textable ?? [pat])
        }
        let draft = invoice(sent: false, dueDaysAgo: nil)
        // A proposal marked sent isn't an invoice out.
        let sentProposal = Proposal(operatorID: "op", client: h.client)
        sentProposal.invoiceSentAt = Date()
        h.context.insert(sentProposal)
        #expect(state([draft, sentProposal]) == .init(hasOverdue: false, needsPaymentMethod: false))
        let sent = invoice(sent: true, dueDaysAgo: -5)                         // due in 5 days
        #expect(state([draft, sent]) == .init(hasOverdue: false, needsPaymentMethod: true))
        #expect(state([draft, sent], methods: 1) == .init(hasOverdue: false, needsPaymentMethod: false))
        let late = invoice(sent: true, dueDaysAgo: 3)
        #expect(state([late], methods: 2) == .init(hasOverdue: true, needsPaymentMethod: false))
        // No Send Reminder to tap: a device that can't text, or a client with no phone.
        #expect(!state([late], methods: 2, canText: false).hasOverdue)
        #expect(!state([late], methods: 2, textable: []).hasOverdue)
    }

    /// Create Route's tip never leads to the paywall.
    @Test func createRoutesTipWaitsForARouteThatCanBeMade() {
        #expect(PlowRTips.routeFromDayCount(4, canCreateRoute: true) == 4)
        #expect(PlowRTips.routeFromDayCount(4, canCreateRoute: false) == 0)
    }

    /// Bill Unbilled Work finishes its tip only when it made an invoice.
    @Test func billingFinishesTheTipOnlyWhenItBilled() {
        var done: [String] = []
        PlowRTips.onDone = { done.append($0) }
        defer { PlowRTips.onDone = nil }
        PlowRTips.billed(WorkBilling.Outcome())
        #expect(done.isEmpty)
        var made = WorkBilling.Outcome()
        made.invoices = [Proposal(operatorID: "op", client: Client(name: "Pat", phone: "", address: "", operatorID: "op"))]
        PlowRTips.billed(made)
        #expect(done == [BillWorkTip.helpID])
    }

    /// Each schedule and money tip is finished by its action, live (not
    /// commented or compiled out), from every screen that does it.
    @Test(arguments: [
        ("PlowR/Views/Schedule/AddVisitView.swift", "if isRecurring { PlowRTips.done(RepeatVisitTip(), RepeatVisitTip.visitRepeated) }"),
        ("PlowR/Views/Schedule/ScheduleView.swift", "PlowRTips.done(RouteFromDayTip(), RouteFromDayTip.routeMade)"),
        ("PlowR/Views/Proposals/BillWorkView.swift", "if let outcome { PlowRTips.billed(outcome) }"),
        ("PlowR/Views/Proposals/ProposalListView.swift", "PlowRTips.reminderOpened()"),
        ("PlowR/Views/Proposals/ProposalDetailView.swift", "PlowRTips.reminderOpened()"),
        ("PlowR/Views/Settings/PaymentMethodsView.swift", "PlowRTips.done(PaymentMethodsTip(), PaymentMethodsTip.methodAdded)"),
    ])
    func eachMoneyTipIsFinishedByItsAction(_ file: String, _ call: String) throws {
        let text = try source(file)
        let lines = text.split(separator: "\n").filter { $0.contains(call) }
        #expect(lines.count == 1, "\(file)")
        #expect(lines.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }, "\(file)")
        #expect(!text.contains("#if") && !text.contains("/*"), "\(file) has code that may not compile in")
    }

    /// Create Route's tip is done only once a route was made: after the
    /// guard that stops on no stops.
    @Test func createRoutesTipIsDoneOnlyAfterARouteIsMade() throws {
        let text = try source("PlowR/Views/Schedule/ScheduleView.swift")
        let guardLine = try #require(text.range(of: "guard !stops.isEmpty else {"))
        let done = try #require(text.range(of: "PlowRTips.done(RouteFromDayTip(), RouteFromDayTip.routeMade)"))
        #expect(guardLine.upperBound < done.lowerBound)
    }

    @Test func aBusinessThatHasRunARouteIsNotOnItsFirst() {
        #expect(!PlowRTips.hasRunRoute(completedRoutes: 0, serviceRecords: 0))
        #expect(PlowRTips.hasRunRoute(completedRoutes: 1, serviceRecords: 0))
        #expect(PlowRTips.hasRunRoute(completedRoutes: 0, serviceRecords: 3))
    }

    /// A stop completed from Siri or Control Center finishes the Siri tip;
    /// one that wasn't completed doesn't.
    @Test func siriAndControlCenterFinishTheSiriTip() throws {
        var done: [String] = []
        PlowRTips.onDone = { done.append($0) }
        defer { PlowRTips.onDone = nil }
        let h = try ActiveRouteStoreTests.Harness()
        let store = h.makeStore()
        store.start(h.route)
        let first = try #require(store.currentStopID)
        _ = CompleteStopAction.siri(in: store, role: UserRole.business)
        #expect(done == [SiriTip.helpID])
        _ = CompleteStopAction.controlCenter(stopID: first, in: store, role: UserRole.business)
        #expect(done == [SiriTip.helpID], "an already-done stop completes nothing")
        let second = try #require(store.currentStopID)
        _ = CompleteStopAction.controlCenter(stopID: second, in: store, role: UserRole.business)
        #expect(done == [SiriTip.helpID, SiriTip.helpID])
    }

    @Test func deleteEverythingErasesTheTipsAtNextLaunch() throws {
        let account = try Account()
        defer { account.removeFiles() }
        #expect(account.eraser().eraseAll().isEmpty)
        #expect(PlowRTips.isResetPending(account.defaults))
    }

    @Test func removeFromThisDeviceErasesTheTipsAtNextLaunch() throws {
        let account = try Account()
        defer { account.removeFiles() }
        #expect(account.eraser().removeFromThisDevice().isEmpty)
        #expect(PlowRTips.isResetPending(account.defaults))
    }

    /// A failed step keeps the preferences (to retry), and the tips with them.
    @Test func aFailedEraseLeavesTheTips() throws {
        let account = try Account()
        defer { account.removeFiles() }
        var eraser = account.eraser()
        eraser.eraseCalendar = { throw CocoaError(.fileWriteNoPermission) }
        #expect(!eraser.eraseAll().isEmpty)
        #expect(!PlowRTips.isResetPending(account.defaults))
    }
}
