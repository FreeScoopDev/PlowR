import SwiftData
import SwiftUI

/// A snow contract's trigger: work starts at this depth of snow. Its own
/// file, as snow-only features are, and shown only when the contract covers
/// a snow service. The Dashboard's storm card goes by it (StormWatch).
struct ContractTriggerSection: View {
    @Binding var inches: Double
    @Environment(\.access) private var access
    @State private var gate: ProGate?

    private var value: String { inches > 0 ? "\(inches.formatted()) in or more" : "Every snowfall" }

    var body: some View {
        Section {
            // A PlowR Pro tool: without Pro the setting shows, and says why it can't change.
            if let blocked = ProGate.proFeature("The snow trigger", access) {
                Button { gate = blocked } label: {
                    LabeledContent("Snow Trigger", value: value)
                }
                .foregroundStyle(.primary)
            } else {
                Stepper(value: $inches, in: 0...12, step: 0.5) {
                    LabeledContent("Snow Trigger", value: value)
                }
            }
        } footer: {
            Text("Snow clearing starts at this depth. The Dashboard shows a storm card when the forecast reaches it.")
        }
        .proGateSheet($gate)
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
/// check made at the stop on a route is listed too; it's the crew's record,
/// with photos, so removing one asks first.
struct ContractTriggerChecksSection: View {
    let contract: Contract

    @Environment(\.modelContext) private var modelContext
    @Environment(\.access) private var access
    @State private var gate: ProGate?
    @Query private var allChecks: [TriggerCheck]
    @Query private var allServices: [ServiceItem]
    @State private var day = Date()
    @State private var removing: TriggerCheck?

    /// This contract's places' marks, the newest day first.
    private var checks: [TriggerCheck] {
        allChecks.filter { $0.clientID == contract.clientID && contract.placeIDs.contains($0.placeID) }
            .sorted { ($0.day, $0.checkedAt) > ($1.day, $1.checkedAt) }
    }

    /// Days the contract covers, up to today; nil before it starts.
    private var range: ClosedRange<Date>? {
        let end = min(contract.endDate, Date())
        guard contract.startDate <= end else { return nil }
        return contract.startDate...end
    }

    private var places: [String] {
        TriggerChecks.contractPlaces(of: contract.clientID, on: day, contracts: [contract], services: allServices)
    }

    var body: some View {
        Section {
            LabeledContent("Snow Trigger",
                           value: contract.triggerInches > 0 ? "\(contract.triggerInches.formatted()) in or more" : "Every snowfall")
            if let range {
                DatePicker("Day", selection: $day, in: range, displayedComponents: .date)
                let sameDay = checks.filter { Calendar.current.isDate($0.day, inSameDayAs: day) }
                // Places not yet marked that day (one may be checked at the stop already).
                let unmarked = places.filter { place in !sameDay.contains { $0.placeID == place } }
                if !unmarked.isEmpty {
                    Button(sameDay.isEmpty ? "Mark Below Trigger That Day" : "Mark Its Other Places That Day") {
                        // Marking is a PlowR Pro tool; removing a mark never is.
                        $gate.unless(ProGate.proFeature("Marking below trigger", access)) {
                            TriggerChecks.mark(clientID: contract.clientID, clientName: contract.clientName,
                                               places: unmarked, on: day, operatorID: contract.operatorID, in: modelContext)
                        }
                    }
                }
                if sameDay.contains(where: { !$0.isFromStop }) {
                    Button("Remove the Marks by Hand That Day") {
                        TriggerChecks.unmark(contract.clientID, places: contract.placeIDs, on: day, in: modelContext)
                    }
                }
            }
            ForEach(checks) { check in
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()))
                    Text(check.isFromStop
                         ? "Checked on a route\(check.routeName.isEmpty ? "" : " (\(check.routeName))")"
                         : "Marked by hand")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !check.note.isEmpty {
                        Text(check.note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        if check.isFromStop {
                            removing = check
                        } else {
                            TriggerChecks.delete(check, in: modelContext)
                            try? modelContext.save()
                        }
                    }
                }
            }
        } header: {
            Text("Snow Trigger")
        } footer: {
            Text(range == nil
                 ? "Days below the trigger can be marked once the contract starts."
                 : "Less fell at the property than the trigger? Mark the day: the storm card and route leave the client out, and the Service Report lists it.")
        }
        .proGateSheet($gate)
        .onAppear {
            // Start on a day the picker offers: an ended contract's last day.
            if let range, !range.contains(day) { day = range.upperBound }
        }
        .confirmationDialog("Remove this check?", isPresented: Binding(get: { removing != nil },
                                                                        set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove Check and Photos", role: .destructive) {
                if let removing {
                    TriggerChecks.delete(removing, in: modelContext)
                    try? modelContext.save()
                }
                removing = nil
            }
            Button("Keep", role: .cancel) { removing = nil }
        } message: {
            Text("It was made at the stop on a route, with its photos. It comes off every device and the Service Report.")
        }
    }
}
