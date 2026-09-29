import SwiftUI

extension View {
    /// Asks what to do with an address that couldn't be put on the map
    /// (AddressPin): try again when the map couldn't be reached; keep the
    /// current pin, when there is one (`keepCurrentPin`), or save without a
    /// pin; or edit the address. Adding a client, the business-card scanner
    /// and Edit Client all ask this.
    func addressLookupAlert(_ problem: Binding<AddressPin.Problem?>,
                            saveWithoutPin: @escaping () -> Void,
                            tryAgain: @escaping () -> Void,
                            keepCurrentPin: (() -> Void)? = nil) -> some View {
        alert(problem.wrappedValue?.title ?? "",
              isPresented: Binding(get: { problem.wrappedValue != nil },
                                   set: { if !$0 { problem.wrappedValue = nil } }),
              presenting: problem.wrappedValue) { shown in
            ForEach(shown.choices(hasPin: keepCurrentPin != nil), id: \.self) { choice in
                switch choice {
                case .tryAgain: Button("Try Again") { tryAgain() }
                case .keepCurrentPin: Button("Keep Current Pin") { keepCurrentPin?() }
                case .saveWithoutPin: Button("Save Without Pin") { saveWithoutPin() }
                case .editAddress: Button("Edit Address", role: .cancel) {}
                }
            }
        } message: { shown in
            Text(shown.message(hasPin: keepCurrentPin != nil))
        }
    }
}
