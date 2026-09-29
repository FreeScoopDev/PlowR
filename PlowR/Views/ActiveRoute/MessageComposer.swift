import SwiftUI
import MessageUI

/// What became of a text the user was shown in Messages' composer.
enum MessageOutcome: Equatable {
    case sent, cancelled, failed

    init(_ result: MessageComposeResult) {
        switch result {
        case .sent: self = .sent
        case .failed: self = .failed
        default: self = .cancelled
        }
    }
}

struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    /// Called once the composer has closed, with whether the text went.
    /// Cancel and a failed send used to be reported just like a sent text.
    let onFinish: (MessageOutcome) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let controller = MFMessageComposeViewController()
        controller.recipients = recipients
        controller.body = body
        controller.messageComposeDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: (MessageOutcome) -> Void

        init(onFinish: @escaping (MessageOutcome) -> Void) {
            self.onFinish = onFinish
        }

        func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            let outcome = MessageOutcome(result)
            controller.dismiss(animated: true) {
                self.onFinish(outcome)
            }
        }
    }
}
