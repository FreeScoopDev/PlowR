import SwiftData
import SwiftUI
import UIKit

/// Where an Add to PlowR request (IncomingLinks) opens: a sheet in a window
/// of its own, above the app. So it opens over whatever is on screen (the
/// route screen, a half-written proposal) without closing it: a sheet
/// presented from the app's own views would close any sheet already open,
/// and its unsaved work with it (seen in the simulator). Closing it, by
/// Cancel, Save Lead, OK or a swipe, takes the window away and clears the
/// link.
@MainActor
@Observable
final class LeadRequestWindow: NSObject, UIAdaptivePresentationControllerDelegate {
    static let shared = LeadRequestWindow()

    @ObservationIgnored private var window: UIWindow?
    /// The link this window opened: closing clears only that one, so a
    /// second request that came in meanwhile opens next.
    @ObservationIgnored private var opened: URL?
    @ObservationIgnored private var closing = false
    /// Observed: when it closes, a request waiting behind it opens.
    private(set) var isShowing = false

    /// Shows what `route` needs: the New Lead screen, or why a link can't
    /// be read. Nothing if something's already showing.
    func show(_ route: IncomingLinks.Route, container: ModelContainer, authManager: AuthManager) {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first
        else { return }
        let close: () -> Void = { [weak self] in self?.close() }
        let content: AnyView
        switch route {
        case let .request(request):
            content = AnyView(NewLeadFromRequestView(request: request, onClose: close))
        case .damaged:
            content = AnyView(DamagedRequestView(onClose: close))
        default:
            return
        }
        let host = UIHostingController(rootView: content
            .environment(authManager)
            .environment(ActiveRouteStore.shared)
            .environment(CalendarSync.shared)
            .modelContainer(container)
            .tint(PlowRColor.accent))
        host.presentationController?.delegate = self

        opened = IncomingLinks.shared.pending
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .normal + 1
        window.backgroundColor = .clear
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        self.window = window
        isShowing = true
        window.rootViewController?.present(host, animated: true)
    }

    /// The window goes, and the link with it.
    func close() {
        guard let window, !closing else { return }
        // A second tap while the sheet slides away mustn't finish twice: the
        // first finish may already have opened the next request.
        closing = true
        let opened = self.opened
        let finish = { [weak self] in
            window.isHidden = true
            // The app's own window takes the keyboard and taps back.
            window.windowScene?.windows.first { $0 !== window && $0.windowLevel == .normal }?.makeKey()
            if IncomingLinks.shared.pending == opened { IncomingLinks.shared.pending = nil }
            guard let self, self.window === window else { return }
            self.opened = nil
            self.window = nil
            self.closing = false
            self.isShowing = false
        }
        if let presented = window.rootViewController?.presentedViewController {
            presented.dismiss(animated: true, completion: finish)
        } else {
            finish()
        }
    }

    /// Swiped down.
    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Task { @MainActor in self.close() }
    }
}

/// A link that was cut short or changed.
private struct DamagedRequestView: View {
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("This Request Can't Be Read", systemImage: "exclamationmark.triangle")
            } description: {
                Text("The link may have been cut short or changed. The request itself is in the text it came with: add them as a client from there.")
            } actions: {
                Button("OK", action: onClose).buttonStyle(.borderedProminent)
            }
        }
    }
}
