import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Import Clients: a client list from a spreadsheet (CSV), from Settings or
/// the empty Clients screen. Choose the file; check the columns PlowR
/// guessed (ClientImport) and what each row would do; import; then watch the
/// map pins go in (ImportPins) and undo the import if it wasn't right. An
/// import can be undone later from here too (Recent Imports), until its
/// clients' tag is taken off.
struct ImportClientsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    /// Opened as a sheet (the empty Clients screen): it has its own Close.
    var isSheet = false

    @State private var choosingFile = false
    @State private var fileName = ""
    @State private var table: CSVReader.Table?
    @State private var fields: [ClientImport.Field] = []
    @State private var kind: ClientImport.Kind = .customers
    @State private var asProperties = false
    @State private var known: [ClientImport.Known] = []
    @State private var preview: ClientImport.Preview?
    @State private var fileProblem: String?
    @State private var saveFailed = false
    @State private var isSaving = false
    @State private var result: ClientImport.Result?
    @State private var recent: [ClientImport.Result] = []
    @State private var confirmingUndo: ClientImport.Result?
    @State private var undoPlan: ClientImport.UndoPlan?
    @State private var undone: String?
    @State private var undoFailed = false
    @State private var nothingToUndo = false
    /// The preview changed when it was checked again just before saving
    /// (iCloud brought clients meanwhile): shown instead of saving.
    @State private var previewChanged = false
    private let pins = ImportPins.shared

    var body: some View {
        Form {
            if let result {
                importedSections(result)
            } else if let table {
                mappingSections(table)
            } else {
                startSections
            }
        }
        .navigationTitle("Import Clients")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                }
            }
        }
        .fileImporter(isPresented: $choosingFile,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text, .data]) { picked in
            switch picked {
            case let .success(url): load(url)
            case let .failure(error):
                // Cancelled: whatever was loaded stays.
                if (error as? CocoaError)?.code != .userCancelled {
                    showFileProblem("That file couldn't be opened. Try again, or choose another.")
                }
            }
        }
        .onChange(of: fields) { refresh() }
        .onChange(of: asProperties) { refresh() }
        .onAppear { recent = ClientImport.recentImports(in: modelContext, operatorID: authManager.userID) }
        .confirmationDialog("Undo This Import?", isPresented: Binding(get: { confirmingUndo != nil },
                                                                     set: { if !$0 { confirmingUndo = nil } }),
                            titleVisibility: .visible, presenting: confirmingUndo) { imported in
            Button("Undo Import", role: .destructive) { undo(imported) }
        } message: { _ in
            Text(undoMessage)
        }
        .alert("Nothing to Undo", isPresented: $nothingToUndo) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(nothingToUndoMessage)
        }
        .alert("The Import Couldn't Be Undone", isPresented: $undoFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Nothing was removed. Try again in a moment.")
        }
    }

    // MARK: - Choosing the file

    @ViewBuilder private var startSections: some View {
        Section {
            Button {
                choosingFile = true
            } label: {
                Label("Choose a CSV File", systemImage: "doc.badge.plus")
            }
        } footer: {
            Text("A spreadsheet of your clients saved as CSV, with the first row naming the columns: Name, Phone, Email, Address and so on. PlowR matches the columns, shows what it will add, and skips clients you already have.")
        }
        if let fileProblem {
            Section {
                Label(fileProblem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
        if let undone {
            Section {
                Label(undone, systemImage: "arrow.uturn.backward.circle.fill")
            }
        }
        Section("Getting a CSV File") {
            hint("Numbers", "File > Export To > CSV.")
            hint("Excel", "File > Save As, then CSV UTF-8.")
            hint("Google Sheets", "File > Download > Comma-separated values.")
            hint("Google Contacts", "Select contacts, then Export > Google CSV.")
            hint("Another app", "Look for Export Clients or Export Customers in its settings.")
        }
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.self) { imported in
                    let when = imported.tag.dropFirst(ClientImport.tagPrefix.count).description
                    LabeledContent {
                        Button("Undo", role: .destructive) { askToUndo(imported) }
                            .accessibilityLabel("Undo the import of \(when)")
                    } label: {
                        Text(when)
                        Text(count(imported.clients, "client", "clients") + " still tagged")
                    }
                }
            } header: {
                Text("Recent Imports")
            } footer: {
                Text("Undo removes the clients an import added that haven't been used since. Taking the import's tag off a client keeps them.")
            }
        }
    }

    private func hint(_ app: String, _ how: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(app).font(.subheadline)
            Text(how).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// A file couldn't be used: back to the start, which says why.
    private func showFileProblem(_ problem: String) {
        fileProblem = problem
        table = nil
        preview = nil
    }

    /// Bigger than any client list (50,000 rows is a few MB): not read.
    private static let largestFile = 10_000_000

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        undone = nil
        do {
            // A file whose size isn't known (a stream, a provider that won't say)
            // could be anything: it isn't read whole into memory.
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let size else {
                showFileProblem("PlowR couldn't tell how big that file is. Save the CSV file of your clients to Files on this device and choose it there.")
                return
            }
            guard size <= Self.largestFile else {
                showFileProblem("That file is too big to be a client list. Choose the CSV file of your clients.")
                return
            }
            let data = try Data(contentsOf: url)
            let read = try CSVReader.read(data)
            fileName = url.lastPathComponent
            fields = ClientImport.guess(read.header, rows: Array(read.rows.prefix(200)))
            known = ClientImport.known(in: modelContext, operatorID: authManager.userID)
            table = read
            fileProblem = nil
            previewChanged = false
            saveFailed = false
            refresh()
        } catch CSVReader.Problem.notText {
            showFileProblem("That isn't a CSV file. If it's an Excel or Numbers spreadsheet, export it as CSV, then choose the CSV file.")
        } catch CSVReader.Problem.empty {
            showFileProblem("That file is empty.")
        } catch {
            showFileProblem("That file couldn't be opened. Try saving it again, or choose another.")
        }
    }

    private func refresh() {
        guard let table else { return }
        preview = ClientImport.preview(table, fields: fields, existing: known, addressesAsProperties: asProperties)
    }

    // MARK: - Columns and preview

    private var hasName: Bool {
        fields.contains { [.name, .firstName, .lastName, .company].contains($0) }
    }

    @ViewBuilder private func mappingSections(_ table: CSVReader.Table) -> some View {
        Section {
            LabeledContent("File", value: fileName)
            LabeledContent("Rows", value: "\(table.rows.count)")
            Button("Choose Another File") { choosingFile = true }
        } footer: {
            if let line = table.unclosedQuoteLine {
                Text("A quote opened on line \(line) is never closed, so everything after it may be in one cell. Check the rows from there in the preview.")
                    .foregroundStyle(.orange)
            }
        }

        Section {
            Picker("These Clients Are", selection: $kind) {
                Text("Current Customers").tag(ClientImport.Kind.customers)
                Text("Leads").tag(ClientImport.Kind.leads)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Who Are They?")
        } footer: {
            Text(kind == .customers
                 ? "Clients you work for now. They're counted as customers, not listed in the Pipeline."
                 : "People you hope to work for. They're listed in the Pipeline as leads.")
        }

        Section {
            ForEach(table.header.indices, id: \.self) { column in
                Picker(selection: fieldBinding(column)) {
                    ForEach(ClientImport.Field.allCases) { field in
                        Text(field.title).tag(field)
                    }
                } label: {
                    Text(table.header[column].isEmpty ? "Column \(column + 1)" : table.header[column])
                    if let sample = sample(column, in: table) {
                        Text(sample).lineLimit(1)
                    }
                }
            }
        } header: {
            Text("Columns")
        } footer: {
            Text(hasName ? "PlowR guessed what each column holds from its name. Change any that's wrong; columns set to Don't Import are left out."
                 : "Choose which column holds the client's name (or first and last name, or company).")
                .foregroundStyle(hasName ? Color.secondary : Color.orange)
        }

        Section {
            Toggle("Extra Addresses as Properties", isOn: $asProperties)
        } footer: {
            Text("When a client is listed again (same name and phone) at another address, add that address as one of their properties. Off, those rows are skipped.")
        }

        if let preview, hasName {
            previewSections(preview, table: table)
        }
    }

    /// A column's field. Choosing one another column has takes it from
    /// that column (only the first would be read); notes can come from many.
    private func fieldBinding(_ column: Int) -> Binding<ClientImport.Field> {
        Binding(get: { fields.indices.contains(column) ? fields[column] : .ignore },
                set: { field in
                    guard fields.indices.contains(column) else { return }
                    var changed = fields
                    if field != .ignore, field != .notes {
                        for other in changed.indices where other != column && changed[other] == field {
                            changed[other] = .ignore
                        }
                    }
                    changed[column] = field
                    fields = changed
                })
    }

    /// The column's first filled-in value, as an example.
    private func sample(_ column: Int, in table: CSVReader.Table) -> String? {
        table.rows.lazy.compactMap { $0.indices.contains(column) && !$0[column].isEmpty ? $0[column] : nil }.first
    }

    @ViewBuilder private func previewSections(_ preview: ClientImport.Preview, table: CSVReader.Table) -> some View {
        Section {
            LabeledContent("New Clients", value: "\(preview.new.count)")
            if preview.properties > 0 {
                LabeledContent("Properties of Clients", value: "\(preview.properties)")
            }
            LabeledContent("Duplicates (Skipped)", value: "\(preview.duplicates)")
            if preview.samePhones > 0 {
                LabeledContent("Another Client's Phone (Skipped)", value: "\(preview.samePhones)")
            }
            if !preview.problems.isEmpty {
                LabeledContent("Not Imported", value: "\(preview.problems.count)")
            }
            NavigationLink("See Every Row") {
                ImportPreviewList(preview: preview, table: table)
            }
        } header: {
            Text("What Will Happen")
        } footer: {
            Text("Duplicates are clients already in PlowR, or listed twice in the file: same name and phone, or same name and address."
                 + (preview.samePhones > 0
                    ? " A row with another client's phone under a different name is skipped too; if it's someone else (a household, an office line), add them by hand. After the import, What Was Skipped lists every row left out."
                    : ""))
        }

        Section {
            Button {
                save(preview)
            } label: {
                HStack {
                    Text(importTitle(preview))
                    Spacer()
                    if isSaving { ProgressView() }
                }
            }
            .disabled(isSaving || preview.new.isEmpty && preview.properties == 0)
        } footer: {
            if previewChanged {
                Text("Clients arrived from iCloud since the file was chosen, so what will happen has changed. Check it, then import.")
                    .foregroundStyle(.orange)
            } else if saveFailed {
                Text("The clients couldn't be saved, and nothing was imported. Make sure there's free space on this device, then try again.")
                    .foregroundStyle(.orange)
            } else {
                Text("Each client is tagged with the import, so you can find them under Clients and undo it.")
            }
        }
    }

    private func importTitle(_ preview: ClientImport.Preview) -> String {
        if preview.new.isEmpty { return "Import \(count(preview.properties, "Property", "Properties"))" }
        return "Import \(count(preview.new.count, "Client", "Clients"))"
    }

    /// Saves the import, once: a second tap while saving, or after, does
    /// nothing. The clients are checked again first (iCloud may have brought
    /// some since the file was chosen); if that changes what will happen,
    /// the new preview is shown instead of saving.
    private func save(_ shown: ClientImport.Preview) {
        guard !isSaving, result == nil, let table else { return }
        isSaving = true
        Task {
            await Task.yield()                              // the spinner shows
            defer { isSaving = false }
            known = ClientImport.known(in: modelContext, operatorID: authManager.userID)
            let fresh = ClientImport.preview(table, fields: fields, existing: known, addressesAsProperties: asProperties)
            guard fresh == shown else {
                preview = fresh
                previewChanged = true
                return
            }
            do {
                result = try ClientImport.save(fresh, as: kind, operatorID: authManager.userID, in: modelContext)
                saveFailed = false
                previewChanged = false
                undone = nil
                let context = modelContext, operatorID = authManager.userID
                Task { await pins.startAfterImport(in: context, operatorID: operatorID) }
            } catch {
                saveFailed = true
            }
        }
    }

    // MARK: - Imported

    @ViewBuilder private func importedSections(_ result: ClientImport.Result) -> some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(undone ?? "Imported \(count(result.clients, "client", "clients"))"
                         + (result.properties > 0 ? " and \(count(result.properties, "property", "properties"))" : ""))
                        .font(.headline)
                    if undone == nil {
                        Text("Tagged \u{201C}\(result.tag)\u{201D}")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: undone == nil ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                    .foregroundStyle(undone == nil ? .green : .secondary)
            }
            if result.propertiesSkipped > 0 {
                Text("\(count(result.propertiesSkipped, "property wasn't", "properties weren't")) added: the client was deleted meanwhile.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }

        if undone == nil {
            pinSection
            if let preview, let table, preview.skipped > 0 {
                Section {
                    NavigationLink {
                        ImportPreviewList(preview: preview, table: table, skippedOnly: true)
                    } label: {
                        LabeledContent("What Was Skipped", value: "\(preview.skipped)")
                    }
                } footer: {
                    Text("Rows left out of the import, each with its row in the spreadsheet and why. Add any you want by hand.")
                }
            }
            Section {
                Button("Undo This Import", role: .destructive) { askToUndo(result) }
            } footer: {
                Text("Removes the clients this import added, unless they've been used since. You can also undo it later from Import Clients.")
            }
        }
    }

    @ViewBuilder private var pinSection: some View {
        Section {
            if pins.isRunning, pins.total > 0 {
                ProgressView(value: Double(pins.done), total: Double(pins.total)) {
                    Text("Placing clients on the map: \(pins.done) of \(pins.total)")
                        .font(.subheadline)
                }
            } else if pins.isWaiting {
                Label("The map is busy. PlowR carries on the next time it's opened.", systemImage: "clock")
            } else if pins.notFound.isEmpty {
                Label("On the map", systemImage: "mappin.and.ellipse")
            }
            ForEach(pins.notFound) { missed in
                VStack(alignment: .leading, spacing: 2) {
                    Text(missed.name).font(.subheadline)
                    Text(missed.address).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Map Pins")
        } footer: {
            if !pins.notFound.isEmpty {
                Text("The map couldn't find \(count(pins.notFound.count, "address", "addresses")). Those clients have no pin, so they aren't on route maps. They're marked in your client list, and PlowR won't look them up again: open each one to correct the address or set the pin.")
            } else if pins.isRunning {
                Text("Apple's map limits lookups, so PlowR places about 30 a minute. This carries on in the background; keep PlowR open to finish sooner.")
            }
        }
    }

    // MARK: - Undo

    private var undoMessage: String {
        guard let plan = undoPlan else { return "" }
        var parts = ["Removes \(count(plan.removable.count, "client", "clients")) this import added"
                     + (plan.properties.isEmpty ? "" : " and \(count(plan.properties.count, "property", "properties")) it added to other clients")
                     + "."]
        if plan.kept > 0 {
            parts.append("\(count(plan.kept, "client has", "clients have")) been used since (a route, a visit, a document or the like) and \(plan.kept == 1 ? "is" : "are") kept.")
        }
        if plan.keptProperties > 0 {
            parts.append("\(count(plan.keptProperties, "property has", "properties have")) been worked at and \(plan.keptProperties == 1 ? "is" : "are") kept.")
        }
        return parts.joined(separator: " ")
    }

    /// Why an undo would remove nothing, from its plan.
    private var nothingToUndoMessage: String {
        guard let plan = undoPlan else { return "" }
        if plan.kept > 0 || plan.keptProperties > 0 {
            let kept = [plan.kept > 0 ? count(plan.kept, "client", "clients") : nil,
                        plan.keptProperties > 0 ? count(plan.keptProperties, "property", "properties") : nil]
                .compactMap { $0 }.joined(separator: " and ")
            return "What's left of this import (\(kept)) has been used since (a route, a visit, a document or the like), so it's kept. To remove a client, delete it from its page."
        }
        return "Nothing from this import is left: its clients were deleted or had the import's tag taken off."
    }

    private func askToUndo(_ imported: ClientImport.Result) {
        let plan = ClientImport.undoPlan(for: imported, in: modelContext)
        undoPlan = plan
        if plan.removable.isEmpty && plan.properties.isEmpty {
            nothingToUndo = true
        } else {
            confirmingUndo = imported
        }
    }

    private func undo(_ imported: ClientImport.Result) {
        do {
            let plan = try ClientImport.undo(imported, in: modelContext)
            guard !plan.removable.isEmpty || !plan.properties.isEmpty else {
                // Used since the question was asked (iCloud put them on a route).
                undoPlan = plan
                nothingToUndo = true
                return
            }
            let removed = [plan.removable.isEmpty ? nil : count(plan.removable.count, "client", "clients"),
                           plan.properties.isEmpty ? nil : count(plan.properties.count, "property", "properties")]
                .compactMap { $0 }.joined(separator: " and ")
            undone = "Import undone: \(removed) removed"
                + (plan.kept > 0 ? ", \(count(plan.kept, "client", "clients")) kept" : "")
            recent = ClientImport.recentImports(in: modelContext, operatorID: authManager.userID)
        } catch {
            undoFailed = true
        }
    }

    private func count(_ n: Int, _ one: String, _ many: String) -> String {
        "\(n.formatted()) \(n == 1 ? one : many)"
    }
}

/// Every row of an import, as the preview sorts it, with its spreadsheet row.
struct ImportPreviewList: View {
    let preview: ClientImport.Preview
    let table: CSVReader.Table
    /// After an import: only the rows left out, to keep (Share).
    var skippedOnly = false

    private struct Row: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let note: String?
    }

    private var groups: [(title: String, rows: [Row])] {
        var new: [Row] = [], properties: [Row] = [], duplicates: [Row] = [], samePhones: [Row] = [], problems: [Row] = []
        for (index, outcome) in preview.outcomes.enumerated() {
            let number = table.rowNumber(index)
            switch outcome {
            case let .new(draft):
                new.append(Row(id: number, title: draft.name, detail: detail(draft, number), note: nil))
            case let .samePhone(draft, other):
                samePhones.append(Row(id: number, title: draft.name, detail: detail(draft, number),
                                      note: "Same phone as \(other)"))
            case let .property(draft, owner, _):
                properties.append(Row(id: number, title: draft.address, detail: "Row \(number) · \(owner)", note: nil))
            case let .duplicate(draft, existing):
                duplicates.append(Row(id: number, title: draft.name, detail: detail(draft, number),
                                      note: existing == draft.name ? nil : "Matches \(existing)"))
            case let .problem(row, reason):
                problems.append(Row(id: row, title: "Row \(row)", detail: reason, note: nil))
            }
        }
        let all = [("Not Imported", problems), ("Another Client's Phone, Skipped", samePhones),
                   ("New Clients", new), ("Properties of Clients", properties), ("Duplicates, Skipped", duplicates)]
        let skipped: Set = ["Not Imported", "Another Client's Phone, Skipped", "Duplicates, Skipped"]
        return all.filter { !$0.1.isEmpty && (!skippedOnly || skipped.contains($0.0)) }
            .map { (title: $0.0, rows: $0.1) }
    }

    private func detail(_ draft: ClientImport.Draft, _ number: Int) -> String {
        (["Row \(number)"] + [draft.phone, draft.address].filter { !$0.isEmpty }).joined(separator: " · ")
    }

    var body: some View {
        List {
            ForEach(groups, id: \.title) { group in
                Section("\(group.title) (\(group.rows.count))") {
                    ForEach(group.rows) { row in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title).font(.subheadline)
                            Text(row.detail).font(.caption).foregroundStyle(.secondary)
                            if let note = row.note {
                                Text(note).font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(skippedOnly ? "What Was Skipped" : "Every Row")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if skippedOnly {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    /// The list as plain text, to keep or send.
    private var shareText: String {
        groups.map { group in
            ([group.title] + group.rows.map { row in
                "\(row.title): \(row.detail)" + (row.note.map { " (\($0))" } ?? "")
            }).joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
