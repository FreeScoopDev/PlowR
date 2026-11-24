import SwiftUI

/// Picking a client from a long list: one row per client (name, address),
/// searched by the Clients list's rule (`ClientSearch`), in the order
/// given. Used by a new document's Select Client and Add Visit's Client.
/// Picking one closes the list: pops it, or closes the sheet it's in.
struct ClientSearchList: View {
    let clients: [Client]
    /// The client already chosen, shown with a check.
    var selectedID: UUID?
    let onSelect: (Client) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        let shown = ClientSearch.filter(clients, query: searchText)
        List {
            Section {
                ForEach(shown) { client in
                    Button {
                        onSelect(client)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(client.name).font(.headline).foregroundStyle(.primary)
                                if !client.address.isEmpty {
                                    Text(client.address).font(.caption).foregroundStyle(PlowRColor.inkSecondary)
                                }
                            }
                            .padding(.vertical, 2)
                            Spacer()
                            if client.id == selectedID {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(PlowRColor.accent)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(client.id == selectedID ? .isSelected : [])
                }
            }
            .listRowBackground(PlowRColor.surface)
        }
        .plowRGrouped()
        .overlay {
            if shown.isEmpty && !clients.isEmpty {
                NoSearchMatches(query: searchText)
            }
        }
        .searchable(text: $searchText, prompt: "Search Clients")
    }
}

/// What a searched list shows when the search finds nothing.
struct NoSearchMatches: View {
    let query: String

    var body: some View {
        ContentUnavailableView(
            "No Matches",
            systemImage: "magnifyingglass",
            description: Text("Nothing matches \u{201C}\(ClientSearch.query(query))\u{201D}. Check the spelling, or try fewer words.")
        )
    }
}
