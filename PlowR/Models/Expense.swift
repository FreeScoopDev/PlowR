import Foundation
import SwiftData

/// Money the business spent: fuel, materials, equipment and repairs, or
/// anything else. Logged by hand from Home's Expenses, kept for tax time and
/// exported for an accountant (CSVExport.expenses).
///
/// Like ServiceRecord, it refers to a client and a route by ID and keeps a
/// copy of their names, with no relationship: an expense outlives a deleted
/// client or route, needs no inverse, and ClientRemoval never touches it.
///
/// Every field has a default and none is unique, as CloudKit needs.
@Model
final class Expense {
    var id: UUID = UUID()
    var operatorID: String = ""
    /// The day it was bought.
    var date: Date = Date()
    /// To the cent (Expenses.amount).
    var amount: Double = 0
    /// An ExpenseCategory's raw value; read through `category`.
    var categoryRaw: String = "other"
    /// What was bought, as the user typed it. Suggestions come only from this
    /// business's own earlier items (Expenses.itemSuggestions): PlowR names
    /// no materials, so shared screens stay the same for every kind of work.
    var item: String = ""
    /// How much of it, for materials; 0 when not given.
    var quantity: Double = 0
    /// The quantity's unit, as typed ("bags", "yd").
    var unit: String = ""
    var note: String = ""

    /// The client it was for, if any, and a copy of their name then.
    var clientID: String = ""
    var clientName: String = ""
    /// The route it was for, if any, and a copy of its name then.
    var routeID: String = ""
    var routeName: String = ""

    /// A photo of the receipt. Not used yet: the receipts change takes and
    /// shows it. Here now so iCloud's schema gets every field in one deploy.
    /// External storage keeps the photo out of the database file; it's
    /// erased with the record.
    @Attribute(.externalStorage) var receiptData: Data? = nil
    /// When the receipt photo was taken. Used with `receiptData`, in the
    /// receipts change.
    var receiptCapturedAt: Date? = nil

    var createdAt: Date = Date()

    init(operatorID: String, date: Date = Date(), amount: Double = 0, category: ExpenseCategory = .other) {
        self.operatorID = operatorID
        self.date = date
        self.amount = amount
        self.categoryRaw = category.rawValue
    }

    /// The category; one this build doesn't know (written by a newer PlowR)
    /// reads as Other.
    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

/// What an expense was for. Neutral across snow, lawn and landscaping work:
/// what was bought is the expense's own `item`.
nonisolated enum ExpenseCategory: String, CaseIterable, Identifiable {
    case fuel, materials, equipment, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fuel: "Fuel"
        case .materials: "Materials"
        case .equipment: "Equipment & Repairs"
        case .other: "Other"
        }
    }

    var symbol: PlowRSymbol {
        switch self {
        case .fuel: .fuel
        case .materials: .materials
        case .equipment: .equipment
        case .other: .otherExpense
        }
    }
}
