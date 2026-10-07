//
//  ICloudStatusTests.swift
//  PlowRTests
//

import CloudKit
import Foundation
import Testing
import UIKit
@testable import PlowR

/// When PlowR says the data isn't backed up to iCloud. It only warned when the
/// iCloud database failed to open, never when nobody was signed in to iCloud,
/// and Settings said "Data Backed Up to iCloud" regardless. These never ask
/// CloudKit: the account status is a stand-in.
@MainActor
struct ICloudStatusTests {
    @MainActor
    final class Setup {
        let suite = "ICloudStatusTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        let notifications = NotificationCenter()
        var status: CKAccountStatus = .available
        var fails = false
        var opened = true
        var turnedOff = false
        var checks = 0
        /// Checks held until the test answers them, in order.
        var holds = false
        var held: [CheckedContinuation<CKAccountStatus, Never>] = []

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
        }

        func make() -> ICloudStatus {
            ICloudStatus(check: { [unowned self] in
                             checks += 1
                             if fails { throw CKError(.networkUnavailable) }
                             if holds { return await withCheckedContinuation { held.append($0) } }
                             return status
                         },
                         databaseOpened: { [unowned self] in opened },
                         syncTurnedOff: { [unowned self] in turnedOff },
                         defaults: defaults, notifications: notifications)
        }

        deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        for _ in 0..<1000 where !condition() {      // Up to 5 s on a busy CI runner.
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition())
    }

    @Test func eachAccountStatusMapsToAState() {
        #expect(ICloudStatus.state(for: .available) == .available)
        #expect(ICloudStatus.state(for: .noAccount) == .noAccount)
        #expect(ICloudStatus.state(for: .restricted) == .restricted)
        #expect(ICloudStatus.state(for: .temporarilyUnavailable) == .temporarilyUnavailable)
        #expect(ICloudStatus.state(for: .couldNotDetermine) == .couldNotDetermine)
    }

    @Test func aSignedOutDeviceIsWarned() async throws {
        let s = try Setup()
        s.status = .noAccount
        let status = s.make()
        await status.refresh()
        #expect(status.state == .noAccount)
        #expect(status.warning?.title == "Not backed up to iCloud")
        #expect(status.banner == status.warning)
        #expect(status.summary.kind == .problem)
        #expect(status.summary.title == status.warning?.title)
    }

    // Each problem is told apart: a Screen Time restriction isn't fixed by
    // signing in. PlowR runs on iPad too, so no message says "iPhone".
    @Test func eachProblemHasItsOwnMessage() {
        let problems: [ICloudStatus.State] = [.noAccount, .restricted, .temporarilyUnavailable, .localOnly]
        let warnings = problems.compactMap(ICloudStatus.warning(for:))
        #expect(warnings.count == problems.count)
        #expect(Set(warnings.map(\.title)).count == problems.count)
        #expect(Set(warnings.map(\.message)).count == problems.count)
        #expect(ICloudStatus.warning(for: .restricted)?.message.contains("Screen Time") == true)
        #expect(ICloudStatus.warning(for: .noAccount)?.message.contains("signed in") == true)
        #expect(warnings.allSatisfy { !$0.message.contains("iPhone") && !$0.title.contains("iPhone") })
    }

    // Synced, not known yet, or iCloud couldn't answer: nothing the user can
    // fix, so no card. Settings says "Backed Up" only when iCloud said so.
    @Test func nothingIsShownWhenSyncedOrUnknown() async throws {
        let s = try Setup()
        let status = s.make()
        #expect(status.state == .checking)
        #expect(status.banner == nil)
        #expect(status.summary.kind == .unknown)
        await status.refresh()
        #expect(status.state == .available)
        #expect(status.banner == nil)
        #expect(status.summary.kind == .backedUp)
        #expect(status.summary.title == "Data Backed Up to iCloud")
        s.fails = true
        await status.refresh()
        #expect(status.state == .couldNotDetermine)
        #expect(status.banner == nil)
        #expect(status.summary.kind == .unknown)
        #expect(status.summary.title != "Data Backed Up to iCloud")
    }

    // The one case the old alert covered: the database didn't open with
    // iCloud, whatever the account says.
    @Test func aDatabaseThatDidntOpenWithICloudIsWarnedAbout() async throws {
        let s = try Setup()
        s.opened = false
        let status = s.make()
        await status.refresh()
        #expect(status.state == .localOnly)
        #expect(status.warning != nil)
        #expect(s.checks == 0)
    }

    // Sync turned off on this device (Remove from This Device, or the switch)
    // is said in Settings, not warned about on the Dashboard.
    @Test func syncTurnedOffHereIsSaidNotWarnedAbout() async throws {
        let s = try Setup()
        s.opened = false
        s.turnedOff = true
        let status = s.make()
        await status.refresh()
        #expect(status.state == .turnedOff)
        #expect(status.warning == nil && status.banner == nil)
        #expect(status.summary.title == "iCloud Sync Is Off on This Device")
        #expect(s.checks == 0)
    }

    // The old alert came back every time the Dashboard appeared.
    @Test func aClosedCardStaysClosedUntilSomethingElseIsWrong() async throws {
        let s = try Setup()
        s.status = .noAccount
        let status = s.make()
        await status.refresh()
        status.dismissBanner()
        #expect(status.banner == nil)
        #expect(status.warning != nil)                  // Settings still says so.
        let relaunched = s.make()
        await relaunched.refresh()
        #expect(relaunched.banner == nil)               // After a relaunch too.
        s.status = .temporarilyUnavailable
        await relaunched.refresh()
        #expect(relaunched.banner != nil)
    }

    // Closed, then fixed, then signed out again months later: said again.
    @Test func aClosedCardComesBackWhenItsProblemDoes() async throws {
        let s = try Setup()
        s.status = .noAccount
        let status = s.make()
        await status.refresh()
        status.dismissBanner()
        s.status = .available
        await status.refresh()
        s.status = .noAccount
        await status.refresh()
        #expect(status.banner != nil)
        #expect(s.defaults.string(forKey: ICloudStatus.dismissedKey) == nil)
    }

    // Back from signing in, two checks start close together. The first can
    // answer last, from before the sign-in: the newer answer stands.
    @Test func aLateAnswerDoesntOverwriteANewerOne() async throws {
        let s = try Setup()
        s.holds = true
        let status = s.make()
        let first = Task { await status.refresh() }
        try await waitUntil { s.held.count == 1 }
        let second = Task { await status.refresh() }
        try await waitUntil { s.held.count == 2 }
        s.held[1].resume(returning: .available)
        await second.value
        s.held[0].resume(returning: .noAccount)
        await first.value
        #expect(status.state == .available)
    }

    @Test func comingBackAndAccountChangesAreChecked() async throws {
        let s = try Setup()
        let status = s.make()
        status.watch()
        status.watch()                                  // Once is enough.
        try await waitUntil { s.checks == 1 }
        s.notifications.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        try await waitUntil { s.checks == 2 }
        s.notifications.post(name: .CKAccountChanged, object: nil)
        try await waitUntil { s.checks == 3 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(s.checks == 3)
    }

    // The app's own check, which the Dashboard runs, never reaches CloudKit
    // in a test run.
    @Test func theAppsCheckNeverAsksCloudKitUnderTests() async throws {
        #expect(try await ICloudStatus.accountStatus() == .couldNotDetermine)
    }
}
