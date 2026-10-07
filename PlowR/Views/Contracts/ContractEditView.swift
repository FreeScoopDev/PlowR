import SwiftData
import SwiftUI

/// A new contract, or changes to one: where and when it applies, what it
/// covers and how it's priced (Contracts.Draft).
struct ContractEditView: View {
    let client: Client
    /// Nil: a new contract.
    let contract: Contract?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allServiceItems: [ServiceItem]
    @State private var draft: Contracts.Draft

    init(client: Client, contract: Contract?) {
        self.client = client
        self.contract = contract
        _draft = State(initialValue: contract.map { Contracts.Draft($0) } ?? Contracts.Draft(for: client))
    }

    /// A new contract starting from `draft`: made from a proposal, or a renewal.
    init(client: Client, draft: Contracts.Draft) {
        self.client = client
        self.contract = nil
        _draft = State(initialValue: draft)
    }

    private var services: [ServiceItem] {
        allServiceItems
            .filter { $0.operatorID == client.operatorID && ($0.isActive || draft.serviceIDs.contains($0.id.uuidString)) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// The client's places, and any the contract already names that's since
    /// been made inactive.
    private var places: [Place] {
        let bookable = Place.all(of: client)
        let kept = draft.placeIDs.compactMap { Place.of(client, propertyID: $0) }.filter { !bookable.contains($0) }
        return bookable + kept
    }

    private var coversSnow: Bool { Contracts.coversSnow(draft.serviceIDs, catalog: services) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(draft.resolvedName(), text: $draft.name)
                    if draft.isSigned {
                        LabeledContent("Starts", value: draft.startDate.formatted(date: .abbreviated, time: .omitted))
                    } else {
                        DatePicker("Starts", selection: $draft.startDate, displayedComponents: .date)
                    }
                    DatePicker("Ends", selection: $draft.endDate, in: draft.earliestEnd()..., displayedComponents: .date)
                } header: {
                    Text("Contract")
                } footer: {
                    Text(draft.isSigned
                         ? "Signed: what was agreed (where, what, the price) is locked. To change it, cancel it and make a new one."
                         : "Left blank, it's named for its dates.")
                }
                if draft.isSigned {
                    Section("Agreed") {
                        LabeledContent("Applies To", value: places.filter { draft.placeIDs.contains($0.id) }
                            .map { $0.isMain ? "Main Address" : $0.label }.joined(separator: ", "))
                        LabeledContent("Services", value: services.filter { draft.serviceIDs.contains($0.id.uuidString) }
                            .map(\.name).joined(separator: ", "))
                        if let contract { LabeledContent("Price", value: Contracts.priceSummary(of: contract)) }
                    }
                } else {
                    termsSections
                }
                scheduleSection
                if coversSnow { ContractTriggerSection(inches: $draft.triggerInches) }
                Section("Notes") {
                    TextField("Terms, what's included, anything agreed", text: $draft.notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle(contract == nil ? "New Contract" : "Edit Contract")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Contracts.save(draft, to: contract, of: client, in: modelContext)
                        dismiss()
                    }
                    .disabled(draft.problem() != nil)
                }
            }
        }
    }

    /// Where, what and how it's priced: set until it's signed.
    @ViewBuilder
    private var termsSections: some View {
                if places.count > 1 || draft.placeIDs.isEmpty {
                    Section("Applies To") {
                        ForEach(places, id: \.id) { place in
                            checkRow(place.isMain ? "Main Address" : place.label, detail: place.address,
                                     isOn: draft.placeIDs.contains(place.id)) {
                                toggle(place.id, in: &draft.placeIDs)
                            }
                        }
                    }
                }
                Section {
                    ForEach(services) { service in
                        checkRow(service.name, detail: nil, isOn: draft.serviceIDs.contains(service.id.uuidString)) {
                            toggle(service.id.uuidString, in: &draft.serviceIDs)
                        }
                    }
                } header: {
                    Text("Services Covered")
                } footer: {
                    Text("Services it doesn't cover are billed as extras, as usual.")
                }
                pricingSection
    }

    /// The visits it books: which days, how often. Changeable after signing.
    private var scheduleSection: some View {
        Section {
            Toggle("Book Visits", isOn: Binding(
                get: { !draft.scheduleWeekdays.isEmpty },
                set: { on in
                    let weekday = Calendar.current.component(.weekday, from: draft.startDate)
                    draft.scheduleWeekdays = on ? [weekday] : []
                }))
            if !draft.scheduleWeekdays.isEmpty {
                WeekdayPicker(selection: $draft.scheduleWeekdays)
                Stepper(value: $draft.scheduleIntervalWeeks, in: 1...8) {
                    LabeledContent("Every", value: draft.scheduleIntervalWeeks == 1 ? "Week" : "\(draft.scheduleIntervalWeeks) Weeks")
                }
            }
        } header: {
            Text("Visits")
        } footer: {
            Text(scheduleNote)
        }
    }

    private var scheduleNote: String {
        let booked = contract.map { !ContractSchedule.visitsAhead(of: $0, in: modelContext).isEmpty } ?? false
        if draft.scheduleWeekdays.isEmpty {
            return booked ? "Off: saving takes the visits it booked after today off the Schedule."
                          : "Off: no visits are booked by the contract (for work done when it's needed)."
        }
        return booked ? "Its booked visits keep their days until you Book Again on its page."
                      : "Once it's signed, Book Visits on its page puts them on the Schedule, at each place it applies to."
    }

    private var pricingSection: some View {
        Section {
            Picker("Pricing", selection: $draft.pricing) {
                ForEach(Contracts.Pricing.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            LabeledContent(draft.pricing.priceLabel) {
                TextField("0.00", text: $draft.priceText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
            }
            if draft.pricing == .season {
                Stepper(value: $draft.installments, in: 1...12) {
                    LabeledContent("Payments", value: draft.installments == 1 ? "All up front" : "\(draft.installments)")
                }
            }
        } header: {
            Text("Price")
        } footer: {
            Text(draft.problem() ?? pricingNote)
        }
    }

    private var pricingNote: String {
        switch draft.pricing {
        case .season: "One price for the whole period. Work it covers isn't billed by the visit."
        case .perVisit: "Each visit is billed at this price instead of the catalog's."
        case .monthly: "A set amount each month. Work it covers isn't billed by the visit."
        }
    }

    private func checkRow(_ title: String, detail: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func toggle(_ id: String, in set: inout Set<String>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
}
