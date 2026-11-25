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

    /// A photo of the receipt (the expense's editor), as the client's
    /// gallery stores photos: a JPEG from the camera, or a library photo's
    /// file without its location. External storage keeps the photo out of
    /// the database file; it's erased with the record. Set only through
    /// `setReceipt`.
    @Attribute(.externalStorage) var receiptData: Data? = nil
    /// When the receipt photo was taken (or added, if its file doesn't
    /// say). Set and cleared together with `receiptData` (`setReceipt`): the
    /// list's receipt mark and the Expenses file's Receipt column read this
    /// one, so neither loads the photos.
    var receiptCapturedAt: Date? = nil

    var createdAt: Date = Date()

    init(operatorID: String, date: Date = Date(), amount: Double = 0, category: ExpenseCategory = .other) {
        self.operatorID = operatorID
        self.date = date
        self.amount = amount
        self.categoryRaw = category.rawValue
    }

    /// Whether there's a receipt photo, without loading it.
    var hasReceipt: Bool { receiptCapturedAt != nil }

    /// Puts a receipt photo on the expense, or takes it off (nil): both
    /// fields together. A photo whose time isn't known is dated `now`, when
    /// it was added, so `hasReceipt` still sees it.
    func setReceipt(_ data: Data?, capturedAt: Date?, now: Date = .now) {
        receiptData = data
        receiptCapturedAt = data == nil ? nil : (capturedAt ?? now)
    }

    /// The category; one this build doesn't know (written by a newer PlowR)
    /// reads as Other.
    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}

/// The expense editor's receipt until Save: what it shows, and whether the
/// user changed it. Save writes it only when changed, since writing the same
/// photo again would send it to iCloud again; Cancel leaves the expense's
/// receipt as it was.
struct ReceiptDraft {
    private(set) var data: Data?
    private(set) var capturedAt: Date?
    private(set) var changed = false

    /// No photo yet (a new expense, or before the editor loads one).
    init() { }

    /// The expense's photo as it is (nil: a new expense).
    init(from expense: Expense?) {
        guard let expense, expense.hasReceipt, let data = expense.receiptData else { return }
        self.data = data
        capturedAt = expense.receiptCapturedAt
    }

    /// A photo taken or chosen in the editor, in place of any other.
    mutating func use(_ data: Data, capturedAt: Date?) {
        self.data = data
        self.capturedAt = capturedAt
        changed = true
    }

    /// Remove Receipt.
    mutating func remove() {
        data = nil
        capturedAt = nil
        changed = true
    }

    /// Save: puts the photo on the expense, or takes it off, only if the
    /// user changed it.
    func apply(to expense: Expense, now: Date = .now) {
        guard changed else { return }
        expense.setReceipt(data, capturedAt: capturedAt, now: now)
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
