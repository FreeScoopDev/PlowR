import SwiftUI
import Contacts
import ContactsUI

// CNContactPickerViewController requires no permission prompt — the system picker
// shows a read-only UI, and only the user-selected contact is returned to the app.
struct ContactPickerView: UIViewControllerRepresentable {
    let onPick: (_ name: String, _ phone: String, _ address: String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ vc: CNContactPickerViewController, context: Context) {}

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (String, String, String) -> Void

        init(onPick: @escaping (String, String, String) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
            var address = ""
            if let postal = contact.postalAddresses.first?.value {
                let parts = [postal.street, postal.city, postal.state, postal.postalCode]
                    .filter { !$0.isEmpty }
                address = parts.joined(separator: ", ")
            }
            onPick(name, phone, address)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}
    }
}
