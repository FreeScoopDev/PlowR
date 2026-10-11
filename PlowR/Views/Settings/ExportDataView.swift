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
            if files.count > 1 {
                Section {
                    ShareLink(items: files.map(\.url)) {
                        Label("Share All \(files.count) Files", systemImage: "square.and.arrow.up.on.square")
                    }
                } footer: {
                    Text("Every file at once, to Files, Mail or AirDrop.")
                }
            }
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
                     : "Spreadsheet (CSV) files that open in Numbers, Excel or Google Sheets, and import into most accounting software. Money has two decimals; dates are year-month-day. Invoice Lines has the services on invoices billed (not drafts, or void ones with no money on them), before discount and tax, which are in Invoices. They're a copy to keep: routes, photos and settings aren't in them. Import Clients can bring back the Clients file's names, phones, emails, addresses, tags and notes (not whether a client is inactive or comped, their discount, or their other properties); the other files can't be loaded into PlowR.")
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
        let contracts = Contracts.all(in: modelContext)
        let visits = (try? modelContext.fetch(FetchDescriptor<ScheduledVisit>())) ?? []
        let catalog = (try? modelContext.fetch(FetchDescriptor<ServiceItem>())) ?? []
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
                Export(title: "Invoice Lines",
                       detail: "\(CSVExport.billedInvoices(documents, operatorID: operatorID).reduce(0) { $0 + ($1.lineItems?.count ?? 0) }) lines billed",
                       systemImage: "list.bullet.rectangle",
                       url: try CSVExport.file("Invoice Lines",
                                               contents: CSVExport.invoiceLines(documents, operatorID: operatorID))),
                Export(title: "Proposals",
                       detail: "\(documents.filter { $0.operatorID == operatorID && !$0.isInvoice }.count) proposals",
                       systemImage: "doc.plaintext",
                       url: try CSVExport.file("Proposals",
                                               contents: CSVExport.proposals(documents, operatorID: operatorID))),
                Export(title: "Payments",
                       detail: "\(Payments.receiptEntries(documents.filter { $0.operatorID == operatorID }).count) amounts received",
                       systemImage: "banknote",
                       url: try CSVExport.file("Payments",
                                               contents: CSVExport.payments(documents, operatorID: operatorID))),
                Export(title: "Contracts",
                       detail: "\(contracts.filter { $0.operatorID == operatorID }.count) contracts",
                       systemImage: "signature",
                       url: try CSVExport.file("Contracts", contents: CSVExport.contracts(contracts, operatorID: operatorID,
                                                                                         catalog: catalog))),
                Export(title: "Schedule",
                       detail: "\(visits.filter { $0.operatorID == operatorID }.count) visits",
                       systemImage: "calendar",
                       url: try CSVExport.file("Schedule", contents: CSVExport.schedule(visits, operatorID: operatorID,
                                                                                       catalog: catalog))),
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
