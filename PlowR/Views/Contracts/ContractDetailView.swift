import SwiftData
import SwiftUI

/// One contract: where it stands, what it covers and how it's priced, and
/// signing, changing, cancelling or deleting it.
struct ContractDetailView: View {
    @Bindable var contract: Contract

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allServiceItems: [ServiceItem]
    @State private var showingEdit = false
    @State private var confirmingCancel = false
    @State private var confirmingDelete = false
    @State private var confirmingSign = false

    private var status: Contracts.Status { Contracts.status(of: contract) }

    var body: some View {
        if contract.isDeleted || contract.modelContext == nil {
            Color.clear.onAppear { dismiss() }
        } else {
            list
        }
    }

    private var list: some View {
        List {
            Section {
                LabeledContent("Status") { StatusChip(status.title, color: status.chipColor) }
                if contract.client == nil {
                    LabeledContent("Client", value: contract.clientName)
                }
                LabeledContent("Period", value: period)
                LabeledContent("Price", value: Contracts.priceSummary(of: contract))
                if let signed = contract.signedAt {
                    LabeledContent("Signed", value: signed.formatted(.dateTime.month(.abbreviated).day().year()))
                }
                if let cancelled = contract.cancelledAt {
                    LabeledContent("Cancelled", value: cancelled.formatted(.dateTime.month(.abbreviated).day().year()))
                }
            }
            Section("Applies To") {
                ForEach(places, id: \.id) { place in
                    LabeledContent(place.isMain ? "Main Address" : place.label, value: place.address)
                }
            }
            Section("Services Covered") {
                if serviceNames.isEmpty {
                    Text("None chosen").foregroundStyle(.secondary)
                }
                ForEach(serviceNames, id: \.self) { Text($0) }
            }
            if contract.triggerInches > 0 {
                Section { ContractTriggerRow(inches: contract.triggerInches) }
            }
            if !contract.notes.isEmpty {
                Section("Notes") { Text(contract.notes) }
            }
            actions
        }
        .navigationTitle(contract.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if status != .cancelled, status != .ended, contract.client != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEdit = true }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let client = contract.client { ContractEditView(client: client, contract: contract) }
        }
        .confirmationDialog("Cancel this contract?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel Contract", role: .destructive) { Contracts.cancel(contract, in: modelContext) }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("It ends today. Work already done and anything already billed stay as they are.")
        }
        .confirmationDialog("Mark it signed?", isPresented: $confirmingSign, titleVisibility: .visible) {
            Button("Mark Signed") { Contracts.sign(contract, in: modelContext) }
            Button("Not Yet", role: .cancel) {}
        } message: {
            Text("From then what was agreed (where, what, the price) is locked, and it can be cancelled but not deleted.")
        }
        .confirmationDialog("Delete this draft?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Draft", role: .destructive) {
                Contracts.deleteDraft(contract, in: modelContext)
                dismiss()
            }
            Button("Keep It", role: .cancel) {}
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .draft:
            Section {
                Button("Mark Signed") { confirmingSign = true }
                Button("Delete Draft", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Mark it signed once the client has agreed. From then it counts: they're a customer, what was agreed is locked, and it can be cancelled but not deleted.")
            }
        case .upcoming, .active:
            Section {
                Button("Cancel Contract", role: .destructive) { confirmingCancel = true }
            }
        case .ended, .cancelled:
            EmptyView()
        }
    }

    private var period: String {
        let format = Date.FormatStyle.dateTime.month(.abbreviated).day().year()
        return "\(contract.startDate.formatted(format)) – \(contract.endDate.formatted(format))"
    }

    private var places: [Place] {
        guard let client = contract.client else { return [] }
        return contract.placeIDs.compactMap { Place.of(client, propertyID: $0) }
    }

    private var serviceNames: [String] {
        allServiceItems.filter { contract.serviceIDs.contains($0.id.uuidString) }
            .sorted { $0.sortOrder < $1.sortOrder }.map(\.name)
    }
}

/// A contract in a client's list: its name, where it stands, its price.
struct ContractRow: View {
    let contract: Contract

    var body: some View {
        let status = Contracts.status(of: contract)
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(contract.name)
                Text(Contracts.priceSummary(of: contract)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            StatusChip(status.title, color: status.chipColor)
        }
    }
}
