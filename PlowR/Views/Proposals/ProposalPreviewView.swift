import SwiftUI
import PDFKit

struct ProposalPreviewView: View {
    let pdfData: Data
    let client: Client
    var isInvoice: Bool = false
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss

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
                            if let url = shareURL {
                                ShareLink(
                                    item: url,
                                    preview: SharePreview(docTitle, icon: Image(systemName: "doc.fill"))
                                ) {
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

struct ProposalShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
