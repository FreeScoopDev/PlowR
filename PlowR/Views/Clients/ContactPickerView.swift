import SwiftUI
import Contacts
import ContactsUI

// CNContactPickerViewController must be presented modally (not embedded as a child VC).
// Using updateUIViewController guarantees the container is in the hierarchy before we present.
struct ContactPickerView: UIViewControllerRepresentable {
    let onPick: (_ name: String, _ phone: String, _ email: String, _ address: String) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> UIViewController {
        let container = UIViewController()
        container.view.backgroundColor = .clear
        return container
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // Only present once; guard prevents re-presenting while picker is open
        guard uiViewController.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        uiViewController.present(picker, animated: true)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (String, String, String, String) -> Void
        let onCancel: () -> Void

        init(onPick: @escaping (String, String, String, String) -> Void,
             onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name  = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            let email = contact.emailAddresses.first?.value as String? ?? ""
            var address = ""
            if let postal = contact.postalAddresses.first?.value {
                address = [postal.street, postal.city, postal.state, postal.postalCode]
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
            }
            DispatchQueue.main.async { self.onPick(name, phone, email, address) }
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            DispatchQueue.main.async { self.onCancel() }
        }
    }
}
