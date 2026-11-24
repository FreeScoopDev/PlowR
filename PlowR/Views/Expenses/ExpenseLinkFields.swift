import SwiftUI

/// An expense's or a trip's optional client and route, as ID and a copy of
/// the name. A client or route since deleted keeps showing by its name.
struct ExpenseLinkFields: View {
    let clients: [Client]
    let routes: [PlowRoute]
    @Binding var clientID: String
    @Binding var clientName: String
    @Binding var routeID: String
    @Binding var routeName: String

    var body: some View {
        // A searchable list, as Add Visit's: a long client list can't be
        // scrolled through to find one.
        NavigationLink {
            ClientSearchList(clients: clients, selectedID: UUID(uuidString: clientID)) { client in
                clientID = client.id.uuidString
                clientName = client.name
            }
            .navigationTitle("Client")
            .navigationBarTitleDisplayMode(.inline)
        } label: {
            LabeledContent("Client") {
                Text(clientID.isEmpty ? "None" : clientName)
            }
        }
        if !clientID.isEmpty {
            Button("Remove Client", role: .destructive) {
                clientID = ""
                clientName = ""
            }
        }
        Picker("Route", selection: Binding(
            get: { routeID },
            set: { id in
                routeID = id
                routeName = routes.first { $0.id.uuidString == id }?.name ?? (id.isEmpty ? "" : routeName)
            })) {
            Text("None").tag("")
            ForEach(routes) { route in
                Text(route.name).tag(route.id.uuidString)
            }
            // Deleted since, or not on this device yet: shown by its name.
            if !routeID.isEmpty, !routes.contains(where: { $0.id.uuidString == routeID }) {
                Text(routeName.isEmpty ? "Route" : routeName).tag(routeID)
            }
        }
    }
}
