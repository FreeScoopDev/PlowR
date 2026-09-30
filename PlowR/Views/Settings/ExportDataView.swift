import SwiftUI
import SwiftData

/// Settings → Export Data: clients, invoices and the Service History as
/// spreadsheet files (CSVExport), to share, save to Files, or send to an
/// accountant.
struct ExportDataView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @State private var files: [Export] = []
    @State private var failed = false

    struct Export: Identifiable {
        let title: String
        let detail: String
        let systemImage: String
        let url: URL
        var id: String { title }
    }

    var body: some View {
        List {
            Section {
                ForEach(files) { export in
                    ShareLink(item: export.url) {
                        HStack(spacing: 12) {
                            IconBadge(systemImage: export.systemImage, color: .blue, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(export.title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text(export.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "square.and.arrow.up").foregroundStyle(.secondary)
                        }
                    }
                }
            } footer: {
                Text(failed ? "The files couldn't be made. Try again."
                     : "Spreadsheet (CSV) files that open in Numbers, Excel or Google Sheets, and import into most accounting software. Money has two decimals; dates are year-month-day.")
            }
        }
        .navigationTitle("Export Data")
        .navigationBarTitleDisplayMode(.inline)
        .task { makeFiles() }
    }

    private func makeFiles() {
        let operatorID = authManager.userID
        let clients = (try? modelContext.fetch(FetchDescriptor<Client>())) ?? []
        let documents = (try? modelContext.fetch(FetchDescriptor<Proposal>())) ?? []
        let records = (try? modelContext.fetch(FetchDescriptor<ServiceRecord>())) ?? []
        do {
            files = [
                Export(title: "Clients", detail: "\(clients.filter { $0.operatorID == operatorID }.count) clients",
                       systemImage: "person.2",
                       url: try CSVExport.file("Clients", contents: CSVExport.clients(clients, operatorID: operatorID))),
                Export(title: "Invoices",
                       detail: "\(documents.filter { $0.operatorID == operatorID && $0.isInvoice }.count) invoices",
                       systemImage: "doc.text",
                       url: try CSVExport.file("Invoices",
                                               contents: CSVExport.invoices(documents, operatorID: operatorID))),
                Export(title: "Payments",
                       detail: "\(documents.filter { $0.operatorID == operatorID }.reduce(0) { $0 + ($1.payments?.count ?? 0) }) payments",
                       systemImage: "banknote",
                       url: try CSVExport.file("Payments",
                                               contents: CSVExport.payments(documents, operatorID: operatorID))),
                Export(title: "Service History",
                       detail: "\(records.filter { $0.operatorID == operatorID }.count) jobs",
                       systemImage: "list.bullet.clipboard",
                       url: try CSVExport.file("Service History",
                                               contents: CSVExport.serviceHistory(records, operatorID: operatorID,
                                                                                  in: modelContext)))
            ]
            failed = false
        } catch {
            failed = true
        }
    }
}
