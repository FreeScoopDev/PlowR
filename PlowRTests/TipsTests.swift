//
//  TipsTests.swift
//  PlowRTests
//

import Foundation
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
    @Test(arguments: PlowRTips.routeTipIDs)
    func everyTipHasItsCopy(_ id: String) throws {
        let tip = try #require(PlowRTips.copy(id, in: try HelpGuide.load(from: .main)), "\(id) isn't in HelpGuide.json")
        #expect(HelpTip.isShort(title: tip.title, message: tip.message), "\(id)")
    }

    @Test func tipIDsAreDistinct() {
        #expect(Set(PlowRTips.routeTipIDs).count == PlowRTips.routeTipIDs.count)
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

    /// Launch configures TipKit, after the reset, before any view.
    @Test func launchConfiguresTips() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("PlowR/PlowRApp.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.contains("PlowRTips.configure()"))
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
