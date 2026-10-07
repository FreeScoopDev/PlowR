import SwiftUI

/// The mark on a client or property whose address the map couldn't find
/// (`needsAddressFix`): in the client list, on the client's page and the
/// property's. One look and one wording for all of them.
struct AddressNotFoundLabel: View {
    /// The longer explanation, for a page; nil is the short mark for a row.
    var detail: String?

    static let symbol = "mappin.slash"
    static let color = Color.orange
    static let short = "Address not found on the map"

    var body: some View {
        Label(detail ?? Self.short, systemImage: Self.symbol)
            .foregroundStyle(Self.color)
    }
}
