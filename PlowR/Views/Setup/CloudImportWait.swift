import CloudKit
import CoreData
import SwiftUI

/// Before first-run setup, the business's records may still be on their way
/// from iCloud: a new phone signed in to an account already used with
/// PlowR. Setup shown then made a second business profile beside the real
/// one (BusinessProfiles). So with iCloud available and sync on, setup waits
/// for the database's first import from iCloud to finish, at most `limit`;
/// with no account, or sync off on this device, it doesn't wait.
@MainActor @Observable
final class CloudImportWait {
    private(set) var isDone = false
    private var observer: NSObjectProtocol?
    private var timeout: Task<Void, Never>?
    static let limit: Duration = .seconds(25)

    func start(syncOff: Bool) async {
        guard !isDone, observer == nil else { return }
        if syncOff || PlowRApp.isRunningUnderTests { return finish() }
        guard (try? await ICloudStatus.accountStatus()) == .available else { return finish() }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { note in
            let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            guard event?.type == .import, event?.endDate != nil else { return }
            MainActor.assumeIsolated { self.finish() }
        }
        timeout = Task { [weak self] in
            try? await Task.sleep(for: Self.limit)
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    /// Done waiting: the import finished, the time ran out, or the user
    /// chose to set up a new business.
    func finish() {
        isDone = true
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        timeout?.cancel()
    }
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
