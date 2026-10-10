import SwiftData
import SwiftUI

/// One contract: where it stands, what it covers and how it's priced, and
/// signing, changing, cancelling or deleting it.
struct ContractDetailView: View {
    @Bindable var contract: Contract

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.access) private var access
    @State private var gate: ProGate?
    @Query private var allServiceItems: [ServiceItem]
    @Query private var allContracts: [Contract]
    @Query private var allProfiles: [BusinessProfile]
    /// The contract's PDF, written when the page opens, to share.
    @State private var pdfURL: URL?
    @State private var choosingRenewal = false
    @State private var renewalDraft: Contracts.Draft?
    @State private var showingEdit = false
    @State private var confirmingCancel = false
    @State private var confirmingDelete = false
    @State private var confirmingSign = false
    @State private var confirmingBook = false

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
            visitsSection
            paymentsSection
            if contract.signedAt != nil,
               contract.triggerInches > 0 || Contracts.coversSnow(Set(contract.serviceIDs), catalog: allServiceItems) {
                ContractTriggerChecksSection(contract: contract)
            } else if contract.triggerInches > 0 {
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
            if let pdfURL {
                ToolbarItem(placement: .primaryAction) {
                    // Read only: a contract isn't shared until they subscribe again.
                    if let blocked = ProGate.shareDocument(access, isInvoice: false, owed: 0) {
                        Button { gate = blocked } label: { Image(systemName: "square.and.arrow.up") }
                    } else {
                        ShareLink(item: pdfURL) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
            if status != .cancelled, status != .ended, contract.client != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { showingEdit = true }
                }
            }
        }
        .proGateSheet($gate)
        .task(id: contract.persistentModelID) { writePDF() }
        .onChange(of: access.showsMadeWithPlowR) { writePDF() }
        .onChange(of: showingEdit) { _, open in if !open { writePDF() } }
        // Changed here or on another device: the file shared is the page as it is.
        .onChange(of: [contract.name, contract.notes]) { writePDF() }
        .onChange(of: contract.endDate) { writePDF() }
        .onChange(of: contract.signedAt) { writePDF() }
        .onChange(of: allProfiles.count) { writePDF() }
        .confirmationDialog("Renew for next season?", isPresented: $choosingRenewal, titleVisibility: .visible) {
            ForEach([0.0, 3, 5, 10], id: \.self) { percent in
                Button(percent == 0 ? "Same Price" : "Raise \(Int(percent))%") { renew(raising: percent) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A new draft for the same months next season, with the same terms. Check it and mark it signed when the client agrees.")
        }
        .sheet(isPresented: Binding(get: { renewalDraft != nil }, set: { if !$0 { renewalDraft = nil } })) {
            if let client = contract.client, let draft = renewalDraft {
                ContractEditView(client: client, draft: draft)
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let client = contract.client { ContractEditView(client: client, contract: contract) }
        }
        .confirmationDialog("Cancel this contract?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel Contract", role: .destructive) { Contracts.cancel(contract, in: modelContext) }
            Button("Keep It", role: .cancel) {}
        } message: {
            Text("It ends today. Work already done and anything already billed stay as they are, and the visits it booked after today come off the Schedule.")
        }
        .confirmationDialog("Book its visits?", isPresented: $confirmingBook, titleVisibility: .visible) {
            Button("Book Visits") { ContractSchedule.book(contract, in: modelContext) }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text(bookMessage)
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
                Button("Mark Signed") { $gate.unless(ProGate.edit(access)) { confirmingSign = true } }
                Button("Delete Draft", role: .destructive) { confirmingDelete = true }
            } footer: {
                Text("Mark it signed once the client has agreed. From then it counts: they're a customer, what was agreed is locked, and it can be cancelled but not deleted.")
            }
        case .upcoming, .active:
            Section {
                if Contracts.canRenew(contract, among: allContracts) {
                    Button("Renew") { $gate.unless(ProGate.edit(access)) { choosingRenewal = true } }
                }
                Button("Cancel Contract", role: .destructive) { $gate.unless(ProGate.edit(access)) { confirmingCancel = true } }
            }
        case .ended, .cancelled:
            if Contracts.canRenew(contract, among: allContracts) {
                Section {
                    Button("Renew") { $gate.unless(ProGate.edit(access)) { choosingRenewal = true } }
                }
            }
        }
    }

    /// The visits it books: its days, how many are ahead, and Book Visits.
    @ViewBuilder
    private var visitsSection: some View {
        let ahead = ContractSchedule.visitsAhead(of: contract, in: modelContext).count
        if ContractSchedule.hasSchedule(contract) || ahead > 0 {
            Section {
                LabeledContent("Days", value: ContractSchedule.summary(of: contract))
                LabeledContent("Booked Ahead", value: ahead == 1 ? "1 visit" : "\(ahead) visits")
                if ContractSchedule.canBook(contract) {
                    Button(ahead == 0 ? "Book Visits" : "Book Again") { $gate.unless(ProGate.edit(access)) { confirmingBook = true } }
                }
            } header: {
                Text("Visits")
            } footer: {
                Text(visitsNote(ahead: ahead))
            }
        }
    }

    /// Its payments (season or monthly): each date and amount, and its
    /// invoice once made. A per-visit contract bills its visits instead.
    @ViewBuilder
    private var paymentsSection: some View {
        let ledger = ContractInstallments.ledger(of: contract, in: modelContext)
        let due = ContractInstallments.due(contract, now: .now)
        if !ledger.isEmpty {
            Section {
                ForEach(ledger, id: \.installment.index) { entry in
                    if let invoice = entry.invoice {
                        NavigationLink { ProposalDetailView(proposal: invoice) } label: { paymentRow(entry.installment, invoice) }
                    } else if due.contains(entry.installment) {
                        HStack {
                            paymentRow(entry.installment, nil)
                            Button("Make Invoice") {
                                $gate.unless(ProGate.edit(access)) {
                                    ContractInstallments.makeInvoice(for: entry.installment, of: contract, in: modelContext)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    } else {
                        paymentRow(entry.installment, nil)
                    }
                }
            } header: {
                Text("Payments")
            } footer: {
                Text("On a payment's date, Make Invoice makes its draft, ready for you to send. Nothing is sent by itself.")
            }
        }
    }

    private func paymentRow(_ installment: ContractInstallments.Installment, _ invoice: Proposal?) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(installment.date.formatted(.dateTime.month(.abbreviated).day().year()))
                Text(invoice.map { $0.invoiceNumber } ?? paymentNote(installment))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(installment.amount, format: .currency(code: "USD"))
            if let invoice {
                StatusChip(invoice.invoiceStatus.rawValue, color: invoice.invoiceStatus.chipColor)
            }
        }
    }

    /// A payment with no invoice: still to come, or never made (the
    /// contract was cancelled first, or it was deleted).
    private func paymentNote(_ installment: ContractInstallments.Installment) -> String {
        if contract.installmentsMade.contains(installment.index) { return "Invoice deleted" }
        if let cancelled = contract.cancelledAt, installment.date > Calendar.current.startOfDay(for: cancelled) {
            return "Not billed: cancelled"
        }
        if contract.signedAt == nil { return "Once signed" }
        if contract.client == nil { return "Client deleted" }
        return installment.date <= .now ? "Due" : "Due on this date"
    }

    private func visitsNote(ahead: Int) -> String {
        if ContractSchedule.canBook(contract) {
            return ahead == 0
                ? "Puts its visits on the Schedule, from today to its last day, at each place it applies to."
                : "Booking again replaces the visits it booked that aren't done yet: after changing its days, say."
        }
        if contract.signedAt == nil { return "Book them once it's signed." }
        if contract.client?.isActive == false { return "Its client is inactive: mark them active to book visits." }
        return ""
    }

    private var bookMessage: String {
        let plan = ContractSchedule.plan(contract, in: modelContext)
        let ahead = ContractSchedule.visitsAhead(of: contract, in: modelContext).count
        let count = plan.visits.count
        var text = "\(ContractSchedule.summary(of: contract)): \(count == 1 ? "1 visit" : "\(count) visits") on the Schedule."
        if ahead > 0 { text += " The \(ahead) it booked before that aren't done yet are replaced." }
        if plan.keptDays > 0 {
            text += " \(plan.keptDays == 1 ? "1 day already has" : "\(plan.keptDays) days already have") a visit there, left as it is."
        }
        return text
    }

    private func renew(raising percent: Double) {
        renewalDraft = Contracts.renewal(of: contract, increasePercent: percent)
    }

    /// The PDF to share, in the temporary folder.
    private func writePDF() {
        let profile = allProfiles.first { $0.operatorID == contract.operatorID }
        let data = ContractPDF.generate(contract, client: contract.client, profile: profile, catalog: allServiceItems,
                                        madeWithPlowR: access.showsMadeWithPlowR)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(ContractPDF.fileName(contract))
        if (try? data.write(to: url)) != nil { pdfURL = url }
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
