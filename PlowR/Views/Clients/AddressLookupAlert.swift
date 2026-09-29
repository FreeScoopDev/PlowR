import SwiftUI

extension View {
    /// Asks what to do with an address that couldn't be put on the map
    /// (AddressPin): save the client without a pin, try again when the map
    /// couldn't be reached, or go back and check the address. Adding a
    /// client, the business-card scanner and Edit Client all ask this.
    func addressLookupAlert(_ problem: Binding<AddressPin.Problem?>,
                            saveWithoutPin: @escaping () -> Void,
                            tryAgain: @escaping () -> Void) -> some View {
        alert(problem.wrappedValue?.title ?? "",
              isPresented: Binding(get: { problem.wrappedValue != nil },
                                   set: { if !$0 { problem.wrappedValue = nil } }),
              presenting: problem.wrappedValue) { shown in
            if shown == .unreachable {
                Button("Try Again") { tryAgain() }
            }
            Button("Save Without Pin") { saveWithoutPin() }
            Button("Check Address", role: .cancel) {}
        } message: { shown in
            Text(shown.message)
        }
    }
}
