import SwiftUI
import SwiftData

struct ProposalBuilderView: View {
    let client: Client
    var isInvoiceMode: Bool = false
    var linkedVisitID: String = ""        // set when opened from a ScheduledVisit
    var afterHoursMultiplier: Double = 1.0
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager
    @Query private var allServices: [ServiceItem]
    @Query private var allProfiles: [BusinessProfile]
    @Query private var allPaymentMethods: [PaymentMethod]

    // Per-service, per-zone selection: key = "serviceID|zoneIndex"
    @State private var selections: Set<String> = []
    @State private var amounts:    [String: String] = [:]
    @State private var lineNotes:  [String: String] = [:]
    @State private var notes = ""
    @State private var discountAmount = ""
    @State private var taxRateString = ""
    @State private var disclaimer = ""
    @State private var customItems: [CustomLineItem] = []
    @State private var validUntilEnabled = false
    @State private var validUntil = Date().addingTimeInterval(14 * 86400)
    @State private var invoiceDueDate = Date().addingTimeInterval(30 * 86400)
    @State private var showingPreview = false
    @State private var generatedPDFData: Data?
    @State private var pendingProposal: Proposal?
    /// The document the preview shared before it was saved, and the number
    /// on it: saved as shared (a draft invoice, as sent) if it's still that
    /// document with that number (DocumentSent.wasSharedBeforeSave).
    @State private var sharedProposalID: UUID?
    @State private var sharedNumber = ""
    @State private var grouped = false

    private struct CustomLineItem: Identifiable {
        let id = UUID()
        var name: String = ""
        var amount: String = ""
        var notes: String = ""
    }

    // MARK: - Computed Properties

