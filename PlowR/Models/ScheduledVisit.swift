import Foundation
import SwiftData
import SwiftUI

@Model
final class ScheduledVisit {
    var id: UUID = UUID()
    var operatorID: String = ""
    var clientID: String = ""
    var clientName: String = ""
    var clientAddress: String = ""
    var scheduledDate: Date = Date()
    var estimatedMinutes: Int = 0
    var statusRaw: String = VisitStatus.scheduled.rawValue
    var notes: String = ""
    var visitReason: String = ""              // preset or custom reason for the visit
    var expectedServiceIDs: [String] = []    // service catalog item IDs expected this visit
    var completedAt: Date? = nil
    var proposalID: String = ""    // invoice generated from this visit
    var isAfterHours: Bool = false
    var afterHoursMultiplier: Double = 1.5

    // Recurrence — all visits in a series share seriesID
    var isRecurring: Bool = false
    var recurrenceTypeRaw: String = RecurrenceType.weekly.rawValue
    var recurrenceInterval: Int = 1           // every N units
    var recurrenceWeekdays: [Int] = []        // weekday numbers (1=Sun … 7=Sat) for weekly
    var recurrenceEndDate: Date? = nil
    var seriesID: String = ""                 // groups all visits in a recurring series

    var status: VisitStatus {
        get { VisitStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    var recurrenceType: RecurrenceType {
        get { RecurrenceType(rawValue: recurrenceTypeRaw) ?? .weekly }
        set { recurrenceTypeRaw = newValue.rawValue }
    }

    var isPast: Bool { scheduledDate < Date() && status == .scheduled }

    init(operatorID: String, clientID: String, clientName: String,
         clientAddress: String, scheduledDate: Date) {
        self.operatorID = operatorID
        self.clientID = clientID
        self.clientName = clientName
        self.clientAddress = clientAddress
        self.scheduledDate = scheduledDate
        self.seriesID = UUID().uuidString
    }

    // Generate the next occurrence date based on recurrence settings
    func nextOccurrence(after date: Date) -> Date? {
        guard isRecurring else { return nil }

        if recurrenceType == .weekly && !recurrenceWeekdays.isEmpty {
            return nextWeekdayOccurrence(after: date)
        }

        var components = DateComponents()
        switch recurrenceType {
        case .daily:    components.day = recurrenceInterval
        case .weekly:   components.weekOfYear = recurrenceInterval
        case .biweekly: components.weekOfYear = 2
        case .monthly:  components.month = recurrenceInterval
        }
        let next = Calendar.current.date(byAdding: components, to: date) ?? date
        if let end = recurrenceEndDate, next > end { return nil }
        return next
    }

    // For weekly recurrence with specific weekdays: find the next matching day.
    // If a later weekday exists in the same week (interval == 1), use it.
    // Otherwise advance N weeks from the current week's Sunday and use the first weekday.
    private func nextWeekdayOccurrence(after date: Date) -> Date? {
        let cal = Calendar.current
        let sorted = recurrenceWeekdays.sorted()
        let currentWeekday = cal.component(.weekday, from: date)

        if recurrenceInterval == 1, let nextWD = sorted.first(where: { $0 > currentWeekday }) {
            let candidate = cal.date(byAdding: .day, value: nextWD - currentWeekday, to: date)
            if let end = recurrenceEndDate, let c = candidate, c > end { return nil }
            return candidate
        }

        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: date)?.start,
              let targetStart = cal.date(byAdding: .weekOfYear, value: recurrenceInterval, to: weekStart),
              let firstWD = sorted.first else { return nil }

        // Calendar weekday 1 = Sunday = offset 0 from week start
        let candidate = cal.date(byAdding: .day, value: firstWD - 1, to: targetStart)
        if let end = recurrenceEndDate, let c = candidate, c > end { return nil }
        return candidate
    }
}

enum VisitStatus: String, CaseIterable {
    case scheduled = "Scheduled"
    case completed = "Completed"
    case cancelled = "Cancelled"
    case skipped   = "Skipped"

    var systemImage: String {
        switch self {
        case .scheduled: return "calendar.circle"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle.fill"
        case .skipped:   return "arrow.right.circle.fill"
        }
    }

    var chipColor: Color {
        switch self {
        case .scheduled: return .blue
        case .completed: return .green
        case .cancelled: return .red
        case .skipped:   return .orange
        }
    }
}

enum RecurrenceType: String, CaseIterable {
    case daily    = "Daily"
    case weekly   = "Weekly"
    case biweekly = "Every 2 Weeks"
    case monthly  = "Monthly"
}
