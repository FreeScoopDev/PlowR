import SwiftUI
import SwiftData

/// Adds or changes an expense (Home → Expenses).
struct ExpenseEditView: View {
    /// nil: a new expense.
    let editing: Expense?
    let operatorID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allClients: [Client]
    @Query private var allRoutes: [PlowRoute]
    @Query private var allExpenses: [Expense]

    @State private var date: Date
    @State private var amountText: String
    @State private var category: ExpenseCategory
    @State private var item: String
    @State private var quantityText: String
    @State private var unit: String
    @State private var clientID: String
    @State private var clientName: String
    @State private var routeID: String
    @State private var routeName: String
    @State private var note: String
    @FocusState private var itemFocused: Bool
    @State private var showingDiscardConfirm = false
    @State private var showingDeleteConfirm = false

    init(editing: Expense? = nil, operatorID: String) {
        self.editing = editing
        self.operatorID = operatorID
        _date = State(initialValue: editing?.date ?? Date())
        _amountText = State(initialValue: editing.map { DecimalText.trimmed($0.amount, places: 2) } ?? "")
        _category = State(initialValue: editing?.category ?? .fuel)
        _item = State(initialValue: editing?.item ?? "")
        _quantityText = State(initialValue: editing.map { $0.quantity > 0 ? DecimalText.trimmed($0.quantity) : "" } ?? "")
        _unit = State(initialValue: editing?.unit ?? "")
        _clientID = State(initialValue: editing?.clientID ?? "")
        _clientName = State(initialValue: editing?.clientName ?? "")
        _routeID = State(initialValue: editing?.routeID ?? "")
        _routeName = State(initialValue: editing?.routeName ?? "")
        _note = State(initialValue: editing?.note ?? "")
    }

    private var amount: Double? { Expenses.amount(typed: amountText) }
    private var quantity: Double? { category == .materials ? Expenses.quantity(typed: quantityText) : 0 }
    private var canSave: Bool { amount != nil && quantity != nil }

    private var hasChanges: Bool {
        guard let editing else {
            return !amountText.isEmpty || !item.isEmpty || !note.isEmpty || !clientID.isEmpty || !routeID.isEmpty
        }
        return date != editing.date || amount != editing.amount || category != editing.category
            || item != editing.item || clientID != editing.clientID || routeID != editing.routeID
            || note != editing.note || unit != editing.unit || quantity != editing.quantity
    }

    private var suggestions: [String] {
        Array(Expenses.itemSuggestions(allExpenses, operatorID: operatorID, prefix: item).prefix(4))
    }

    private var myClients: [Client] {
        allClients.filter { $0.operatorID == operatorID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var myRoutes: [PlowRoute] {
        allRoutes.filter { $0.operatorID == operatorID }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // PlowR Pro: read only, this editor shows why instead (EditsNeedPro).
    var body: some View { editor.editsNeedPro() }

    private var editor: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                    LabeledContent("Amount") {
                        TextField(Money.text(0), text: $amountText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if !amountText.trimmingCharacters(in: .whitespaces).isEmpty, amount == nil {
                        Label("Enter an amount above zero, such as 45.20.", systemImage: PlowRSymbol.warning.name)
                            .foregroundStyle(PlowRColor.Status.overdue.text)
                    }
                    Picker("Category", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { category in
                            Label(category.title, systemImage: category.symbol.name).tag(category)
                        }
                    }
                }
                .listRowBackground(PlowRColor.surface)

                Section {
                    TextField("What (optional)", text: $item)
                        .focused($itemFocused)
                        .textInputAutocapitalization(.sentences)
                    if itemFocused {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                item = suggestion
                                itemFocused = false
                            } label: {
                                Label(suggestion, systemImage: "arrow.up.left")
                            }
                        }
                    }
                    if category == .materials {
                        LabeledContent("Quantity") {
                            TextField("Optional", text: $quantityText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                        if quantity == nil {
                            Label("Enter a number, such as 12.", systemImage: PlowRSymbol.warning.name)
                                .foregroundStyle(PlowRColor.Status.overdue.text)
                        }
                        LabeledContent("Unit") {
                            TextField("Optional", text: $unit)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                } header: {
                    SectionTitle("What")
                } footer: {
                    SectionNote("What you bought. PlowR suggests what you've typed before.")
                }
                .listRowBackground(PlowRColor.surface)

                Section(title: "For") {
                    ExpenseLinkFields(clients: myClients, routes: myRoutes, clientID: $clientID,
                                      clientName: $clientName, routeID: $routeID, routeName: $routeName)
                }
                .listRowBackground(PlowRColor.surface)

                Section(title: "Note") {
                    TextField("Optional note", text: $note, axis: .vertical)
                        .lineLimit(2...)
                }
                .listRowBackground(PlowRColor.surface)

                if editing != nil {
                    Section {
                        Button("Delete Expense", role: .destructive) { showingDeleteConfirm = true }
                    }
                    .listRowBackground(PlowRColor.surface)
                }
            }
            .plowRGrouped()
            .navigationTitle(editing == nil ? "Add Expense" : "Expense")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if hasChanges { showingDiscardConfirm = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                }
            }
            .interactiveDismissDisabled(hasChanges)
            .confirmationDialog("Discard changes?", isPresented: $showingDiscardConfirm, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            }
            .confirmationDialog(editing.map { Expenses.deleteTitle(for: $0) } ?? "",
                                isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
                Button("Delete Expense", role: .destructive, action: delete)
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This can't be undone.")
            }
        }
    }

    private func save() {
        guard let amount, let quantity else { return }
        let expense = editing ?? {
            let new = Expense(operatorID: operatorID)
            modelContext.insert(new)
            return new
        }()
        expense.date = date
        expense.amount = amount
        expense.category = category
        expense.item = item.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.quantity = category == .materials ? quantity : 0
        expense.unit = category == .materials ? unit.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        expense.clientID = clientID
        expense.clientName = clientName
        expense.routeID = routeID
        expense.routeName = routeName
        expense.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        try? modelContext.save()
        Haptics.success()
        dismiss()
    }

    private func delete() {
        guard let editing else { return }
        modelContext.delete(editing)
        try? modelContext.save()
        dismiss()
    }
}