    private var myServices: [ServiceItem] {
        var seen = Set<String>()
        return allServices
            .filter { $0.operatorID == authManager.userID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
            .filter { seen.insert($0.id.uuidString).inserted }
    }

    private var zones: [PropertyZone] { client.sortedZones }
    private var hasZones: Bool { !zones.isEmpty }

    private var profile: BusinessProfile? {
        allProfiles.first { $0.operatorID == authManager.userID }
    }

    private var activePaymentMethods: [PaymentMethod] {
        allPaymentMethods
            .filter { $0.operatorID == authManager.userID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var hasContent: Bool {
        !selections.isEmpty || customItems.contains { !$0.name.isEmpty }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                clientSection
                servicesSection
                customItemsSection
                optionsSection
            }
            .navigationTitle(isInvoiceMode ? "New Invoice" : "New Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button { buildAndPreview() } label: {
                            Label("Preview PDF", systemImage: "doc.richtext")
                        }
                        Button { buildAndSaveDraft() } label: {
                            Label("Save Draft", systemImage: "tray.and.arrow.down")
                        }
                    } label: {
                        Text(isInvoiceMode ? "Save Invoice" : "Save")
                            .fontWeight(.semibold)
                    }
                    .disabled(!hasContent)
                }
            }
            .sheet(isPresented: $showingPreview) {
                if let data = generatedPDFData {
                    ProposalPreviewView(pdfData: data, client: client, isInvoice: isInvoiceMode,
                                        onShared: {
                                            sharedProposalID = pendingProposal?.id
                                            sharedNumber = pendingProposal?.invoiceNumber ?? ""
                                        }) {
                        if let proposal = pendingProposal {
                            saveProposal(proposal)
                        }
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Sections

    private var clientSection: some View {
        Section("Client") {
            LabeledContent("Name", value: client.name)
            LabeledContent("Address", value: client.address)
            if zones.isEmpty {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("No property zones mapped — pricing will use flat rates only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if afterHoursMultiplier > 1.0 {
                HStack(spacing: 8) {
                    Image(systemName: "moon.fill").foregroundStyle(.orange)
                    Text("After hours — \(String(format: "%.2g", afterHoursMultiplier))× multiplier applied to service prices.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var servicesSection: some View {
        Section {
            if myServices.isEmpty {
                StandardServicesOffer(operatorID: authManager.userID)
            }
            ForEach(myServices) { service in
                if hasZones && service.unitType == "perSqFt" {
                    DisclosureGroup {
                        ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                            let key = selectionKey(service: service, zoneIndex: index)
                            let defaultAmt = draft.defaultAmount(serviceID: service.id.uuidString, zoneIndex: index) ?? 0
                            VStack(alignment: .leading, spacing: 0) {
                                Toggle(isOn: Binding(
                                    get: { selections.contains(key) },
                                    set: {
                                        if $0 {
                                            selections.insert(key)
                                            if amounts[key] == nil {
                                                amounts[key] = String(format: "%.2f", defaultAmt)
                                            }
                                        } else { selections.remove(key) }
                                    }
                                )) {
                                    HStack {
                                        Text(zone.label)
                                        Spacer()
                                        Text(String(format: "$%.2f", defaultAmt))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                if selections.contains(key) {
                                    itemEditFields(key: key, defaultAmount: defaultAmt)
                                }
                            }
                        }
                    } label: {
                        serviceRowLabel(service)
                    }
                } else {
                    let key = selectionKey(service: service, zoneIndex: -1)
                    let defaultAmt = draft.defaultAmount(serviceID: service.id.uuidString, zoneIndex: -1) ?? 0
                    VStack(alignment: .leading, spacing: 0) {
                        Toggle(isOn: Binding(
                            get: { selections.contains(key) },
                            set: {
                                if $0 {
                                    selections.insert(key)
                                    if amounts[key] == nil {
                                        amounts[key] = String(format: "%.2f", defaultAmt)
                                    }
                                } else { selections.remove(key) }
                            }
                        )) {
                            serviceRowLabel(service)
                        }
                        if selections.contains(key) {
                            itemEditFields(key: key, defaultAmount: defaultAmt)
                        }
                    }
                }
            }
        } header: {
            Text("Services")
        } footer: {
            if !selections.isEmpty {
                Text("Estimated total: \(estimatedTotalString)")
            }
        }
    }

    @ViewBuilder
    private func itemEditFields(key: String, defaultAmount: Double) -> some View {
        HStack(spacing: 6) {
            Text("$").foregroundStyle(.secondary)
            TextField("Amount", text: Binding(
                get: { amounts[key] ?? String(format: "%.2f", defaultAmount) },
                set: { amounts[key] = $0 }
            ))
            .keyboardType(.decimalPad)
        }
        .font(.subheadline)
        .padding(.leading, 8)
        .padding(.top, 6)

        TextField("Note for this line (optional)", text: Binding(
            get: { lineNotes[key] ?? "" },
            set: { lineNotes[key] = $0 }
        ))
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, 8)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var customItemsSection: some View {
        Section {
            ForEach($customItems) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Description", text: $item.name)
                        Spacer()
                        Text("$").foregroundStyle(.secondary)
                        TextField("0.00", text: $item.amount)
                            .keyboardType(.decimalPad)
                            .frame(width: 70)
                        Button {
                            customItems.removeAll { $0.id == item.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    TextField("Note for this line (optional)", text: $item.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                customItems.append(CustomLineItem())
            } label: {
                Label("Add Custom Line Item", systemImage: "plus.circle")
            }
        } header: {
            Text("Custom Line Items")
        }
    }

    private var optionsSection: some View {
        Group {
            Section("Options") {
                Toggle("Group line items by service", isOn: $grouped)
                if isInvoiceMode {
                    DatePicker("Due Date", selection: $invoiceDueDate, displayedComponents: .date)
                } else {
                    Toggle("Include validity date", isOn: $validUntilEnabled)
                    if validUntilEnabled {
                        DatePicker("Valid until", selection: $validUntil, displayedComponents: .date)
                    }
                }
            }
            Section("Discount & Tax") {
                HStack {
                    Text("Discount $")
                    TextField("0.00", text: $discountAmount)
                        .keyboardType(.decimalPad)
                }
                HStack {
                    Text("Tax")
                    TextField("0.0", text: $taxRateString)
                        .keyboardType(.decimalPad)
                    Text("%")
                }
            }
            Section("Disclaimer") {
                TextEditor(text: $disclaimer)
                    .frame(minHeight: 60)
                    .foregroundStyle(disclaimer.isEmpty ? .secondary : .primary)
                    .onAppear {
                        if disclaimer.isEmpty {
                            disclaimer = profile?.defaultDisclaimer ?? ""
                        }
                    }
            }
            Section("Notes") {
                TextEditor(text: $notes)
                    .frame(minHeight: 80)
            }
        }
    }

    // MARK: - Helpers

    private func serviceRowLabel(_ service: ServiceItem) -> some View {
        HStack {
            Text(service.name)
            Spacer()
            Text(service.unitType == "flat"
                 ? String(format: "$%.2f", service.pricePerUnit)
                 : String(format: "$%.3f/sqft", service.pricePerUnit))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func selectionKey(service: ServiceItem, zoneIndex: Int) -> String {
        "\(service.id.uuidString)|\(zoneIndex)"
    }

    private var estimatedTotalString: String {
        String(format: "$%.2f", calculateTotal())
    }

    /// Everything chosen on this screen, priced the one way both the estimate
    /// and the saved document use (see DocumentDraft).
    private var draft: DocumentDraft {
        DocumentDraft(
            services: myServices.map { .init(id: $0.id.uuidString, name: $0.name,
                                             unitType: $0.unitType, pricePerUnit: $0.pricePerUnit) },
            zones: zones.map { .init(label: $0.label, areaSquareFeet: $0.areaSquareFeet) },
            afterHoursMultiplier: afterHoursMultiplier,
            selections: selections,
            amounts: amounts,
            lineNotes: lineNotes,
            customLines: customItems.map { .init(name: $0.name, amount: $0.amount, notes: $0.notes) },
            discount: discountAmount,
            taxRate: taxRateString
        )
    }

    /// The estimate is the total of the document Save would make.
    private func calculateTotal() -> Double { draft.total }

    // MARK: - Build

    private func buildProposalObject() -> Proposal {
        let proposal = Proposal(operatorID: authManager.userID, client: client)
        proposal.notes = notes
        proposal.disclaimer = disclaimer
        if isInvoiceMode {
            proposal.invoiceNumber = InvoiceNumbering.next(operatorID: authManager.userID, in: modelContext)
            proposal.invoiceDueDate = invoiceDueDate
        } else if validUntilEnabled {
            proposal.validUntil = validUntil
        }

        // Priced by the same draft that gives the estimate, so the two agree.
        draft.apply(to: proposal, grouped: grouped)
        return proposal
    }

    private func buildAndPreview() {
        let proposal = buildProposalObject()
        pendingProposal = proposal
        generatedPDFData = PDFGenerator.generate(
            proposal: proposal,
            zones: zones,
            profile: profile,
            paymentMethods: activePaymentMethods,
            forceIsInvoice: isInvoiceMode
        )
        showingPreview = true
    }

    private func buildAndSaveDraft() {
        let proposal = buildProposalObject()
        saveProposal(proposal)
        dismiss()
    }

    private func saveProposal(_ proposal: Proposal) {
        proposal.visitID = linkedVisitID
        DocumentSent.saveBuilt(proposal, sharedID: sharedProposalID, sharedNumber: sharedNumber, in: modelContext)
        // Write proposal ID back to the originating scheduled visit
        if !linkedVisitID.isEmpty, let uuid = UUID(uuidString: linkedVisitID) {
            let descriptor = FetchDescriptor<ScheduledVisit>(predicate: #Predicate { $0.id == uuid })
            if let visit = try? modelContext.fetch(descriptor).first {
                visit.proposalID = proposal.id.uuidString
            }
        }
    }
}
