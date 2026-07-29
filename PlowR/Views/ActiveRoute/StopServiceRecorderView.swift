import SwiftUI
import SwiftData

struct StopServiceRecorderView: View {
    let stop: RouteStop
    let client: Client?
    let operatorID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allServices: [ServiceItem]
    @Query private var allProposals: [Proposal]

    @State private var selectedServiceIDs: Set<String>
    @State private var notes: String

    init(stop: RouteStop, client: Client?, operatorID: String) {
        self.stop = stop
        self.client = client
        self.operatorID = operatorID
        _selectedServiceIDs = State(initialValue: Set(stop.completedServiceIDs))
        _notes = State(initialValue: stop.completedNotes)
    }

    private var myServices: [ServiceItem] {
        allServices
            .filter { $0.operatorID == operatorID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let client {
                    Section {
                        LabeledContent("Client", value: client.name)
                        if !client.address.isEmpty {
                            LabeledContent("Address", value: client.address)
                        }
                    }
                }

                Section("Services Performed") {
                    if myServices.isEmpty {
                        Text("No services in your catalog. Add services in Settings → Service Catalog.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(myServices) { service in
                            Toggle(isOn: Binding(
                                get: { selectedServiceIDs.contains(service.id.uuidString) },
                                set: { on in
                                    if on { selectedServiceIDs.insert(service.id.uuidString) }
                                    else  { selectedServiceIDs.remove(service.id.uuidString) }
                                }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(service.name)
                                    Text(service.unitType == "flat"
                                         ? String(format: "$%.2f flat", service.pricePerUnit)
                                         : String(format: "$%.3f/sq ft", service.pricePerUnit))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Optional notes for this stop…", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle("Record Services")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save & Draft Invoice") { saveDraftInvoice() }
                        .disabled(selectedServiceIDs.isEmpty || client == nil)
                }
            }
        }
    }

    private func saveDraftInvoice() {
        stop.completedServiceIDs = Array(selectedServiceIDs)
        stop.completedNotes = notes

        guard let client else { dismiss(); return }

        let existingCount = allProposals.filter {
            !$0.invoiceNumber.isEmpty && $0.operatorID == operatorID
        }.count

        let proposal = Proposal(operatorID: operatorID, client: client)
        proposal.invoiceNumber = String(format: "INV-%04d", existingCount + 1)
        proposal.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
        if !notes.isEmpty { proposal.notes = notes }

        var lineItems: [ProposalLineItem] = []
        var sortIndex = 0
        let zones = client.sortedZones

        for service in myServices where selectedServiceIDs.contains(service.id.uuidString) {
            if !zones.isEmpty && service.unitType == "perSqFt" {
                for zone in zones {
                    let item = ProposalLineItem(
                        serviceName: service.name,
                        zoneLabel: zone.label,
                        quantity: zone.areaSquareFeet,
                        unitType: service.unitType,
                        unitPrice: service.pricePerUnit,
                        sortOrder: sortIndex
                    )
                    lineItems.append(item)
                    sortIndex += 1
                }
            } else {
                let item = ProposalLineItem(
                    serviceName: service.name,
                    zoneLabel: zones.isEmpty ? "Property" : "All Zones",
                    quantity: 1,
                    unitType: "flat",
                    unitPrice: service.pricePerUnit,
                    sortOrder: sortIndex
                )
                lineItems.append(item)
                sortIndex += 1
            }
        }

        lineItems.forEach { modelContext.insert($0) }
        proposal.lineItems = lineItems
        modelContext.insert(proposal)
        dismiss()
    }
}
