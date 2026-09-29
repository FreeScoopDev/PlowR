import CloudKit
import Foundation
import UIKit

/// Whether PlowR's data is backed up and synced through iCloud, for the
/// Dashboard card and Settings > Data & Backup.
///
/// The iCloud database opens without complaint when nobody is signed in to
/// iCloud, and then nothing syncs. PlowR only warned when the database failed
/// to open, which is rare, so a signed-out user was never told their clients
/// were on one device only. It now asks iCloud for the account's status: when
/// the Dashboard first appears, when the app comes back, and when the account
/// changes.
@MainActor
@Observable
final class ICloudStatus {
    enum State: String, Equatable {
        /// Not asked yet.
        case checking
        case available
        case noAccount
        case restricted
        /// Signed in, but the account needs attention (new terms, a password).
        case temporarilyUnavailable
        /// iCloud couldn't say. The reason isn't given, and there's nothing
        /// for the user to do about it.
        case couldNotDetermine
        /// The iCloud database didn't open at launch.
        case localOnly
    }

    struct Warning: Equatable {
        var title: String
        var message: String
    }

    static let shared = ICloudStatus(check: accountStatus, databaseOpened: { PlowRApp.isCloudKitAvailable })
    /// The warning the user closed on the Dashboard. It comes back when the
    /// problem does, after iCloud has worked in between.
    static let dismissedKey = "iCloudWarningDismissed"

    /// The account's status from CloudKit, never under tests: asking CloudKit
    /// from an unsigned test build, with no iCloud entitlement or account, is
    /// what the "Tests must never touch real CloudKit" note in CLAUDE.md is about.
    static func accountStatus() async throws -> CKAccountStatus {
        guard !PlowRApp.isRunningUnderTests else { return .couldNotDetermine }
        return try await CKContainer(identifier: PlowRApp.iCloudContainer).accountStatus()
    }

    private(set) var state: State = .checking
    private(set) var dismissed: State?

    @ObservationIgnored private let check: () async throws -> CKAccountStatus
    @ObservationIgnored private let databaseOpened: () -> Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifications: NotificationCenter
    @ObservationIgnored private var isWatching = false
    /// Bumped by every check, so one that answers late can't overwrite a
    /// newer one: back from signing in, the first check can still see the
    /// account signed out.
    @ObservationIgnored private var generation = 0

    init(check: @escaping () async throws -> CKAccountStatus, databaseOpened: @escaping () -> Bool,
         defaults: UserDefaults = .standard, notifications: NotificationCenter = .default) {
        self.check = check
        self.databaseOpened = databaseOpened
        self.defaults = defaults
        self.notifications = notifications
        dismissed = defaults.string(forKey: Self.dismissedKey).flatMap(State.init(rawValue:))
    }

    /// Checks now, then whenever the app comes back or the account changes.
    func watch() {
        guard !isWatching else { return }
        isWatching = true
        for name in [UIApplication.didBecomeActiveNotification, Notification.Name.CKAccountChanged] {
            notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.refresh() }
                }
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        generation += 1
        let asked = generation
        guard databaseOpened() else {
            state = .localOnly
            return
        }
        let answer: State
        do {
            answer = Self.state(for: try await check())
        } catch {
            answer = .couldNotDetermine
        }
        guard asked == generation else { return }   // A newer check's answer stands.
        state = answer
        // Working again: a warning closed before shows if its problem comes back.
        if answer == .available, dismissed != nil {
            dismissed = nil
            defaults.removeObject(forKey: Self.dismissedKey)
        }
    }

    nonisolated static func state(for status: CKAccountStatus) -> State {
        switch status {
        case .available: return .available
        case .noAccount: return .noAccount
        case .restricted: return .restricted
        case .temporarilyUnavailable: return .temporarilyUnavailable
        case .couldNotDetermine: return .couldNotDetermine
        @unknown default: return .couldNotDetermine
        }
    }

    /// What's wrong. Nil when there's nothing to tell: synced, or not known.
    var warning: Warning? { Self.warning(for: state) }

    /// The Dashboard card: the warning, unless the user closed it.
    var banner: Warning? { state == dismissed ? nil : warning }

    func dismissBanner() {
        dismissed = state
        defaults.set(state.rawValue, forKey: Self.dismissedKey)
    }

    /// What Settings > Data & Backup says. "Backed Up" only when iCloud said
    /// so; it used to say that whatever iCloud's state.
    var summary: Warning {
        if let warning { return warning }
        switch state {
        case .available:
            return Warning(title: "Data Backed Up to iCloud",
                           message: "Your clients, routes, and documents sync automatically across your devices and are stored securely in your private iCloud account.")
        case .checking:
            return Warning(title: "iCloud", message: "Checking whether your data is backed up…")
        default:
            return Warning(title: "iCloud",
                           message: "PlowR couldn't check iCloud just now. When iCloud is on, your clients, routes, and documents sync across your devices through your private iCloud account.")
        }
    }

    nonisolated static func warning(for state: State) -> Warning? {
        switch state {
        case .checking, .available, .couldNotDetermine:
            return nil
        case .noAccount:
            return Warning(title: "Not backed up to iCloud",
                           message: "PlowR can't use iCloud on this device: it isn't signed in, or iCloud is off for PlowR. Until it can, your clients, routes and documents are only on this device. Check in the Settings app, under your name at the top.")
        case .restricted:
            return Warning(title: "iCloud is restricted",
                           message: "iCloud is restricted on this device, by Screen Time or by whoever manages the device, so your clients, routes and documents are only on this device.")
        case .temporarilyUnavailable:
            return Warning(title: "iCloud needs attention",
                           message: "Your Apple Account needs attention before PlowR can sync. Open the Settings app and tap your name at the top. Until then, changes stay on this device.")
        case .localOnly:
            return Warning(title: "iCloud sync may be off",
                           message: "PlowR couldn't open its iCloud database when it started, so your changes may not reach iCloud or your other devices. If this still shows after you reopen PlowR, contact support from Settings.")
        }
    }
}
