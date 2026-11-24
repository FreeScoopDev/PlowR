import SwiftUI
import SwiftData
import PhotosUI

/// Record Services: what was done at a stop, with photos and notes, saved to
/// the Service Log, and optionally invoiced. It used to save only by making an
/// invoice, and Skip threw away any photos just taken.
///
/// A scheduled visit (the visit sheet, VisitSheet) records through the same
/// sheet: `init(visit:client:operatorID:invoiceOnSave:onSave:)`. Visit mode
/// differs only in where the address, zones, contract, expected services and
/// record come from, saving through `ServiceLog.saveVisitRecording`, and its
/// expected services starting ticked. A stop works exactly as before.
struct StopServiceRecorderView: View {
    @Environment(\.access) private var access
    /// What's being recorded: a route stop, or a visit done off a route.
    enum Subject {
        case stop(RouteStop)
        case visit(ScheduledVisit)
    }

    /// What a visit-mode save did, for the visit sheet to show.
    enum VisitSaveOutcome {
        case saved
        /// A draft invoice was made (`invoiceOnSave`): open it.
        case invoiced(Proposal)
        /// `invoiceOnSave`, but nothing to bill: the work is saved. The
        /// covering contract's name, if one covers it.
        case nothingToBill(contractName: String?)
    }

    let subject: Subject
    let client: Client?
    let operatorID: String
    /// Visit mode: the confirm button saves, completes and drafts the
    /// invoice (Complete & Invoice, Invoice Work).
    private let invoiceOnSave: Bool
    private let onVisitSave: ((VisitSaveOutcome) -> Void)?
    /// The route run (ActiveRouteStore.runID), so this writes to the record
    /// that completing the stop fills in. A sheet opened without one gets
    /// its own, kept (as state) for as long as it's open.
    @State private var runID: UUID
    /// When the stop was started, if it's the current one: which day's
    /// visit it is doesn't change if the sheet is saved after midnight.
    @State private var stopStartedAt: Date

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
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
        self.subject = .stop(stop)
        self.client = client
        self.operatorID = operatorID
        invoiceOnSave = false
        onVisitSave = nil
        _runID = State(initialValue: runID ?? UUID())
        _stopStartedAt = State(initialValue: stopStartedAt ?? Date())
        _selectedServiceIDs = State(initialValue: Set(stop.completedServiceIDs))
        _notes = State(initialValue: stop.completedNotes)
    }

    /// Record Services for a visit. `invoiceOnSave`: Complete & Invoice or
    /// Invoice Work, whose one button saves and drafts the invoice.
    init(visit: ScheduledVisit, client: Client?, operatorID: String, invoiceOnSave: Bool = false,
         onSave: ((VisitSaveOutcome) -> Void)? = nil) {
        self.subject = .visit(visit)
        self.client = client
        self.operatorID = operatorID
        self.invoiceOnSave = invoiceOnSave
        onVisitSave = onSave
        // Unused for a visit: its record is keyed by the visit.
        _runID = State(initialValue: UUID())
        _stopStartedAt = State(initialValue: visit.scheduledDate)
        _selectedServiceIDs = State(initialValue: [])
        _notes = State(initialValue: "")
    }

    private var visit: ScheduledVisit? {
        if case .visit(let visit) = subject { return visit }
        return nil
    }

    /// Where the work is: the stop's place, or the visit's.
    private var propertyID: String {
        switch subject {
        case .stop(let stop): stop.propertyID
        case .visit(let visit): visit.propertyID
        }
    }

    private var address: String {
        switch subject {
        case .stop(let stop): stop.clientAddress
        case .visit(let visit): visit.clientAddress
        }
    }

    /// Whether the Save menu offers invoices: never once the work is on one,
    /// never read only, and for a visit never for a comped client (their
    /// work isn't billed). A stop's rule is unchanged.
    static func offersInvoiceItems(invoicedAs: String?, canEdit: Bool, isVisit: Bool, clientIsComped: Bool) -> Bool {
        guard invoicedAs == nil, canEdit else { return false }
        return !isVisit || !clientIsComped
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

    /// Expected at this stop (StopServices) or visit, in the catalog, and not ticked.
    private var expectedToAdd: [StopRecording.Service] {
        // The same filter as the route screen's "Done:" button (OneTapServices).
        OneTapServices.expectedInCatalog(expectedIDs, active: myServices)
            .filter { !selectedServiceIDs.contains($0.id) }
    }

    private var expectedIDs: [String] {
        switch subject {
        case .stop(let stop): StopServices.expected(for: stop, client: client)
        case .visit(let visit): visit.expectedServiceIDs
        }
    }

    private var myServices: [StopRecording.Service] {
        ServiceLog.activeServices(allServices, operatorID: operatorID)
    }

    /// The contract covering this stop on the day it started (a visit: the
    /// day it's scheduled), as billing will find it (Contracts.contract(coveringPlace:)).
    private func coveringContract(_ client: Client) -> Contract? {
        Contracts.contract(coveringPlace: Place.id(of: client, propertyID: propertyID), of: client.id.uuidString,
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
            "The services it covers are billed at \(Money.text(contract.price)) a visit, here and in Bill Unbilled Work."
        }
    }

    private var pricingZones: [InvoiceLines.Zone] {
        client.map { Place.zones(of: $0, propertyID: propertyID) } ?? []
    }

    var body: some View {
        NavigationStack {
            Form {
                if let client {
                    Section {
                        LabeledContent("Client", value: client.name)
                        // The stop's or visit's: its place's address, which may be a property's.
                        if !address.isEmpty {
                            LabeledContent("Address", value: address)
                        }
                        if let contract = coveringContract(client) {
                            LabeledContent("Contract", value: contract.name)
                            Text(contractNote(contract))
                                .font(.caption)
                                .foregroundStyle(PlowRColor.inkSecondary)
                        }
                    }
                    .listRowBackground(PlowRColor.surface)
                }

                photoSection(isBefore: true)
                photoSection(isBefore: false)

                // The stop's expected services, one tap to tick, never ticked
                // for you: a skipped or cleared stop mustn't record (and bill)
                // work that wasn't done. A visit's start ticked (completing it
                // records them anyway); this offers back any unticked.
                if !servicesLocked, !expectedToAdd.isEmpty {
                    Section {
                        Button {
                            Haptics.impact(.light)
                            expectedToAdd.forEach { selectedServiceIDs.insert($0.id) }
                        } label: {
                            Label("Add Expected: \(OneTapServices.englishList(expectedToAdd.map(\.name)))",
                                  systemImage: PlowRSymbol.services.name)
                        }
                    }
                    .listRowBackground(PlowRColor.surface)
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

                Section(title: "Notes") {
                    TextField("Optional notes for this stop…", text: $notes, axis: .vertical)
                        .lineLimit(3...)
                }
                .listRowBackground(PlowRColor.surface)
            }
            .plowRGrouped()
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
                    if invoiceOnSave, let visit {
                        Button(visit.status == .scheduled ? "Complete & Draft Invoice" : "Draft Invoice") {
                            save(invoice: .draft)
                        }
                        .disabled(client == nil || !hasAnythingToSave
                                  || !recording.unreadableFields(locked: servicesLocked).isEmpty)
                    } else {
                    Menu("Save") {
                        Button {
                            save(invoice: .none)
                        } label: {
                            Label("Save", systemImage: "checkmark.circle")
                        }
                        // Read only (a route that was running when the
                        // subscription ended): the stop still saves, no invoices.
                        if Self.offersInvoiceItems(invoicedAs: invoicedAs, canEdit: access.canEdit,
                                                   isVisit: visit != nil, clientIsComped: client?.isComped ?? false) {
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
                    .disabled(client == nil || !hasAnythingToSave || !recording.unreadableFields(locked: servicesLocked).isEmpty)
                    }
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
        .modifier(VisitEditsNeedPro(applies: visit != nil))
    }

    // MARK: - Photo Section

    @ViewBuilder
    private func photoSection(isBefore: Bool) -> some View {
        let images = isBefore ? beforeImages : afterImages
        let label = isBefore ? "Before Photos" : "After Photos"
        // The photo tags' colours (PhotoTag): Before neutral, After done.
        // Before's label is ink, not the neutral grey, which is how a
        // disabled button looks.
        let status: PlowRColor.Status = isBefore ? .neutral : .done
        let labelColor = isBefore ? PlowRColor.ink : status.text

        Section(title: label) {
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
                                        // Looks as before, in the corner of
                                        // a 44 pt square that takes the tap
                                        // (gloves).
                                        .frame(width: PlowRLayout.minTapTarget, height: PlowRLayout.minTapTarget,
                                               alignment: .topTrailing)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: 4, y: -4)
                                .accessibilityLabel(isBefore ? "Remove Before Photo" : "Remove After Photo")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }

            // Large text: Camera over Library, each at the full width.
            let photoButtons = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 12))
                : AnyLayout(HStackLayout(spacing: 12))
            photoButtons {
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
                            .background(status.soft)
                            .foregroundStyle(labelColor)
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
                        .background(status.soft)
                        .foregroundStyle(labelColor)
                        .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerSmall, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .listRowBackground(PlowRColor.surface)
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
        if let visit {
            loadVisitRecord(visit, client: client)
            return
        }
        guard case .stop(let stop) = subject else { return }
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

    /// A visit's record, as `loadRecord` loads a stop's. With none saved yet,
    /// its expected services start ticked at the visit's prices (after hours
    /// included), as plain Complete would record them (`ServiceLog.lines(for:)`).
    private func loadVisitRecord(_ visit: ScheduledVisit, client: Client) {
        let record = ServiceLog.record(forKey: ServiceLog.visitKey(visit.id), in: modelContext)
        invoicedAs = (ServiceLog.invoice(ofVisit: visit, in: modelContext)
            ?? record.flatMap { ServiceLog.invoice(of: $0, in: modelContext) })?.invoiceNumber
        let lines: [ServiceRecord.Line]
        if let record {
            hadRecord = true
            servicesLocked = ServiceLog.servicesLocked(record, in: modelContext)
            notes = record.notes
            lines = record.lines
        } else {
            lines = ServiceLog.lines(for: visit.expectedServiceIDs, client: client, propertyID: visit.propertyID,
                                     multiplier: visit.priceMultiplier, in: modelContext)
        }
        guard !lines.isEmpty else { return }
        let loaded = StopRecording.loading(lines, services: recording.services, zones: pricingZones)
        selectedServiceIDs = loaded.selectedIDs
        servicePriceOverrides = loaded.typedPrices
        customItems = loaded.customItems
        keptLines = loaded.keptLines
    }

    private func save(invoice choice: InvoiceChoice) {
        guard let client else { dismiss(); return }
        if let visit {
            saveVisit(visit, client: client, invoice: choice)
            return
        }
        guard case .stop(let stop) = subject else { return }
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
        if choice != .none, ServiceLog.invoice(of: record, in: modelContext) == nil,
           let proposal = ServiceLog.invoice(record, recording: recording, under: coveringContract(client),
                                             client: client, operatorID: operatorID, notes: notes, in: modelContext) {
            if choice == .sent {
                DocumentSent.markSent(proposal, in: modelContext)
            }
        }
        Haptics.success()
        PlowRTips.done(RecordServicesTip(), RecordServicesTip.servicesRecorded)
        dismiss()
    }

    /// A visit's save: `ServiceLog.saveVisitRecording` (completing a scheduled
    /// visit as Complete does), its photos, and the invoice asked for, made
    /// by the same `ServiceLog.invoice` a stop's is.
    private func saveVisit(_ visit: ScheduledVisit, client: Client, invoice choice: InvoiceChoice) {
        let recording = recording
        let record = ServiceLog.saveVisitRecording(recording, notes: notes, for: visit, client: client,
                                                   operatorID: operatorID, in: modelContext)
        for (images, isBefore) in [(beforeImages, true), (afterImages, false)] {
            for captured in images {
                guard let photo = StopPhoto.make(from: captured, isBefore: isBefore, operatorID: operatorID,
                                                 clientID: client.id.uuidString, routeID: "",
                                                 recordID: record.id.uuidString) else { continue }
                modelContext.insert(photo)
            }
        }
        var outcome = VisitSaveOutcome.saved
        if choice != .none, ServiceLog.invoice(of: record, in: modelContext) == nil {
            let contract = coveringContract(client)
            if let proposal = ServiceLog.invoice(record, recording: recording, under: contract, client: client,
                                                 operatorID: operatorID, notes: notes, in: modelContext) {
                if choice == .sent { DocumentSent.markSent(proposal, in: modelContext) }
                outcome = .invoiced(proposal)
            } else if invoiceOnSave {
                outcome = .nothingToBill(contractName: contract?.name)
            }
        }
        try? modelContext.save()
        Haptics.success()
        PlowRTips.done(RecordServicesTip(), RecordServicesTip.servicesRecorded)
        onVisitSave?(outcome)
        dismiss()
    }
}

/// Visit mode is an editor (`.editsNeedPro()`); a route stop's sheet never
/// is: a route already running is never gated.
private struct VisitEditsNeedPro: ViewModifier {
    let applies: Bool

    func body(content: Content) -> some View {
        if applies { content.editsNeedPro() } else { content }
    }
}
