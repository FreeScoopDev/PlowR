import SwiftUI
import SwiftData

struct ProposalDetailView: View {
    @Bindable var proposal: Proposal
    @Environment(\.modelContext) private var modelContext
    @Query private var allProfiles: [BusinessProfile]
    @Query private var allPaymentMethods: [PaymentMethod]
    @Query private var allClients: [Client]
    @Query private var allProposals: [Proposal]

    @State private var pdfData: Data? = nil
    @State private var isSharing = false
    @State private var shareURL: URL? = nil
    @State private var showingEditView = false
    @State private var showingReviseDialog = false

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

    // MARK: - Body

    var body: some View {
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
                Button { shareDocument() } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(pdfData == nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
                .background(.ultraThinMaterial)
        }
        .onAppear { generatePDF() }
        .onChange(of: proposal.total) { _, _ in generatePDF() }
        .onChange(of: proposal.invoicePaidAt) { _, _ in generatePDF() }
        .onChange(of: proposal.invoiceSentAt) { _, _ in generatePDF() }
        .sheet(isPresented: $isSharing) {
            if let url = shareURL { ProposalShareSheet(url: url) }
        }
        .sheet(isPresented: $showingEditView, onDismiss: { generatePDF() }) {
            ProposalEditView(proposal: proposal)
        }
        .confirmationDialog("Revise Paid Invoice", isPresented: $showingReviseDialog, titleVisibility: .visible) {
            Button("Create Revision Copy") { createRevision() }
            Button("Reset to Draft", role: .destructive) { resetToDraft() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Create a new draft revision, or reset this invoice back to Draft status.")
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private var actionBar: some View {
        HStack(spacing: 12) {
            switch status {
            case .proposal:
                Button { convertToInvoice() } label: {
                    Label("Convert to Invoice", systemImage: "doc.badge.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

            case .draft:
                Button { showingEditView = true } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { markSent() } label: {
                    Label("Mark Sent", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

            case .sent, .overdue:
                Button {
                    proposal.invoicePaidAt = Date()
                    generatePDF()
                } label: {
                    Label("Mark Paid", systemImage: "checkmark.seal.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)

            case .paid:
                Button { showingReviseDialog = true } label: {
                    Label("Revise", systemImage: "doc.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    // MARK: - PDF

    private func generatePDF() {
        pdfData = PDFGenerator.generate(
            proposal: proposal,
            profile: profile,
            paymentMethods: activePaymentMethods,
            forceIsInvoice: proposal.isInvoice
        )
    }

    private func shareDocument() {
        guard let data = pdfData else { return }
        let prefix = proposal.isInvoice ? "Invoice" : "Proposal"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(proposal.clientName).pdf")
        try? data.write(to: url)
        shareURL = url
        isSharing = true
    }

    // MARK: - Actions

    private func convertToInvoice() {
        let count = allProposals.filter { $0.isInvoice && $0.operatorID == proposal.operatorID }.count
        proposal.invoiceNumber = String(format: "INV-%04d", count + 1)
        proposal.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
        generatePDF()
    }

    private func markSent() {
        proposal.invoiceSentAt = Date()
        if proposal.invoiceDueDate == nil {
            proposal.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
        }
        generatePDF()
    }

    private func resetToDraft() {
        proposal.invoicePaidAt = nil
        proposal.invoiceSentAt = nil
        generatePDF()
    }

    private func createRevision() {
        guard let client = proposalClient else { return }
        let revisionCount = allProposals.filter { $0.revisionOf == proposal.invoiceNumber }.count
        let revision = Proposal(operatorID: proposal.operatorID, client: client)
        revision.invoiceNumber = "\(proposal.invoiceNumber)-R\(revisionCount + 1)"
        revision.revisionOf = proposal.invoiceNumber
        revision.discountAmount = proposal.discountAmount
        revision.taxRate = proposal.taxRate
        revision.disclaimer = proposal.disclaimer
        revision.notes = proposal.notes
        revision.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
        let copies = (proposal.lineItems ?? []).map { item in
            ProposalLineItem(
                serviceName: item.serviceName,
                zoneLabel: item.zoneLabel,
                quantity: item.quantity,
                unitType: item.unitType,
                unitPrice: item.unitPrice,
                sortOrder: item.sortOrder,
                itemNotes: item.itemNotes
            )
        }
        copies.forEach { modelContext.insert($0) }
        revision.lineItems = copies
        modelContext.insert(revision)
    }
}
