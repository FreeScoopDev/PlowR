//
//  ICloudStatusTests.swift
//  PlowRTests
//

import CloudKit
import Foundation
import Testing
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
        var status: CKAccountStatus = .available
        var fails = false
        var opened = true
        var checks = 0

        init() throws {
            defaults = try #require(UserDefaults(suiteName: suite))
        }

        func make() -> ICloudStatus {
            ICloudStatus(check: { [unowned self] in
                             checks += 1
                             if fails { throw CKError(.networkUnavailable) }
                             return status
                         },
                         databaseOpened: { [unowned self] in opened },
                         defaults: defaults)
        }

        deinit { UserDefaults.standard.removePersistentDomain(forName: suite) }
    }

    @Test func eachAccountStatusMapsToAState() {
        #expect(ICloudStatus.state(for: .available) == .available)
        #expect(ICloudStatus.state(for: .noAccount) == .noAccount)
        #expect(ICloudStatus.state(for: .restricted) == .restricted)
        #expect(ICloudStatus.state(for: .temporarilyUnavailable) == .temporarilyUnavailable)
        #expect(ICloudStatus.state(for: .couldNotDetermine) == .couldNotDetermine)
    }

    @Test func aSignedOutIPhoneIsWarned() async throws {
        let s = try Setup()
        s.status = .noAccount
        let status = s.make()
        await status.refresh()
        #expect(status.state == .noAccount)
        #expect(status.warning?.title == "Not backed up to iCloud")
        #expect(status.banner == status.warning)
    }

    @Test func restrictedAndNeedsAttentionAreWarnedToo() async throws {
        let s = try Setup()
        let status = s.make()
        for account in [CKAccountStatus.restricted, .temporarilyUnavailable] {
            s.status = account
            await status.refresh()
            #expect(status.warning != nil, "\(account.rawValue)")
        }
    }

    // Synced, not known yet, or iCloud couldn't answer (no signal on a job
    // site): nothing the user can fix, so nothing is shown.
    @Test func nothingIsShownWhenSyncedOrUnknown() async throws {
        let s = try Setup()
        let status = s.make()
        #expect(status.state == .checking)
        #expect(status.banner == nil)
        await status.refresh()
        #expect(status.state == .available)
        #expect(status.banner == nil)
        s.status = .couldNotDetermine
        await status.refresh()
        #expect(status.banner == nil)
        s.fails = true
        await status.refresh()
        #expect(status.state == .couldNotDetermine)
        #expect(status.banner == nil)
    }

    // The one case the old alert covered: the database didn't open with
    // iCloud, so PlowR saves on this device only, whatever the account says.
    @Test func aDatabaseThatDidntOpenWithICloudIsLocalOnly() async throws {
        let s = try Setup()
        s.opened = false
        let status = s.make()
        await status.refresh()
        #expect(status.state == .localOnly)
        #expect(status.warning != nil)
        #expect(s.checks == 0)
    }

    // The old alert came back every time the Dashboard appeared.
    @Test func aClosedBannerStaysClosedUntilTheStateChanges() async throws {
        let s = try Setup()
        s.status = .noAccount
        let status = s.make()
        await status.refresh()
        status.dismissBanner()
        #expect(status.banner == nil)
        // Settings still says so.
        #expect(status.warning != nil)
        // After a relaunch too.
        let relaunched = s.make()
        await relaunched.refresh()
        #expect(relaunched.banner == nil)
        // Something new to say shows again.
        s.status = .temporarilyUnavailable
        await relaunched.refresh()
        #expect(relaunched.banner != nil)
    }

    // CloudKit without the iCloud entitlement or account, as in every test
    // run: the Dashboard's call must not reach it.
    @Test func watchingDoesNothingUnderTests() async throws {
        let s = try Setup()
        let status = s.make()
        status.watch()
        try await Task.sleep(for: .milliseconds(100))
        #expect(s.checks == 0)
        #expect(status.state == .checking)
    }
}
