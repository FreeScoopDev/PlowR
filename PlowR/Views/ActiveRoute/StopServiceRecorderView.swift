import SwiftUI
import SwiftData
import PhotosUI

/// Record Services: what was done at a stop, with photos and notes, saved to
/// the Service Log, and optionally invoiced. It used to save only by making an
/// invoice, and Skip threw away any photos just taken.
struct StopServiceRecorderView: View {
    let stop: RouteStop
    let client: Client?
    let operatorID: String
    /// The route run (ActiveRouteStore.runID), so this writes to the record
    /// that completing the stop fills in. A sheet opened without one gets
    /// its own, kept (as state) for as long as it's open.
    @State private var runID: UUID
    /// When the stop was started, if it's the current one: which day's
    /// visit it is doesn't change if the sheet is saved after midnight.
    @State private var stopStartedAt: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allServices: [ServiceItem]

    @State private var selectedServiceIDs: Set<String>
    @State private var notes: String
    @State private var servicePriceOverrides: [String: String] = [:]
    @State private var customItems: [StopRecording.CustomItem] = []
    /// Recorded services no longer in the active catalog (StopRecording.keptLines).
    @State private var keptLines: [ServiceRecord.Line] = []

    // Photos
    @State private var beforePickerItems: [PhotosPickerItem] = []
    @State private var afterPickerItems: [PhotosPickerItem] = []
    /// Each with when it was taken (PhotoCapture).
    @State private var beforeImages: [CapturedPhoto] = []
    @State private var afterImages: [CapturedPhoto] = []
    @State private var showingCamera = false
    @State private var cameraIsBefore = true

    /// The invoice this stop's work is already on, if any (its number).
    @State private var invoicedAs: String?
    /// The saved record is on an invoice and has services: they're fixed.
    @State private var servicesLocked = false
    /// There's a saved record, so saving an emptied sheet clears it.
    @State private var hadRecord = false
    @State private var showingDiscardConfirm = false
    /// What was on screen once the saved record was loaded: Skip asks only
    /// if something differs from it.
    @State private var saved: Snapshot?

    init(stop: RouteStop, client: Client?, operatorID: String, runID: UUID?, stopStartedAt: Date? = nil) {
        self.stop = stop
        self.client = client
        self.operatorID = operatorID
        _runID = State(initialValue: runID ?? UUID())
        _stopStartedAt = State(initialValue: stopStartedAt ?? Date())
        _selectedServiceIDs = State(initialValue: Set(stop.completedServiceIDs))
        _notes = State(initialValue: stop.completedNotes)
    }

    private struct Snapshot: Equatable {
        var services: Set<String>
        var prices: [String: String]
        var custom: [String]
        var kept: [String]
        var notes: String
    }

    private var snapshot: Snapshot {
        Snapshot(services: selectedServiceIDs,
                 prices: servicePriceOverrides.filter { selectedServiceIDs.contains($0.key) },
                 custom: customItems.map { "\($0.name)|\($0.price)" },
                 kept: keptLines.map(\.serviceID), notes: notes)
    }

    /// Everything on screen, priced the one way the log and the invoice share.
    private var recording: StopRecording {
        StopRecording(
            services: myServices,
            zones: pricingZones,
            selectedIDs: selectedServiceIDs,
            typedPrices: servicePriceOverrides,
            customItems: customItems,
            keptLines: keptLines)
    }

    /// Something Skip, or swiping the sheet away, would lose: photos, or a
    /// service, price, custom item or note changed since it was loaded.
    private var hasUnsavedWork: Bool {
        !beforeImages.isEmpty || !afterImages.isEmpty || (saved.map { $0 != snapshot } ?? false)
    }

    /// Anything to save: an empty sheet would only make an empty record,
    /// unless it empties a saved one (services recorded at the wrong stop).
    private var hasAnythingToSave: Bool {
        !selectedServiceIDs.isEmpty || !recording.recordLines.isEmpty || !beforeImages.isEmpty
            || !afterImages.isEmpty || !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (hadRecord && hasUnsavedWork)
    }

    /// Expected at this stop (StopServices), in the catalog, and not ticked.
    private var expectedToAdd: [StopRecording.Service] {
        let expected = Set(StopServices.expected(for: stop, client: client))
        return myServices.filter { expected.contains($0.id) && !selectedServiceIDs.contains($0.id) }
    }

