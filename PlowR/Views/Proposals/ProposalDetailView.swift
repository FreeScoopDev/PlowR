import SwiftUI
import SwiftData
import MessageUI

struct ProposalDetailView: View {
    @Bindable var proposal: Proposal
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.access) private var access
    @State private var gate: ProGate?
    @Query private var allProfiles: [BusinessProfile]
    @Query private var allPaymentMethods: [PaymentMethod]
    @Query private var allClients: [Client]
    @Query private var allServiceItems: [ServiceItem]
    @Query private var allContracts: [Contract]
    /// For a number two devices both gave out (InvoiceRecords).
    @Query private var allProposals: [Proposal]

    @State private var pdfData: Data? = nil
    @State private var shareURL: URL? = nil
    @State private var showingShare = false
    @State private var showingEditView = false
    @State private var showingReviseDialog = false
    @State private var showingReminder = false
    @State private var showingPayments = false
    /// A contract being made from this proposal (Contracts.draft(from:)).
    @State private var contractDraft: Contracts.Draft?

    // MARK: - Computed Properties

    private var profile: BusinessProfile? {
        allProfiles.first { $0.operatorID == proposal.operatorID }
    }

    private var activePaymentMethods: [PaymentMethod] {
        allPaymentMethods
            .filter { $0.operatorID == proposal.operatorID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var proposalClient: Client? {
        allClients.first { $0.id.uuidString == proposal.clientID }
    }

    private var status: InvoiceStatus { proposal.invoiceStatus }

    private var navTitle: String {
        proposal.isInvoice ? proposal.invoiceNumber : "Proposal"
    }

    private var reminderMessage: String { proposal.reminderMessage() }


    // MARK: - Body

    var body: some View {
        if proposal.isDeleted || proposal.modelContext == nil {
            // Deleted on another device while open: nothing left to show.
            Color.clear.onAppear { dismiss() }
        } else {
            document
        }
    }

    private var document: some View {
        Group {
            if let data = pdfData {
                PDFKitView(data: data)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView("Generating PDF…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(navTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if shareURL != nil {
                    Button {
                        $gate.unless(ProGate.shareDocument(access, isInvoice: proposal.isInvoice,
                                                           owed: proposal.balanceDue)) {
                            showingShare = true
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .safeAreaInset(edge: .top) {
            // Two sent invoices with one number (made on two devices before
            // they synced): never renumbered, since the client has it; said here.
            if InvoiceRecords.hasDuplicateNumber(proposal, among: allProposals) {
                Label("Another invoice also has the number \(proposal.invoiceNumber). They were made on two devices before they synced; revise or void one.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial)
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
                .background(.ultraThinMaterial)
        }
        .proGateSheet($gate)
        .onAppear { generatePDF() }
        .onChange(of: access.showsMadeWithPlowR) { _, _ in generatePDF() }
        .onChange(of: proposal.total) { _, _ in generatePDF() }
        .onChange(of: proposal.invoicePaidAt) { _, _ in generatePDF() }
        .onChange(of: proposal.amountPaid) { _, _ in generatePDF() }
        .onChange(of: proposal.invoiceSentAt) { _, _ in generatePDF() }
        .onChange(of: proposal.voidedAt) { _, _ in generatePDF() }
        .onChange(of: allProfiles) { _, _ in generatePDF() }
        // Sent to the client from the share sheet (Mark as Sent on): they're
        // awaiting a response.
        .sheet(isPresented: $showingShare) {
            if let url = shareURL {
                DocumentShareView(url: url, document: proposal, in: modelContext)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showingReminder) {
            if let phone = proposalClient?.phone, !phone.isEmpty {
                MessageComposer(recipients: [phone], body: reminderMessage) { outcome in
                    if outcome == .sent, let id = UUID(uuidString: proposal.clientID) {
                        TextLog.record(.invoiceReminder, body: reminderMessage, to: [id], in: modelContext)
                    }
                }
            }
        }
        .sheet(isPresented: Binding(get: { contractDraft != nil }, set: { if !$0 { contractDraft = nil } })) {
            if let client = proposalClient, let draft = contractDraft {
                ContractEditView(client: client, draft: draft)
            }
        }
        .sheet(isPresented: $showingPayments) {
            InvoicePaymentsView(invoice: proposal)
        }
        .sheet(isPresented: $showingEditView, onDismiss: { generatePDF() }) {
            ProposalEditView(proposal: proposal)
        }
        // An invoice that's out is a record: changed by a revision, or voided
        // (InvoiceRecords). Never edited under its number, never deleted.
        .confirmationDialog("Revise or Void \(proposal.invoiceNumber)", isPresented: $showingReviseDialog,
                            titleVisibility: .visible) {
            Button("Create Revision") { createRevision() }
            Button("Void Invoice", role: .destructive) {
                InvoiceRecords.void(proposal, note: "Voided", in: modelContext)
                generatePDF()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A revision is a new invoice that replaces this one: what was paid moves to it, and this one is kept as void. Void takes it back with no replacement: it stays on record and owes nothing, and if nothing was paid on it, its work can be billed again.")
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 12) {
            switch status {
            case .proposal:
                Button { showingEditView = true } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                // Agreed for a period, not a one-off: a contract. Once it is,
                // the proposal is spoken for: no second contract, no invoice.
                if let made = Contracts.madeFrom(proposal, among: allContracts) {
                    NavigationLink { ContractDetailView(contract: made) } label: {
                        Label("View Contract", systemImage: "signature")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    if let client = proposalClient {
                        Button {
                            $gate.unless(ProGate.edit(access)) {
                                contractDraft = Contracts.draft(from: proposal, client: client, catalog: allServiceItems)
                            }
                        } label: {
                            Label("Contract", systemImage: "signature")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button { $gate.unless(ProGate.edit(access)) { convertToInvoice() } } label: {
                        Label("Convert", systemImage: "doc.badge.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }

            case .draft:
                Button { showingEditView = true } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    // Sending an invoice still owed is how they get paid: open
                    // read only, as sharing it is.
                    $gate.unless(ProGate.shareDocument(access, isInvoice: proposal.isInvoice,
                                                       owed: proposal.balanceDue)) { markSent() }
                } label: {
                    Label("Mark Sent", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

            case .sent, .overdue:
                Button { $gate.unless(ProGate.edit(access)) { showingReviseDialog = true } } label: {
                    Label("Revise", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if MFMessageComposeViewController.canSendText(),
                   let phone = proposalClient?.phone, !phone.isEmpty {
                    Button { showingReminder = true } label: {
                        Label("Remind", systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                }

                // All that's owed, or part of it (Payments).
                Button { showingPayments = true } label: {
                    Label("Payment", systemImage: "dollarsign.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            case .paid:
                // A revision of a paid invoice not yet sent: paid until its
                // lines change, and still edited in place.
                if InvoiceRecords.canEditInPlace(proposal) {
                    Button { showingEditView = true } label: {
                        Label("Edit", systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                Button { showingPayments = true } label: {
                    Label("Payments", systemImage: "dollarsign.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { $gate.unless(ProGate.edit(access)) { showingReviseDialog = true } } label: {
                    Label("Revise", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)

            case .void:
                // Kept on record: its payments (if any) can still be seen.
                Button { showingPayments = true } label: {
                    Label("Payments", systemImage: "dollarsign.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - PDF

    private func generatePDF() {
        Task { @MainActor in
            await Task.yield()
            let data = PDFGenerator.generate(
                proposal: proposal,
                profile: profile,
                paymentMethods: activePaymentMethods,
                forceIsInvoice: proposal.isInvoice,
                madeWithPlowR: access.showsMadeWithPlowR
            )
            pdfData = data
            let prefix = proposal.isInvoice ? "Invoice" : "Proposal"
            let safe = proposal.clientName.replacingOccurrences(of: "/", with: "-")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(prefix)-\(safe).pdf")
            try? data.write(to: url)
            shareURL = url
        }
    }

    // MARK: - Actions

    private func convertToInvoice() {
        proposal.invoiceNumber = InvoiceNumbering.next(operatorID: proposal.operatorID, in: modelContext)
        proposal.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
        // A proposal made for a scheduled visit now bills the visit's work.
        if !proposal.visitID.isEmpty {
            ServiceLog.markVisitInvoiced(visitID: proposal.visitID, invoice: proposal, in: modelContext)
        }
        generatePDF()
    }

    private func markSent() {
        DocumentSent.markSent(proposal, in: modelContext)
        generatePDF()
    }

    private func createRevision() {
        guard let client = proposalClient else { return }
        ServiceLog.revise(proposal, client: client, in: modelContext)
        generatePDF()
    }
}
