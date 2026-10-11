import CloudKit
import CoreData
import SwiftUI

/// Watches, from launch, for the database's first import from iCloud to
/// finish. The import starts when the store opens (PlowRApp), usually
/// before the role and sign-in screens are done: a watch started at
/// sign-in missed it and waited out its whole time limit.
@MainActor @Observable
final class CloudImportWatch {
    static let shared = CloudImportWatch()

    /// An import from iCloud has finished since launch.
    private(set) var importEnded = false
    let launchedAt = Date()
    private var observer: NSObjectProtocol?

    func start(center: NotificationCenter = .default) {
        guard observer == nil else { return }
        observer = center.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
                                      object: nil, queue: .main) { note in
            let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            let ended = event?.type == .import && event?.endDate != nil
            MainActor.assumeIsolated { self.record(importEnded: ended) }
        }
    }

    func record(importEnded ended: Bool) {
        if ended { importEnded = true }
    }
}

/// Before first-run setup, the business's records may still be on their way
/// from iCloud: a new phone signed in to an account already used with
/// PlowR. Setup shown then made a second business profile beside the real
/// one (BusinessProfiles). So with iCloud available and sync on, setup waits
/// for the first import (CloudImportWatch), at most `limit` from launch;
/// with no account, or sync off on this device, it doesn't wait.
@MainActor @Observable
final class CloudImportWait {
    static let limit: TimeInterval = 25
    private(set) var isDone = false
    private let watch: CloudImportWatch

    /// `watch` defaults to the app's (a default argument can't name the
    /// main-actor `shared` without a Swift 6 warning).
    init(watch: CloudImportWatch? = nil) {
        self.watch = watch ?? .shared
    }

    /// Setup can show: the import finished, or waiting is over.
    var isReady: Bool { isDone || watch.importEnded }

    /// Run from the waiting screen's task (cancelled when it goes away).
    func start(syncOff: Bool, underTests: Bool = PlowRApp.isRunningUnderTests,
               accountAvailable: () async -> Bool = { (try? await ICloudStatus.accountStatus()) == .available },
               now: () -> Date = Date.init) async {
        if syncOff || underTests { return finish() }
        guard await accountAvailable() else { return finish() }
        guard !Task.isCancelled else { return }
        let left = Self.limit - now().timeIntervalSince(watch.launchedAt)
        if left > 0 { try? await Task.sleep(for: .seconds(left)) }
        guard !Task.isCancelled else { return }
        finish()
    }

    /// Done waiting: the time ran out, there's nothing to wait for, or the
    /// user chose to set up a new business.
    func finish() { isDone = true }

    /// Another business signed in: wait afresh.
    func reset() { isDone = false }
}

/// While CloudImportWait waits: what's happening, and a way past it.
struct LookingForBusinessView: View {
    let setUpNew: () -> Void

    var body: some View {
        VStack(spacing: PlowRLayout.space4) {
            Spacer()
            BrandMark(size: 72)
            ProgressView()
                .padding(.top, PlowRLayout.space4)
            Text("Looking for your business in iCloud…")
                .font(.headline)
                .foregroundStyle(PlowRColor.ink)
            Text("If you've used PlowR on another device, your clients, routes and documents will appear here.")
                .font(.subheadline)
                .foregroundStyle(PlowRColor.inkSecondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Set Up a New Business", action: setUpNew)
                .buttonStyle(.plowRSecondary)
        }
        .padding(PlowRLayout.space6)
        .frame(maxWidth: .infinity)
        .background(PlowRColor.ground.ignoresSafeArea())
    }
}
