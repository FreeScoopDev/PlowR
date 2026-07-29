import SwiftUI
import SwiftData

struct ServiceCatalogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Query private var allServices: [ServiceItem]

    @State private var showingAddService = false
    @State private var serviceToEdit: ServiceItem?

    private var myServices: [ServiceItem] {
        allServices
            .filter { $0.operatorID == authManager.userID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var grouped: [(category: String, label: String, items: [ServiceItem])] {
        let categories: [(String, String)] = [
            ("snow", "Snow Removal"),
            ("lawn", "Lawn Care"),
            ("cleanup", "Cleanup"),
            ("custom", "Custom Services"),
        ]
        return categories.compactMap { (key, label) in
            let items = myServices.filter { $0.category == key }
            return items.isEmpty ? nil : (key, label, items)
        }
    }

    var body: some View {
        List {
            ForEach(grouped, id: \.category) { group in
                Section(group.label) {
                    ForEach(group.items) { item in
                        ServiceRowView(item: item) {
                            serviceToEdit = item
                        }
                    }
                }
            }

            Section {
                Button {
                    showingAddService = true
                } label: {
                    Label("Add Custom Service", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Service Catalog")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { seedIfNeeded() }
        .sheet(isPresented: $showingAddService) {
            ServiceItemEditView(operatorID: authManager.userID)
        }
        .sheet(item: $serviceToEdit) { item in
            ServiceItemEditView(item: item, operatorID: authManager.userID)
        }
    }

    private func seedIfNeeded() {
        guard myServices.isEmpty else { return }
        for (index, def) in ServiceItem.defaultServices.enumerated() {
            let item = ServiceItem(
                name: def.name,
                category: def.category,
                unitType: def.unitType,
                pricePerUnit: def.price,
                isBuiltIn: true,
                operatorID: authManager.userID,
                sortOrder: index
            )
            modelContext.insert(item)
        }
    }
}

struct ServiceRowView: View {
    let item: ServiceItem
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.headline)
                Text(item.unitType == "flat"
                     ? String(format: "$%.2f flat", item.pricePerUnit)
                     : String(format: "$%.3f / sq ft", item.pricePerUnit))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { item.isActive },
                set: { item.isActive = $0 }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }
}

struct ServiceItemEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var item: ServiceItem?
    let operatorID: String

    @State private var name = ""
    @State private var unitType = "flat"
    @State private var price = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Service Name") {
                    TextField("e.g. Patio Clearing", text: $name)
                }
                Section("Pricing") {
                    Picker("Unit Type", selection: $unitType) {
                        Text("Flat Rate").tag("flat")
                        Text("Per Sq Ft").tag("perSqFt")
                    }
                    HStack {
                        Text("$")
                        TextField(unitType == "flat" ? "0.00" : "0.000", text: $price)
                            .keyboardType(.decimalPad)
                        if unitType == "perSqFt" {
                            Text("/ sq ft")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "New Service" : "Edit Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.isEmpty || price.isEmpty)
                }
            }
            .onAppear {
                if let item {
                    name = item.name
                    unitType = item.unitType
                    price = String(item.pricePerUnit)
                }
            }
        }
    }

    private func save() {
        let priceValue = Double(price) ?? 0
        if let item {
            item.name = name
            item.unitType = unitType
            item.pricePerUnit = priceValue
        } else {
            let new = ServiceItem(
                name: name,
                category: "custom",
                unitType: unitType,
                pricePerUnit: priceValue,
                operatorID: operatorID,
                sortOrder: 999
            )
            modelContext.insert(new)
        }
        dismiss()
    }
}
