import SwiftUI
import SwiftData

/// Home → Expenses: money spent (fuel, materials, equipment and repairs)
/// and the mileage log, by month, for tax time. Viewing and deleting are
/// never gated; adding asks ProGate.edit, so only a read-only plan is
/// stopped. Settings → Export Data has both as spreadsheets.
struct ExpensesView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case expenses = "Expenses"
        case mileage = "Mileage"
        var id: String { rawValue }
    }

    /// What the sheet is editing.
    enum Editor: Identifiable {
        case newExpense, newTrip
        case expense(Expense)
        case trip(MileageEntry)

        var id: String {
            switch self {
            case .newExpense: "newExpense"
            case .newTrip: "newTrip"
            case .expense(let expense): "expense-\(expense.id)"
            case .trip(let entry): "trip-\(entry.id)"
            }
        }
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(AuthManager.self) private var authManager
    @Environment(\.access) private var access
    @Query private var allExpenses: [Expense]
    @Query private var allTrips: [MileageEntry]

    @State private var tab: Tab = .expenses
    @State private var editor: Editor?
    @State private var gate: ProGate?
    @State private var expenseToDelete: Expense?
    @State private var tripToDelete: MileageEntry?

    private var operatorID: String { authManager.userID }
    private var myExpenses: [Expense] { allExpenses.filter { $0.operatorID == operatorID } }
    private var myTrips: [MileageEntry] { allTrips.filter { $0.operatorID == operatorID } }
    private var distanceUnit: DistanceUnit { DistanceUnit.default(for: .current) }

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets())
            }
            .listRowBackground(Color.clear)

            switch tab {
            case .expenses: expenseSections
            case .mileage: tripSections
            }
            // In the list, below the picker, so the picker stays usable.
            if tab == .expenses ? myExpenses.isEmpty : myTrips.isEmpty {
                Section { emptyState }
                    .listRowBackground(Color.clear)
            }
        }
        .plowRGrouped()
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HelpToolbarButton(screen: .home)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { add(.newExpense) } label: {
                        Label("Add Expense", systemImage: PlowRSymbol.expense.name)
                    }
                    Button { add(.newTrip) } label: {
                        Label("Log Mileage", systemImage: PlowRSymbol.mileage.name)
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { editor in
            switch editor {
            case .newExpense: ExpenseEditView(operatorID: operatorID)
            case .newTrip: MileageEditView(operatorID: operatorID)
            case .expense(let expense): ExpenseEditView(editing: expense, operatorID: operatorID)
            case .trip(let entry): MileageEditView(editing: entry, operatorID: operatorID)
            }
        }
        .proGateSheet($gate)
        .confirmationDialog(expenseToDelete.map { Expenses.deleteTitle(for: $0) } ?? "",
                            isPresented: Binding(get: { expenseToDelete != nil },
                                                 set: { if !$0 { expenseToDelete = nil } }),
                            titleVisibility: .visible, presenting: expenseToDelete) { expense in
            Button("Delete Expense", role: .destructive) { delete(expense) }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("This can't be undone.")
        }
        .confirmationDialog(tripToDelete.map { Mileage.deleteTitle(for: $0) } ?? "",
                            isPresented: Binding(get: { tripToDelete != nil },
                                                 set: { if !$0 { tripToDelete = nil } }),
                            titleVisibility: .visible, presenting: tripToDelete) { entry in
            Button("Delete Trip", role: .destructive) { delete(entry) }
            Button("Cancel", role: .cancel) { }
        } message: { _ in
            Text("This can't be undone.")
        }
    }

    // MARK: - Expenses

    @ViewBuilder private var expenseSections: some View {
        ForEach(Expenses.byMonth(myExpenses, date: \.date, made: \.createdAt), id: \.month) { group in
            Section {
                ForEach(group.items) { expense in
                    Button { editor = .expense(expense) } label: { expenseRow(expense) }
                        .swipeActions(edge: .trailing) {
                            // Not role: .destructive, which slides the row away
                            // before the confirmation is answered.
                            Button { expenseToDelete = expense } label: {
                                Label("Delete", systemImage: PlowRSymbol.delete.name)
                            }
                            .tint(.red)
                        }
                }
            } header: {
                monthHeader(group.month, total: Money.text(Expenses.total(group.items)))
            }
            .listRowBackground(PlowRColor.surface)
        }
    }

    private func expenseRow(_ expense: Expense) -> some View {
        HStack(spacing: PlowRLayout.space3) {
            IconRow {
                IconBadge(systemImage: expense.category.symbol.name, size: 32)
            } content: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Expenses.name(of: expense))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlowRColor.ink)
                    Text(detail(date: expense.date, clientName: expense.clientName, routeName: expense.routeName))
                        .font(.caption)
                        .foregroundStyle(PlowRColor.inkSecondary)
                }
            }
            Spacer(minLength: PlowRLayout.space2)
            Text(Money.text(expense.amount))
                .font(PlowRFont.number)
                .foregroundStyle(PlowRColor.ink)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mileage

    @ViewBuilder private var tripSections: some View {
        ForEach(Expenses.byMonth(myTrips, date: \.date, made: \.createdAt), id: \.month) { group in
            Section {
                ForEach(group.items) { entry in
                    Button { editor = .trip(entry) } label: { tripRow(entry) }
                        .swipeActions(edge: .trailing) {
                            Button { tripToDelete = entry } label: {
                                Label("Delete", systemImage: PlowRSymbol.delete.name)
                            }
                            .tint(.red)
                        }
                }
            } header: {
                monthHeader(group.month,
                            total: Mileage.text(Mileage.total(group.items, in: distanceUnit), unit: distanceUnit))
            }
            .listRowBackground(PlowRColor.surface)
        }
    }

    private func tripRow(_ entry: MileageEntry) -> some View {
        HStack(spacing: PlowRLayout.space3) {
            IconRow {
                IconBadge(systemImage: PlowRSymbol.mileage.name, size: 32)
            } content: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.purpose.isEmpty ? "Trip" : entry.purpose)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(PlowRColor.ink)
                    Text(detail(date: entry.date, clientName: entry.clientName, routeName: entry.routeName))
                        .font(.caption)
                        .foregroundStyle(PlowRColor.inkSecondary)
                }
            }
            Spacer(minLength: PlowRLayout.space2)
            Text(Mileage.text(entry.distance, unit: entry.unit))
                .font(PlowRFont.number)
                .foregroundStyle(PlowRColor.ink)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    // MARK: - Shared

    /// "Nov 24 · Main Street Route": the day, then the route or the client.
    private func detail(date: Date, clientName: String, routeName: String) -> String {
        let day = date.formatted(.dateTime.month(.abbreviated).day())
        let link = [routeName, clientName].filter { !$0.isEmpty }.joined(separator: " · ")
        return link.isEmpty ? day : "\(day) · \(link)"
    }

    private func monthHeader(_ month: Date, total: String) -> some View {
        HStack {
            Text(Expenses.monthTitle(month))
            Spacer()
            Text(total)
        }
        .foregroundStyle(PlowRColor.inkSecondary)
    }

    @ViewBuilder private var emptyState: some View {
        switch tab {
        case .expenses:
            ContentUnavailableView {
                Label("No Expenses Yet", systemImage: PlowRSymbol.expense.name)
            } description: {
                Text("Log fuel, materials, equipment and repairs as you buy them. Export them for tax time from Settings → Export Data.")
            } actions: {
                Button("Add Expense") { add(.newExpense) }
                    .plowRProminent()
            }
        case .mileage:
            ContentUnavailableView {
                Label("No Mileage Yet", systemImage: PlowRSymbol.mileage.name)
            } description: {
                Text("Log the distance and purpose of each business trip. PlowR doesn't track mileage by GPS.")
            } actions: {
                Button("Log Mileage") { add(.newTrip) }
                    .plowRProminent()
            }
        }
    }

    private func add(_ new: Editor) {
        $gate.unless(ProGate.edit(access)) { editor = new }
    }

    private func delete(_ expense: Expense) {
        modelContext.delete(expense)
        try? modelContext.save()
    }

    private func delete(_ entry: MileageEntry) {
        modelContext.delete(entry)
        try? modelContext.save()
    }
}
