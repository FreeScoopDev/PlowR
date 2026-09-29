import PDFKit
import SwiftData
import SwiftUI

struct ProposalPreviewView: View {
    let pdfData: Data
    let client: Client
    var isInvoice: Bool = false
    /// The PDF was sent to the client from the share sheet (Mark as Sent
    /// on), before the document was saved.
    var onShared: () -> Void = {}
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var showingShare = false

    @State private var shareURL: URL?

    private var docTitle: String { isInvoice ? "Invoice Preview" : "Proposal Preview" }
    private var filePrefix: String { isInvoice ? "Invoice" : "Proposal" }

    var body: some View {
        NavigationStack {
            PDFKitView(data: pdfData)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(docTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Back") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        HStack(spacing: 8) {
                            if shareURL != nil {
                                Button { showingShare = true } label: {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                            Button {
                                onSave()
                                dismiss()
                            } label: {
                                Text("Save")
                                    .fontWeight(.semibold)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
        }
        .onAppear { prepareShareURL() }
        // Sent to the client from the share sheet (Mark as Sent on): they're
        // awaiting a response, and the builder saves it as shared.
        .sheet(isPresented: $showingShare) {
            if let url = shareURL {
                DocumentShareView(url: url, status: isInvoice ? .draft : .proposal, clientName: client.name) { toClient in
                    if DocumentSent.sharedBeforeSave(clientID: client.id.uuidString, toClient: toClient,
                                                     in: modelContext) {
                        onShared()
                    }
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func prepareShareURL() {
        let safe = client.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filePrefix)-\(safe).pdf")
        try? pdfData.write(to: url)
        shareURL = url
    }
}

struct PDFKitView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        view.document = PDFDocument(data: data)
    }
}
