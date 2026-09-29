import CloudKit
import Foundation
import UIKit

/// Whether PlowR's data is backed up and synced through iCloud, for the
/// Dashboard banner and Settings > Data & Backup.
///
/// The iCloud database opens without complaint when nobody is signed in to
/// iCloud, and then nothing syncs. PlowR only warned when the database failed
/// to open, which is rare, so a signed-out user was never told their clients
/// were on one phone only. It now asks iCloud for the account's status: when
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
        /// iCloud couldn't say: no signal, say. Nothing for the user to fix.
        case couldNotDetermine
        /// The iCloud database didn't open, so PlowR saves on this device only.
        case localOnly
    }

    struct Warning: Equatable {
        var title: String
        var message: String
    }

    static let shared = ICloudStatus(
        check: { try await CKContainer(identifier: PlowRApp.iCloudContainer).accountStatus() },
        databaseOpened: { PlowRApp.isCloudKitAvailable })
    /// The warning the user closed on the Dashboard; it comes back when the
    /// state changes.
    static let dismissedKey = "iCloudWarningDismissed"

    private(set) var state: State = .checking
    private(set) var dismissed: State?

    @ObservationIgnored private let check: () async throws -> CKAccountStatus
    @ObservationIgnored private let databaseOpened: () -> Bool
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var isWatching = false

    init(check: @escaping () async throws -> CKAccountStatus, databaseOpened: @escaping () -> Bool,
         defaults: UserDefaults = .standard) {
        self.check = check
        self.databaseOpened = databaseOpened
        self.defaults = defaults
        dismissed = defaults.string(forKey: Self.dismissedKey).flatMap(State.init(rawValue:))
    }

    /// Checks now, then whenever the app comes back or the account changes.
    /// Not under tests: asking CloudKit without the iCloud entitlement, as in
    /// an unsigned test build, crashes the test host.
    func watch() {
        guard !isWatching, !PlowRApp.isRunningUnderTests else { return }
        isWatching = true
        for name in [UIApplication.didBecomeActiveNotification, Notification.Name.CKAccountChanged] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.refresh() }
                }
            }
        }
        Task { await refresh() }
    }

    func refresh() async {
        guard databaseOpened() else {
            state = .localOnly
            return
        }
        do {
            state = Self.state(for: try await check())
        } catch {
            state = .couldNotDetermine
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

    /// What's wrong, for Settings. Nil when there's nothing to tell: synced,
    /// or not known (still asking, or no signal on a job site).
    var warning: Warning? { Self.warning(for: state) }

    /// The Dashboard banner: the warning, unless the user closed it.
    var banner: Warning? { state == dismissed ? nil : warning }

    func dismissBanner() {
        dismissed = state
        defaults.set(state.rawValue, forKey: Self.dismissedKey)
    }

    nonisolated static func warning(for state: State) -> Warning? {
        switch state {
        case .checking, .available, .couldNotDetermine:
            return nil
        case .noAccount:
            return Warning(title: "Not backed up to iCloud",
                           message: "This iPhone isn't signed in to iCloud, so your clients, routes and documents are only on this iPhone. To back them up and sync your devices, open the Settings app and sign in at the top.")
        case .restricted:
            return Warning(title: "Not backed up to iCloud",
                           message: "iCloud is restricted on this iPhone, by Screen Time or by whoever manages it, so your clients, routes and documents are only on this iPhone.")
        case .temporarilyUnavailable:
            return Warning(title: "iCloud needs attention",
                           message: "Your Apple Account needs attention before PlowR can sync. Open the Settings app and tap your name at the top. Until then, changes stay on this iPhone.")
        case .localOnly:
            return Warning(title: "Not syncing with iCloud",
                           message: "PlowR couldn't open its iCloud database, so your changes are saved on this iPhone only for now.")
        }
    }
}
