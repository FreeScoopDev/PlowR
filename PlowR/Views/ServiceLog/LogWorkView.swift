import SwiftUI
import SwiftData

/// Logs work done for a client off a route or a scheduled visit (a call-out,
/// a job done on the way past) into their Service History.
struct LogWorkView: View {
    let client: Client

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allServices: [ServiceItem]

    @State private var performedAt = Date()
    @State private var minutes = ""
    @State private var selectedIDs: Set<String> = []
    @State private var typedPrices: [String: String] = [:]
    @State private var customItems: [StopRecording.CustomItem] = []
    @State private var keptLines: [ServiceRecord.Line] = []
    @State private var notes = ""
    @State private var showingDiscardConfirm = false

    private var services: [StopRecording.Service] {
        ServiceLog.activeServices(allServices, operatorID: client.operatorID)
    }

    private var recording: StopRecording {
        StopRecording(services: services, zones: client.pricingZones, selectedIDs: selectedIDs,
                      typedPrices: typedPrices, customItems: customItems, keptLines: keptLines)
    }

    private var hasNotes: Bool { !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var canSave: Bool { !recording.recordLines.isEmpty || hasNotes }
    private var hasChanges: Bool { !selectedIDs.isEmpty || !customItems.isEmpty || hasNotes || !minutes.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Client", value: client.name)
                    DatePicker("Done", selection: $performedAt, in: ...Date.now)
                    LabeledContent("Minutes on Site") {
                        TextField("Optional", text: $minutes)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                ServiceLinesSections(
                    services: services, zones: client.pricingZones, operatorID: client.operatorID,
                    selectedIDs: $selectedIDs, typedPrices: $typedPrices,
                    customItems: $customItems, keptLines: $keptLines)

                Section("Notes") {
                    TextField("Optional notes", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle("Log Work")
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
            .confirmationDialog("Discard this work?", isPresented: $showingDiscardConfirm, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            }
        }
    }

    private func save() {
        ServiceLog.logWork(recording, notes: notes, performedAt: performedAt,
                           minutes: Double(minutes.trimmingCharacters(in: .whitespaces)) ?? 0,
                           for: client, operatorID: client.operatorID, in: modelContext)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
