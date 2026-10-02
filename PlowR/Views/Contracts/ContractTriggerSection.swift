import SwiftData
import SwiftUI

/// A snow contract's trigger: work starts at this depth of snow. Its own
/// file, as snow-only features are, and shown only when the contract covers
/// a snow service. The Dashboard's storm card goes by it (StormWatch).
struct ContractTriggerSection: View {
    @Binding var inches: Double

    var body: some View {
        Section {
            Stepper(value: $inches, in: 0...12, step: 0.5) {
                LabeledContent("Snow Trigger", value: inches > 0 ? "\(inches.formatted()) in or more" : "Every snowfall")
            }
        } footer: {
            Text("Snow clearing starts at this depth. The Dashboard shows a storm card when the forecast reaches it.")
        }
    }
}

/// The trigger on a contract's page.
struct ContractTriggerRow: View {
    let inches: Double

    var body: some View {
        LabeledContent("Snow Trigger", value: "\(inches.formatted()) in or more")
    }
}

/// A signed snow contract's trigger and the days marked below it at the
/// client's places (TriggerCheck): from the office, or after the fact. A
/// check made at the stop on a route is listed too, and can be removed here.
struct ContractTriggerChecksSection: View {
    let contract: Contract

    @Environment(\.modelContext) private var modelContext
    @Query private var allChecks: [TriggerCheck]
    @State private var day = Date()

    /// This contract's places' marks, the newest day first.
    private var checks: [TriggerCheck] {
        allChecks.filter { $0.clientID == contract.clientID && contract.placeIDs.contains($0.placeID) }
            .sorted { ($0.day, $0.checkedAt) > ($1.day, $1.checkedAt) }
    }

    /// Days the contract covers, up to today.
    private var range: ClosedRange<Date> {
        let end = min(contract.endDate, Date())
        return min(contract.startDate, end)...end
    }

    private var places: [String] {
        TriggerChecks.contractPlaces(of: contract.clientID, on: day, contracts: [contract])
    }

    var body: some View {
        Section {
            LabeledContent("Snow Trigger",
                           value: contract.triggerInches > 0 ? "\(contract.triggerInches.formatted()) in or more" : "Every snowfall")
            DatePicker("Day", selection: $day, in: range, displayedComponents: .date)
            let marked = TriggerChecks.isMarked(contract.clientID, on: day, in: checks)
            Button(marked ? "Not Below Trigger That Day" : "Mark Below Trigger That Day") {
                if marked {
                    TriggerChecks.unmark(contract.clientID, places: contract.placeIDs, on: day, in: modelContext)
                } else {
                    TriggerChecks.mark(clientID: contract.clientID, clientName: contract.clientName, places: places,
                                       on: day, operatorID: contract.operatorID, in: modelContext)
                }
            }
            .disabled(!marked && places.isEmpty)
            ForEach(checks) { check in
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    Text(check.isFromStop
                         ? "Checked at the stop\(check.routeName.isEmpty ? "" : " on \(check.routeName)")"
                         : "Marked by hand")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !check.note.isEmpty {
                        Text(check.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        TriggerChecks.delete(check, in: modelContext)
                        try? modelContext.save()
                    }
                }
            }
        } header: {
            Text("Snow Trigger")
        } footer: {
            Text("Less fell at the property than the trigger? Mark the day: the storm card and route leave the client out, and the Service Report lists it.")
        }
    }
}