    private var myServices: [StopRecording.Service] {
        ServiceLog.activeServices(allServices, operatorID: operatorID)
    }

    /// The contract covering this stop on the day it started, as billing
    /// will find it (Contracts.contract(coveringPlace:)).
    private func coveringContract(_ client: Client) -> Contract? {
        Contracts.contract(coveringPlace: Place.id(of: client, propertyID: stop.propertyID), of: client.id.uuidString,
                           on: stopStartedAt, among: Contracts.all(in: modelContext))
    }

    /// What an invoice made here would bill: under the stop's contract.
    private var invoiceLines: [InvoiceLines.Line] {
        recording.invoiceLines(under: client.flatMap { coveringContract($0) })
    }

    /// What the contract means for what's recorded here, as Bill Unbilled
    /// Work will bill it (ServiceLog.charge).
    private func contractNote(_ contract: Contract) -> String {
        switch Contracts.pricing(of: contract) {
        case .season, .monthly:
            "The services it covers aren't billed by the visit, and aren't put on an invoice from here. Others are billed as extras."
        case .perVisit:
            "The services it covers are billed at \(contract.price.formatted(.currency(code: "USD"))) a visit, here and in Bill Unbilled Work."
        }
    }

    private var pricingZones: [InvoiceLines.Zone] {
        client.flatMap { Place.of($0, propertyID: stop.propertyID)?.zones } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                if let client {
                    Section {
                        LabeledContent("Client", value: client.name)
                        // The stop's: its place's address, which may be a property's.
                        if !stop.clientAddress.isEmpty {
                            LabeledContent("Address", value: stop.clientAddress)
                        }
                        if let contract = coveringContract(client) {
                            LabeledContent("Contract", value: contract.name)
                            Text(contractNote(contract))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                photoSection(isBefore: true)
                photoSection(isBefore: false)

                // The stop's expected services, one tap to tick, never ticked
                // for you: a skipped or cleared stop mustn't record (and bill)
                // work that wasn't done.
                if !servicesLocked, !expectedToAdd.isEmpty {
                    Section {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            expectedToAdd.forEach { selectedServiceIDs.insert($0.id) }
                        } label: {
                            Label("Add Expected: \(expectedToAdd.map(\.name).formatted(.list(type: .and)))",
                                  systemImage: "checklist")
                        }
                    }
                }

                ServiceLinesSections(
                    services: recording.services, zones: pricingZones, operatorID: operatorID,
                    selectedIDs: $selectedServiceIDs, typedPrices: $servicePriceOverrides,
                    customItems: $customItems, keptLines: $keptLines, locked: servicesLocked,
                    footer: invoicedAs.map { number in
                        servicesLocked
                            ? "On invoice \(number), so these services are fixed. To change them, edit the invoice."
                            : "Invoice \(number) was already made for this visit."
                    })

                Section("Notes") {
                    TextField("Optional notes for this stop…", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
            }
            .navigationTitle("Record Services")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        if hasUnsavedWork { showingDiscardConfirm = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu("Save") {
                        Button {
                            save(invoice: .none)
                        } label: {
                            Label("Save", systemImage: "checkmark.circle")
                        }
                        if invoicedAs == nil {
                            Button {
                                save(invoice: .draft)
                            } label: {
                                Label("Save & Draft Invoice", systemImage: "doc.badge.clock")
                            }
                            .disabled(invoiceLines.isEmpty)
                            Button {
                                save(invoice: .sent)
                            } label: {
                                Label("Save & Mark Invoice Sent", systemImage: "paperplane.fill")
                            }
                            .disabled(invoiceLines.isEmpty)
                        }
                    }
                    .disabled(client == nil || !hasAnythingToSave)
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPicker { image, metadata in
                    let photo = PhotoCapture.fromCamera(image, metadata: metadata)
                    if cameraIsBefore { beforeImages.append(photo) } else { afterImages.append(photo) }
                }
            }
            .confirmationDialog("Discard what you recorded?", isPresented: $showingDiscardConfirm,
                                titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) { }
            } message: {
                Text("Photos, services and notes you haven't saved will be lost.")
            }
            .interactiveDismissDisabled(hasUnsavedWork)
            .onAppear(perform: loadRecord)
            .onChange(of: beforePickerItems) { _, items in
                loadImages(from: items) { beforeImages.append($0) }
                beforePickerItems = []
            }
            .onChange(of: afterPickerItems) { _, items in
                loadImages(from: items) { afterImages.append($0) }
                afterPickerItems = []
            }
        }
    }

    // MARK: - Photo Section

    @ViewBuilder
    private func photoSection(isBefore: Bool) -> some View {
        let images = isBefore ? beforeImages : afterImages
        let label = isBefore ? "Before Photos" : "After Photos"
        let color: Color = isBefore ? .orange : .green

        Section(label) {
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(images.indices, id: \.self) { idx in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: images[idx].image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerSmall, style: .continuous))
                                Button {
                                    if isBefore { beforeImages.remove(at: idx) }
                                    else { afterImages.remove(at: idx) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.white)
                                        .background(Color.black.opacity(0.4))
                                        .clipShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }

            HStack(spacing: 12) {
                // No camera (an iPad without one, a Mac): asking for it crashes.
                if CameraPicker.isAvailable {
                    Button {
                        cameraIsBefore = isBefore
                        showingCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(color.opacity(0.1))
                            .foregroundStyle(color)
                            .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerSmall, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                PhotosPicker(
                    selection: isBefore ? $beforePickerItems : $afterPickerItems,
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    Label("Library", systemImage: "photo")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(color.opacity(0.1))
                        .foregroundStyle(color)
                        .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerSmall, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Image Loading

    /// Library photos, each with the time it was taken (its EXIF), read
    /// before it's turned into an image, which drops that.
    private func loadImages(from items: [PhotosPickerItem], appending: @escaping (CapturedPhoto) -> Void) {
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data) = result, let data, let photo = PhotoCapture.fromLibrary(data) {
                    DispatchQueue.main.async { appending(photo) }
                }
            }
        }
    }

    // MARK: - Save

    private enum InvoiceChoice { case none, draft, sent }

    /// What was saved before: the prices typed and the custom items, which
    /// the stop alone doesn't keep, and whether it's invoiced already.
    private func loadRecord() {
        defer { if saved == nil { saved = snapshot } }
        guard saved == nil, let client else { return }
        invoicedAs = ServiceLog.invoiceForStop(stop, of: client, run: runID, startedAt: stopStartedAt,
                                               in: modelContext)?.invoiceNumber
        guard let record = ServiceLog.existingRecordForStop(stop, of: client, run: runID, startedAt: stopStartedAt,
                                                            in: modelContext)
        else { return }
        hadRecord = true
        servicesLocked = ServiceLog.servicesLocked(record, in: modelContext)
        if notes.isEmpty { notes = record.notes }
        guard !record.lines.isEmpty else { return }
        // Everything the record has, as it was: a record made elsewhere (the
        // visit completed in the Schedule) has services the stop doesn't, and
        // saving without them would erase them.
        let loaded = StopRecording.loading(record.lines, services: recording.services, zones: pricingZones)
        selectedServiceIDs = loaded.selectedIDs
        servicePriceOverrides = loaded.typedPrices
        customItems = loaded.customItems
        keptLines = loaded.keptLines
    }

    private func save(invoice choice: InvoiceChoice) {
        guard let client else { dismiss(); return }
        let recording = recording
        let record = ServiceLog.saveRecording(recording, notes: notes, for: stop, of: client, run: runID,
                                              operatorID: operatorID, startedAt: stopStartedAt, in: modelContext)

        let clientID = client.id.uuidString
        let routeID = stop.route?.id.uuidString ?? ""
        for (images, isBefore) in [(beforeImages, true), (afterImages, false)] {
            for captured in images {
                guard let photo = StopPhoto.make(from: captured, isBefore: isBefore, operatorID: operatorID,
                                                 clientID: clientID, routeID: routeID,
                                                 recordID: record.id.uuidString) else { continue }
                modelContext.insert(photo)
            }
        }

        // Billed as its contract says: nothing for work it covers, its price per visit.
        let lines = invoiceLines
        if choice != .none, ServiceLog.invoice(of: record, in: modelContext) == nil, !lines.isEmpty {
            let proposal = ServiceLog.invoice(record, lines: lines, client: client,
                                              operatorID: operatorID, notes: notes, in: modelContext)
            if choice == .sent {
                DocumentSent.markSent(proposal, in: modelContext)
            }
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
