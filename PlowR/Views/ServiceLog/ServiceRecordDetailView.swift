import SwiftUI
import SwiftData

/// One job in the Service Log: when, how long, what was done at what price,
/// notes and photos, and where it came from. It can be corrected here; its
/// services and whether it's billable are fixed while it's on an invoice.
struct ServiceRecordDetailView: View {
    let record: ServiceRecord
    let client: Client?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allServices: [ServiceItem]

    @State private var performedAt: Date
    @State private var minutes: String
    @State private var isBillable: Bool
    @State private var notes: String
    @State private var selectedIDs: Set<String> = []
    @State private var typedPrices: [String: String] = [:]
    @State private var customItems: [StopRecording.CustomItem] = []
    @State private var keptLines: [ServiceRecord.Line] = []
    /// The form as loaded, to tell whether anything changed.
    @State private var loaded: Snapshot?
    @State private var showingDeleteConfirm = false
    /// Looked up once, on opening, not on every keystroke.
    @State private var invoice: Proposal?
    @State private var locked = false
    @State private var photos: [StopPhoto] = []
    /// The minutes field as it opened: left alone, the exact recorded time is
    /// kept rather than the whole minutes shown.
    private let minutesAsLoaded: String

    init(record: ServiceRecord, client: Client?) {
        self.record = record
        self.client = client
        _performedAt = State(initialValue: record.performedAt)
        let shown = record.minutes >= 1 ? String(Int(record.minutes.rounded())) : ""
        _minutes = State(initialValue: shown)
        minutesAsLoaded = shown
        _isBillable = State(initialValue: record.isBillable)
        _notes = State(initialValue: record.notes)
    }

    private struct Snapshot: Equatable {
        var performedAt: Date
        var minutes: String
        var isBillable: Bool
        var notes: String
        var lines: [ServiceRecord.Line]
    }

    private var snapshot: Snapshot {
        Snapshot(performedAt: performedAt, minutes: minutes, isBillable: isBillable, notes: notes,
                 lines: recording.recordLines)
    }

    private var operatorID: String { client?.operatorID ?? record.operatorID }
    private var zones: [InvoiceLines.Zone] { client?.pricingZones ?? [] }
    private var services: [StopRecording.Service] { ServiceLog.activeServices(allServices, operatorID: operatorID) }

    private var recording: StopRecording {
        StopRecording(services: services, zones: zones, selectedIDs: selectedIDs, typedPrices: typedPrices,
                      customItems: customItems, keptLines: keptLines)
    }

    private var hasChanges: Bool { loaded.map { $0 != snapshot } ?? false }

    var body: some View {
        // Deleted here: the page is on its way out and mustn't read the record.
        if record.isDeleted || record.modelContext == nil {
            Color.clear
        } else {
            form
        }
    }

    private var form: some View {
        Form {
            Section {
                DatePicker("Done", selection: $performedAt, in: ...Date.now)
                LabeledContent("Minutes on Site") {
                    TextField("None", text: $minutes)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
                Toggle("Bill for This Work", isOn: $isBillable)
                    .disabled(invoice != nil)
            } footer: {
                if let invoice {
                    Text("On invoice \(invoice.invoiceNumber).")
                } else if !isBillable {
                    Text("No charge: this work won't be billed.")
                }
            }

            ServiceLinesSections(
                services: services, zones: zones, operatorID: operatorID,
                selectedIDs: $selectedIDs, typedPrices: $typedPrices,
                customItems: $customItems, keptLines: $keptLines, locked: locked,
                footer: locked ? "On an invoice, so these are fixed. To change them, edit the invoice." : nil)

            Section("Notes") {
                TextField("Optional notes", text: $notes, axis: .vertical)
                    .lineLimit(3...)
            }

            photosSection

            Section("Details") {
                LabeledContent("Recorded From", value: sourceText)
                if !record.propertyAddress.isEmpty {
                    LabeledContent("Address", value: record.propertyAddress)
                }
                if let started = record.startedAt {
                    LabeledContent("Started") {
                        Text(started, format: .dateTime.hour().minute())
                    }
                }
            }

            if invoice == nil {
                Section {
                    Button("Delete This Job", role: .destructive) { showingDeleteConfirm = true }
                }
            }
        }
        .navigationTitle(record.performedAt.formatted(.dateTime.month(.abbreviated).day().year()))
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            if hasChanges {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                }
            }
        }
        .asksBeforeLeaving(hasChanges: hasChanges, isBusy: false, canSave: true,
                           message: "Your changes to this job aren't saved.",
                           save: save, discard: { dismiss() })
        .confirmationDialog("Delete this job?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if ServiceLog.deleteRecord(record, in: modelContext) { dismiss() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("It's removed from the Service History. Its photos stay in the client's gallery.")
        }
        .onAppear(perform: load)
    }

    @ViewBuilder
    private var photosSection: some View {
        if !photos.isEmpty {
            Section("Photos") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(photos) { photo in
                            if let image = UIImage(data: photo.imageData) {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .accessibilityLabel(photo.isBefore ? "Before photo" : "After photo")
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .bottomLeading) {
                                        Text(photo.isBefore ? "Before" : "After")
                                            .font(.system(size: 9, weight: .semibold))
                                            .padding(.horizontal, 5).padding(.vertical, 2)
                                            .background(photo.isBefore ? Color.orange.opacity(0.85)
                                                                       : Color.green.opacity(0.85))
                                            .foregroundStyle(.white)
                                            .clipShape(Capsule())
                                            .padding(4)
                                    }
                            }
                        }
                    }
                }
            }
        }
    }

    private var sourceText: String {
        switch record.source {
        case .route: record.routeName.isEmpty ? "A route" : "Route: \(record.routeName)"
        case .visit: "A scheduled visit"
        case .manual: "Logged by hand"
        }
    }

    /// The services as the record has them (StopRecording.loading), once.
    private func load() {
        guard loaded == nil else { return }
        invoice = ServiceLog.invoice(of: record, in: modelContext)
        locked = ServiceLog.servicesLocked(record, in: modelContext)
        photos = ServiceLog.photos(of: record, in: modelContext)
        let form = StopRecording.loading(record.lines, services: services, zones: zones)
        selectedIDs = form.selectedIDs
        typedPrices = form.typedPrices
        customItems = form.customItems
        keptLines = form.keptLines
        loaded = snapshot
    }

    private func save() {
        ServiceLog.update(record, lines: recording.recordLines, notes: notes, performedAt: performedAt,
                          minutes: minutes == minutesAsLoaded
                              ? record.minutes : Double(minutes.trimmingCharacters(in: .whitespaces)) ?? 0,
                          isBillable: isBillable, in: modelContext)
        loaded = snapshot
        dismiss()
    }
}
