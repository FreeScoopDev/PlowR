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
                    .onDelete { offsets in
                        offsets.map { group.items[$0] }.forEach { modelContext.delete($0) }
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
        let existingNames = Set(myServices.map { $0.name })
        let toSeed = ServiceItem.defaultServices.enumerated().filter { !existingNames.contains($0.element.name) }
        guard !toSeed.isEmpty else { return }
        for (index, def) in toSeed {
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
                Text(priceLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: Binding(
                get: { item.isActive },
                set: { v in
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    item.isActive = v
                }
            ))
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
    }

    private var priceLabel: String {
        switch item.unitType {
        case "flat":    return String(format: "$%.2f flat", item.pricePerUnit)
        case "perSqFt": return String(format: "$%.3f / sq ft", item.pricePerUnit)
        default:
            let label = item.unitLabel.isEmpty ? "unit" : item.unitLabel
            return String(format: "$%.2f / %@", item.pricePerUnit, label)
        }
    }
}

struct ServiceItemEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var item: ServiceItem?
    let operatorID: String

    @State private var name = ""
    @State private var unitType = "flat"
    @State private var unitLabel = ""
    @State private var price = ""

    private var pricePlaceholder: String {
        switch unitType {
        case "perSqFt": return "0.000"
        default:        return "0.00"
        }
    }

    private var priceSuffix: String {
        switch unitType {
        case "perSqFt": return "/ sq ft"
        case "perUnit":
            let lbl = unitLabel.trimmingCharacters(in: .whitespaces)
            return lbl.isEmpty ? "/ unit" : "/ \(lbl)"
        default: return ""
        }
    }

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
                        Text("Per Unit").tag("perUnit")
                    }
                    if unitType == "perUnit" {
                        TextField("Unit label (e.g. bag, hr, ton)", text: $unitLabel)
                    }
                    HStack {
                        Text("$")
                        TextField(pricePlaceholder, text: $price)
                            .keyboardType(.decimalPad)
                        if !priceSuffix.isEmpty {
                            Text(priceSuffix).foregroundStyle(.secondary)
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
                    name      = item.name
                    unitType  = item.unitType
                    unitLabel = item.unitLabel
                    price     = String(item.pricePerUnit)
                }
            }
        }
    }

    private func save() {
        let priceValue = Double(price) ?? 0
        if let item {
            item.name      = name
            item.unitType  = unitType
            item.unitLabel = unitType == "perUnit" ? unitLabel.trimmingCharacters(in: .whitespaces) : ""
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
            new.unitLabel = unitType == "perUnit" ? unitLabel.trimmingCharacters(in: .whitespaces) : ""
            modelContext.insert(new)
        }
        dismiss()
    }
}
