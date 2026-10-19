import Foundation

/// Runs a notification's work on the main actor without ever making the
/// poster wait for it.
///
/// An observer added with `queue: .main` makes a post from another thread
/// wait until the main thread has run it. CoreData posts its notices holding
/// its store, so a main thread reading that store and a notice waiting for
/// the main thread waited on each other: a deadlock that hung CI from
/// 2026-10-18 (#190's first run, #193), and could hang the app while iCloud
/// brings changes. Observe with `queue: nil` and pass the work here: posted
/// on the main thread (a save of the main context), it runs at once, as
/// before; from any other thread, it's queued for the main actor and the
/// poster carries on.
nonisolated enum MainActorNotice {
    static func run(_ work: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }
}
