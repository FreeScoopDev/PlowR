import SwiftUI
import SwiftData
import MessageUI

struct ProposalDetailView: View {
    @Bindable var proposal: Proposal
    @Environment(\.modelContext) private var modelContext
    @Query private var allProfiles: [BusinessProfile]
    @Query private var allPaymentMethods: [PaymentMethod]
    @Query private var allClients: [Client]

    @State private var pdfData: Data? = nil
    @State private var shareURL: URL? = nil
    @State private var showingShare = false
    @State private var showingEditView = false
    @State private var showingReviseDialog = false
    @State private var showingReminder = false

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
                    Button { showingShare = true } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(.tertiary)
                }
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
        .onChange(of: allProfiles) { _, _ in generatePDF() }
        // Sent to the client from the share sheet: they're awaiting a response.
        .sheet(isPresented: $showingShare) {
            if let url = shareURL {
                DocumentShareSheet(url: url) {
                    DocumentSent.shared(proposal, in: modelContext)
                }
                .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showingReminder) {
            if let phone = proposalClient?.phone, !phone.isEmpty {
                MessageComposer(recipients: [phone], body: reminderMessage) { _ in }
            }
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
                Button { showingEditView = true } label: {
                    Label("Edit", systemImage: "pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button { convertToInvoice() } label: {
                    Label("Convert", systemImage: "doc.badge.arrow.up")
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
                Button { showingEditView = true } label: {
                    Label("Edit", systemImage: "pencil")
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
        Task { @MainActor in
            await Task.yield()
            let data = PDFGenerator.generate(
                proposal: proposal,
                profile: profile,
                paymentMethods: activePaymentMethods,
                forceIsInvoice: proposal.isInvoice
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
        generatePDF()
    }

    private func markSent() {
        DocumentSent.markSent(proposal, in: modelContext)
        generatePDF()
    }

    private func resetToDraft() {
        proposal.invoicePaidAt = nil
        proposal.invoiceSentAt = nil
        generatePDF()
    }

    private func createRevision() {
        guard let client = proposalClient else { return }
        let revision = Proposal(operatorID: proposal.operatorID, client: client)
        revision.invoiceNumber = InvoiceNumbering.nextRevision(of: proposal.invoiceNumber,
                                                               operatorID: proposal.operatorID, in: modelContext)
        revision.revisionOf = proposal.invoiceNumber
        revision.discountAmount = proposal.discountAmount
        revision.taxRate = proposal.taxRate
        revision.disclaimer = proposal.disclaimer
        revision.notes = proposal.notes
        revision.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
        let copies = proposal.makeLineItemCopies()
        copies.forEach { modelContext.insert($0) }
        revision.lineItems = copies
        modelContext.insert(revision)
    }
}
