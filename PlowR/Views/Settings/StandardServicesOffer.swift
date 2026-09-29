import SwiftData
import SwiftUI

/// Where a screen would list services and the catalog has none to list: the
/// standard ones, a tap away (ServiceCatalog). Without it a new business met
/// an empty list with nowhere to go, since the standard services are no
/// longer added by themselves.
struct StandardServicesOffer: View {
    let operatorID: String

    @Environment(\.modelContext) private var modelContext
    @Query private var allServices: [ServiceItem]

    var body: some View {
        switch ServiceCatalog.coverage(of: allServices, operatorID: operatorID) {
        case .none:
            Text("Your service catalog is empty. Add the standard services for your work, or your own in Settings → Service Catalog.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ForEach(ServiceCatalog.standardCategories) { category in
                Button {
                    ServiceCatalog.addStandard(category, operatorID: operatorID, existing: allServices,
                                               to: modelContext)
                } label: {
                    Label(category.label, systemImage: "plus.circle")
                }
            }
        case .allOff:
            Text("All your services are turned off. Turn them on in Settings → Service Catalog.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case .some:
            EmptyView()
        }
    }
}
