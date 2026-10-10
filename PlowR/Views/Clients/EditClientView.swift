import SwiftUI
import SwiftData
import MapKit
import CoreLocation
import MessageUI

struct EditClientView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AuthManager.self) private var authManager
    @Environment(\.access) private var access
    @State private var gate: ProGate?

    let client: Client
    /// The client's address and pin as this screen knows them: when it
    /// opened, or after Adjust Pin or Move Pin changed them.
    @State private var originalAddress: String
    @State private var originalPin: PinPlacement.Pin

    @Query private var allProposals: [Proposal]
    @Query private var allProfiles: [BusinessProfile]
    @Query private var allPaymentMethods: [PaymentMethod]
    @Query(sort: \ScheduledVisit.scheduledDate) private var allVisits: [ScheduledVisit]
    @Query private var allServiceItems: [ServiceItem]

    /// What the screen edits (ClientDraft): compared with the client as saved
    /// when leaving, written back by Save.
    @State private var draft: ClientDraft
    @State private var newTag = ""
    @State private var geocodedCoordinate: CLLocationCoordinate2D?
    /// A pin from the pin screen that Save pairs with the typed address
    /// (PinPlacement.Field.handPin).
    @State private var handPin: PinPlacement.Pin?
    /// The address taken from the map on the pin screen, until the sheet
    /// closes (PinPlacement.field).
    @State private var addressChosenOnPinScreen: String?
    @State private var isSaving = false
    @State private var showingPropertyScanner = false
    @State private var addressCompleter = AddressCompleter()

    // Look Around
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var showingLookAround = false
    @State private var isLoadingLookAround = false
    @State private var showingLookAroundUnavailable = false
    @State private var showingLocationAdjust = false
    /// The new address couldn't be put on the map: save it without a pin,
    /// try again, or check it.
    @State private var lookupProblem: AddressPin.Problem?
    /// The address being looked up, as it was when Save was tapped.
    @State private var lookedUpAddress = ""

    // Documents
    @State private var revisePaidDoc: Proposal?
    @State private var editingProposal: Proposal?
    /// Save marks the client inactive, which takes them off these routes.
    @State private var deactivatingFootprint: ClientRemoval.Footprint?
    @State private var showingProposalBuilder = false
    @State private var showingInvoiceBuilder = false
    @State private var showingAddVisit = false
    @State private var propertySheet: PropertySheet?
    @State private var showingNewContract = false
    @State private var showingMessageComposer = false
    /// A document's PDF being shared from this page (DocumentShareView).
    @State private var documentShare: DocumentShare?

    private struct DocumentShare: Identifiable {
        let proposal: Proposal
        let url: URL
        var id: URL { url }
    }

    init(client: Client) {
        self.client = client
        _originalAddress = State(initialValue: client.address)
        _originalPin = State(initialValue: .init(latitude: client.latitude, longitude: client.longitude))
        _draft = State(initialValue: ClientDraft(client))
    }

    private var hasUnsavedChanges: Bool { draft != ClientDraft(client) }

    // MARK: - Body

    var body: some View {
        Form {
            actionTilesSection
            // Read only (PlowR Pro ended with more than 10 clients): the
            // details show but can't change. Records and documents below
            // stay open; what they open asks for itself.
            Group {
                contactSection
                tagsSection
                notesSection
                billingSection
                expectedServicesSection
                stopNotesSection
                serviceAddressSection
            }
            .disabled(!access.canEdit)
            // Read only, the details are locked, but Mark Inactive stays: an
            // inactive client doesn't count, the way back to the free tier.
            if !access.canEdit, client.isActive {
                Section {
                    Button("Mark Inactive") {
                        draft.isActive = false
                        save()
                    }
                } footer: {
                    Text("Inactive clients don't count toward the free tier's \(Access.freeClientLimit). They come off their routes.")
                }
            }
            otherPropertiesSection
            historySection
            contractsSection
            scheduleSection
            documentsSection
            photosSection
            propertySection
        }
        // Nothing changes, and nothing opens over the alert, while the new
        // address is looked up; and the screen can't be left mid-lookup.
        .disabled(isSaving)
        .navigationTitle(draft.name.isEmpty ? "Client" : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .asksBeforeLeaving(hasChanges: hasUnsavedChanges, isBusy: isSaving, canSave: draft.canSave,
                           message: draft.unsavedMessage(comparedWith: ClientDraft(client)),
                           save: { $gate.unless(ProGate.edit(access)) { save() } }, discard: { dismiss() })
        // The client changed underneath (Schedule making them active again, an
        // edit synced from another device): fields not edited here follow.
        .onChange(of: ClientDraft(client)) { old, new in
            if originalAddress == old.address { originalAddress = new.address }
            draft = draft.rebased(from: old, to: new)
        }
        .addressLookupAlert($lookupProblem, saveWithoutPin: {
            // A client with no pin yet: saved without one.
            client.changeAddress(to: lookedUpAddress)
            client.latitude = 0
            client.longitude = 0
            ClientStops.update(for: client)
            dismiss()
        }, tryAgain: {
            saveChanges()
        }, keepCurrentPin: AddressPin.exists(latitude: client.latitude, longitude: client.longitude) ? {
            // The new address with the pin the client has (a corrected spelling
            // of the same house, say); Adjust Pin moves it if it's a new place.
            client.changeAddress(to: lookedUpAddress)
            ClientStops.update(for: client)
            dismiss()
        } : nil)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button("Save") { $gate.unless(ProGate.edit(access)) { save() } }
                        .disabled(!draft.canSave)
                }
            }
        }
        .proGateSheet($gate)
        .sheet(isPresented: $showingPropertyScanner, onDismiss: takePinFromClient) {
            PropertyScannerView(client: client, pendingAddress: pendingAddress, startingPin: pendingPin,
                                onAddressChosen: { addressChosenOnPinScreen = $0 })
        }
        .sheet(isPresented: $showingLocationAdjust, onDismiss: takePinFromClient) {
            NavigationStack {
                LocationAdjustView(client: client, pendingAddress: pendingAddress, startingPin: pendingPin,
                                   onAddressChosen: { addressChosenOnPinScreen = $0 })
            }
        }
        .sheet(item: $editingProposal) { proposal in
            ProposalEditView(proposal: proposal)
        }
        .sheet(isPresented: $showingProposalBuilder) {
            NavigationStack { ProposalBuilderView(client: client, isInvoiceMode: false, taxExempt: draft.taxExempt) }
        }
        .sheet(isPresented: $showingInvoiceBuilder) {
            NavigationStack { ProposalBuilderView(client: client, isInvoiceMode: true, taxExempt: draft.taxExempt) }
        }
        .sheet(isPresented: $showingNewContract) {
            ContractEditView(client: client, contract: nil)
        }
        .sheet(item: $propertySheet) { sheet in
            PropertyEditView(client: client, property: sheet.property)
        }
        .sheet(isPresented: $showingAddVisit) {
            AddVisitView(client: client)
        }
        .sheet(isPresented: $showingMessageComposer) {
            if !draft.phone.isEmpty {
                // A plain text doesn't make the client "Awaiting Response":
                // that's for invoices and proposals (DocumentSent).
                MessageComposer(recipients: [draft.phone], body: "") { outcome in
                    // Kept for their Timeline (TextLog).
                    if outcome == .sent { TextLog.record(.text, body: "", to: [client.id], in: modelContext) }
                }
            }
        }
        // Sent to the client from the share sheet (Mark as Sent on): they're
        // awaiting a response.
        .sheet(item: $documentShare) { share in
            DocumentShareView(url: share.url, document: share.proposal, in: modelContext)
                .presentationDetents([.medium, .large])
        }
        .lookAroundViewer(isPresented: $showingLookAround, initialScene: lookAroundScene)
        .alert("Street View Unavailable", isPresented: $showingLookAroundUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Apple Maps doesn't have Street View coverage for this location.")
        }
        .confirmationDialog(
            "Mark \(draft.name) Inactive?",
            isPresented: Binding(
                get: { deactivatingFootprint != nil },
                set: { if !$0 { deactivatingFootprint = nil; undoReadOnlyMarkInactive() } }
            ),
            titleVisibility: .visible
        ) {
            Button("Save and Mark Inactive", role: .destructive) {
                deactivatingFootprint = nil
                saveChanges()
            }
            Button("Cancel", role: .cancel) {
                deactivatingFootprint = nil
                undoReadOnlyMarkInactive()
            }
        } message: {
            if let footprint = deactivatingFootprint {
                Text(ClientRemoval.deactivateMessage(for: footprint))
            }
        }
        .confirmationDialog(
            "Revise Paid Invoice",
            isPresented: Binding(
                get: { revisePaidDoc != nil },
                set: { if !$0 { revisePaidDoc = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Save as Revision Copy") {
                if let doc = revisePaidDoc { createRevision(of: doc) }
                revisePaidDoc = nil
            }
            Button("Overwrite Original", role: .destructive) {
                if let doc = revisePaidDoc { overwriteForEdit(doc) }
                revisePaidDoc = nil
            }
            Button("Cancel", role: .cancel) { revisePaidDoc = nil }
        } message: {
            if let doc = revisePaidDoc {
                let copyNumber = InvoiceNumbering.nextRevision(of: doc.invoiceNumber,
                                                               operatorID: doc.operatorID, in: modelContext)
                Text(["'\(doc.invoiceNumber)' is marked paid. 'Save as Revision Copy' creates \(copyNumber) as a new draft. 'Overwrite' resets it to Draft so you can resend.",
                      Payments.clearNote(for: doc)].filter { !$0.isEmpty }.joined(separator: " "))
            }
        }
    }

    // MARK: - Action Tiles

    private var actionTilesSection: some View {
        Section {
            // Four tiles sharing the row's width (ClientActionTile). The
            // scroll view doesn't scroll: it keeps the list from treating the
            // row as one tappable cell with a disclosure arrow.
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Menu {
                        if !draft.phone.isEmpty {
                            Button {
                                if let url = URL(string: "tel:\(draft.phone.filter { $0.isNumber })") { openURL(url) }
                            } label: { Label("Call", systemImage: "phone.fill") }
                            // Presenting the composer where texting isn't set up
                            // (an iPad without Messages) fails; every other
                            // screen checks this first.
                            if MFMessageComposeViewController.canSendText() {
                                Button { showingMessageComposer = true } label: {
                                    Label("Message", systemImage: "message.fill")
                                }
                            }
                        }
                        if RequestLink.mailLink(draft.email) != nil {
                            Button {
                                if let url = RequestLink.mailLink(draft.email) { openURL(url) }
                            } label: { Label("Email", systemImage: "envelope.fill") }
                        }
                    } label: {
                        ClientActionTile(title: "Contact", icon: "phone.badge.waveform.fill", color: .blue)
                    }
                    // Styled as the other tiles are: a menu otherwise tints
                    // and pads its label its own way.
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    actionTile(title: "Invoice", icon: "doc.badge.arrow.up", color: .orange) {
                        if let latest = clientDocuments.first(where: { $0.isInvoice && $0.invoicePaidAt == nil }) {
                            editingProposal = latest
                        } else {
                            showingInvoiceBuilder = true
                        }
                    }
                    actionTile(title: "Schedule", icon: "calendar.badge.plus", color: .purple) {
                        showingAddVisit = true
                    }
                    NavigationLink {
                        ClientPhotoGalleryView(client: client)
                    } label: {
                        ClientActionTile(title: "Photos", icon: "photo.on.rectangle.angled", color: .teal)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 10)
                .containerRelativeFrame(.horizontal)
            }
            .scrollDisabled(true)
            .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
        }
    }

    private func actionTile(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ClientActionTile(title: title, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Contact Section

    private var contactSection: some View {
        Section("Contact") {
            TextField("Full Name", text: $draft.name)
                .textContentType(.name)
            HStack {
                TextField("Phone Number", text: $draft.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                if !draft.phone.isEmpty,
                   let url = URL(string: "tel:\(draft.phone.filter { $0.isNumber })") {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "phone.fill")
                            .foregroundStyle(.green)
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Email (optional)", text: $draft.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                if let url = RequestLink.mailLink(draft.email) {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Toggle(isOn: $draft.skipNotificationPrompt) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skip arrival message prompt")
                    Text("Won't ask to notify when you arrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(value: $draft.goalMinutes, in: 0...180, step: 5) {
                HStack {
                    Text("Stop goal time")
                    Spacer()
                    Text(draft.goalMinutes == 0 ? "Not set" : "\(draft.goalMinutes) min")
                        .foregroundStyle(draft.goalMinutes == 0 ? .secondary : .primary)
                }
            }
            Toggle(isOn: $draft.isActive) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active client")
                    Text("Inactive clients are listed separately and taken off their routes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Tags Section

    private static let tagSuggestions = [
        "Residential", "Commercial", "Priority", "Seasonal",
        "Driveway Only", "Walkways", "Back Lot", "Comped"
    ]

    private var tagsSection: some View {
        Section {
            if !draft.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(draft.tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                Button {
                                    draft.tags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            }
            HStack {
                TextField("Add tag…", text: $newTag)
                    .submitLabel(.done)
                    .onSubmit { addTag() }
                Button("Add") { addTag() }
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            let suggestions = Self.tagSuggestions.filter { !draft.tags.contains($0) }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                draft.tags.append(suggestion)
                            } label: {
                                Text("+ \(suggestion)")
                                    .font(.caption.weight(.medium))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color(.systemGray5))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 4, trailing: 16))
            }
        } header: {
            Text("Tags")
        } footer: {
            Text("Group clients for bulk messaging — e.g. Residential, Priority, Seasonal.")
                .font(.caption)
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !draft.tags.contains(trimmed) else { return }
        draft.tags.append(trimmed)
        newTag = ""
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        Section {
            TextField("Internal notes…", text: $draft.notes, axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text("Notes")
        } footer: {
            Text("Private notes about this client — not shown on route or documents.")
                .font(.caption)
        }
    }

    // MARK: - Expected Services Section

    private var clientServices: [ServiceItem] {
        allServiceItems
            .filter { $0.operatorID == authManager.userID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var expectedServicesSection: some View {
        Section {
            if clientServices.isEmpty {
                StandardServicesOffer(operatorID: authManager.userID)
            } else {
                NavigationLink {
                    expectedServicePickerView
                } label: {
                    HStack {
                        Text("Expected Services")
                        Spacer()
                        Text(draft.expectedServiceIDs.isEmpty ? "None" : "\(draft.expectedServiceIDs.count) selected")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Default Services")
        } footer: {
            Text("Services this client typically needs. Their route stops expect these, except a stop given its own services on its route (tap the stop on the route).")
                .font(.caption)
        }
    }

    private var expectedServicePickerView: some View {
        List {
            ForEach(clientServices) { service in
                let isSelected = draft.expectedServiceIDs.contains(service.id.uuidString)
                Button {
                    if isSelected { draft.expectedServiceIDs.remove(service.id.uuidString) }
                    else          { draft.expectedServiceIDs.insert(service.id.uuidString) }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? .blue : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(service.name).foregroundStyle(.primary)
                            Text(service.category.capitalized)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Expected Services")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Billing Section

    private var billingSection: some View {
        Section("Billing & Preferences") {
            Picker("Preferred Payment", selection: $draft.preferredPayment) {
                Text("Not set").tag("")
                Text("Cash").tag("cash")
                Text("Check").tag("check")
                Text("Zelle").tag("zelle")
                Text("Card").tag("card")
            }

            Toggle("Comped / No Charge", isOn: $draft.isComped)

            Toggle(isOn: $draft.taxExempt) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tax Exempt")
                    Text("New invoices and proposals start at 0% tax instead of your rate in Business Profile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !draft.isComped {
                HStack {
                    Text("Default Discount")
                    Spacer()
                    Picker("Discount", selection: $draft.defaultDiscountPercent) {
                        Text("None").tag(0.0)
                        Text("5%").tag(5.0)
                        Text("10%").tag(10.0)
                        Text("15%").tag(15.0)
                        Text("20%").tag(20.0)
                        Text("25%").tag(25.0)
                        Text("50%").tag(50.0)
                    }
                    .pickerStyle(.menu)
                }
            }
        }
    }

    // MARK: - Stop Notes Section

    private var stopNotesSection: some View {
        Section {
            TextField("Notes shown during active route (gate codes, special instructions…)", text: $draft.defaultStopNotes, axis: .vertical)
                .lineLimit(3)
        } header: {
            Text("Route Notes")
        } footer: {
            Text("Automatically copied to new route stops for this client.")
                .font(.caption)
        }
    }

    // MARK: - Service Address Section

    private var serviceAddressSection: some View {
        Section {
            TextField("Street Address", text: $draft.address)
                .textContentType(.fullStreetAddress)
                .onChange(of: draft.address) { _, v in
                    // Not typed: the address a new pin brought.
                    guard v != originalAddress else {
                        geocodedCoordinate = nil
                        addressCompleter.clear()
                        return
                    }
                    if addressCompleter.fieldChanged(to: v) { geocodedCoordinate = nil }
                }

            if !addressCompleter.completions.isEmpty {
                ForEach(addressCompleter.completions, id: \.self) { completion in
                    Button {
                        Task {
                            let result = await addressCompleter.resolve(completion)
                            draft.address = result.address
                            geocodedCoordinate = result.coordinate
                            addressCompleter.clear()
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(completion.title)
                                .foregroundStyle(.primary)
                            if !completion.subtitle.isEmpty {
                                Text(completion.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Service Address")
        } footer: {
            if client.needsAddressFix {
                AddressNotFoundLabel(detail: "The map couldn't find this address, so this client has no pin and isn't on route maps. Correct the address, or set the pin with Set Pin on the Map, under Main Property.")
            }
        }
    }

    // MARK: - Other Properties Section

    /// The property page, for a property or a new one.
    private struct PropertySheet: Identifiable {
        let property: Property?
        var id: String { property?.id.uuidString ?? "new" }
    }

    private var otherPropertiesSection: some View {
        Section {
            ForEach(Place.ordered(client.properties ?? [])) { property in
                Button {
                    propertySheet = PropertySheet(property: property)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Place.of(property).label).foregroundStyle(.primary)
                            if !property.label.isEmpty {
                                Text(property.address).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if property.needsAddressFix {
                            StatusChip("Address not found", systemImage: AddressNotFoundLabel.symbol, color: AddressNotFoundLabel.color)
                        }
                        if !property.isActive { StatusChip("Inactive", color: .gray) }
                    }
                }
            }
            Button {
                propertySheet = PropertySheet(property: nil)
            } label: {
                Label("Add Property", systemImage: "plus")
            }
        } header: {
            Text("Other Properties")
        } footer: {
            Text("Other places you work for this client, like a rental or a second lot. Each can go on routes and the schedule by itself.")
                .font(.caption)
        }
    }

    // MARK: - Contracts Section

    private var contractsSection: some View {
        Section {
            ForEach(Contracts.sorted(client.contracts ?? [])) { contract in
                NavigationLink { ContractDetailView(contract: contract) } label: { ContractRow(contract: contract) }
            }
            Button {
                showingNewContract = true
            } label: {
                Label("New Contract", systemImage: "plus")
            }
        } header: {
            Text("Contracts")
        } footer: {
            Text("An agreement for a period: a season price, a price per visit, or a monthly amount.")
                .font(.caption)
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        Section("Service History") {
            // Every job, from routes, visits or logged by hand (the Service Log).
            NavigationLink {
                ClientServiceHistoryView(client: client)
            } label: {
                Label("All Work", systemImage: "list.bullet.clipboard")
            }
            // Jobs, visits, invoices and photos together, newest first.
            NavigationLink {
                ClientTimelineView(client: client)
            } label: {
                Label("Timeline", systemImage: "clock")
            }
            if client.totalVisits == 0 {
                Text("No route visits recorded yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                LabeledContent("Total Visits", value: "\(client.totalVisits) visit\(client.totalVisits == 1 ? "" : "s")")
                if let last = client.lastServiceDate {
                    LabeledContent("Last Service") {
                        Text(last, format: .dateTime.month(.abbreviated).day().year())
                    }
                }
                if client.averageServiceMinutes > 0 {
                    LabeledContent("Avg Time on Site") {
                        Text(String(format: "~%.0f min", client.averageServiceMinutes))
                    }
                }
                if draft.goalMinutes > 0 && client.averageServiceMinutes > 0 {
                    let diff = client.averageServiceMinutes - Double(draft.goalMinutes)
                    LabeledContent("vs. Goal (\(draft.goalMinutes)m)") {
                        let label = abs(diff) < 1
                            ? "On target"
                            : (diff > 0 ? "\(Int(diff))m over" : "\(Int(-diff))m under")
                        Text(label)
                            .foregroundStyle(abs(diff) < 2 ? .green : (diff > 0 ? .orange : .green))
                    }
                }
                if totalRevenuePaid > 0 {
                    LabeledContent("Revenue Collected") {
                        Text(totalRevenuePaid, format: .currency(code: "USD"))
                            .foregroundStyle(.green)
                    }
                }
            }
            if outstandingBalance > 0 {
                LabeledContent("Outstanding Balance") {
                    Text(outstandingBalance, format: .currency(code: "USD"))
                        .foregroundStyle(.orange)        // outstanding, as everywhere
                        .fontWeight(.semibold)
                }
            } else if !clientInvoices.isEmpty {
                LabeledContent("Balance") {
                    Text("Paid in full").foregroundStyle(.green)
                }
            }

            pipelineStageRow

            if let sent = client.lastMessageSentAt {
                let awaitingResponse = Pipeline.isAwaitingResponse(client)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(awaitingResponse ? "Awaiting Response" : "Client Responded")
                            .font(.subheadline)
                            .foregroundStyle(awaitingResponse ? .orange : .green)
                        Text("Invoice or proposal sent \(sent, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if awaitingResponse {
                        Button("Mark Responded") {
                            $gate.unless(ProGate.edit(access)) { client.clientRespondedAt = Date() }
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    /// Where they stand before they're a customer (Pipeline): Lead or
    /// Quoted, with Mark Lost; or Lost, with Reopen. Nothing for a customer.
    @ViewBuilder
    private var pipelineStageRow: some View {
        // This client's records only: the page redraws with each key typed.
        let stage = Pipeline.stage(of: client, facts: Pipeline.Facts(of: client, in: modelContext))
        if stage != .customer, client.isActive {
            LabeledContent {
                Button(stage == .lost ? "Reopen" : "Mark Lost") {
                    $gate.unless(ProGate.edit(access)) { Pipeline.setLost(stage != .lost, for: client, in: modelContext) }
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
            } label: {
                StatusChip(stage.title, color: stage == .lost ? .gray : .blue)
            }
        }
    }

    // MARK: - Documents Section

    private var documentsSection: some View {
        Section("Documents") {
            if clientDocuments.isEmpty {
                Text("No documents yet")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(clientDocuments) { doc in
                    clientDocumentRow(doc)
                }
            }
            HStack(spacing: 0) {
                Button {
                    showingProposalBuilder = true
                } label: {
                    Label("New Proposal", systemImage: "doc.text")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                Divider().frame(height: 20)
                Button {
                    showingInvoiceBuilder = true
                } label: {
                    Label("New Invoice", systemImage: "doc.badge.arrow.up")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Property Section

    private var propertySection: some View {
        Section("Main Property") {
            let zones = client.sortedZones
            if !zones.isEmpty {
                zoneMapPreview(zones: zones)
                    .listRowInsets(EdgeInsets())
            }

            if !AddressPin.exists(latitude: client.latitude, longitude: client.longitude) {
                // No pin (the address couldn't be found): set it by hand, or the
                // client stays off route maps. Adjust Pin was hidden here.
                Button {
                    showingLocationAdjust = true
                } label: {
                    Label("Set Pin on the Map", systemImage: "mappin.and.ellipse")
                }
            } else {
                HStack(spacing: 10) {
                    Button {
                        showingLocationAdjust = true
                    } label: {
                        Label("Adjust Pin", systemImage: "mappin.and.ellipse")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        loadLookAround()
                    } label: {
                        if isLoadingLookAround {
                            ProgressView().scaleEffect(0.8).frame(maxWidth: .infinity)
                        } else {
                            Label("Street View", systemImage: "binoculars")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingLookAround)
                }
            }

            if zones.isEmpty {
                Button {
                    showingPropertyScanner = true
                } label: {
                    Label("Map Service Area", systemImage: "map")
                }
                .disabled(!AddressPin.exists(latitude: client.latitude, longitude: client.longitude))
            } else {
                ForEach(zones) { zone in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(zone.label).font(.subheadline)
                            Text("\(Int(zone.areaSquareFeet)) sq ft · \(zone.terrainLabel)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                }
                Button("Edit Zones") { showingPropertyScanner = true }
            }
        }
    }

    // MARK: - Schedule Section

    private var upcomingClientVisits: [ScheduledVisit] {
        let clientID = client.id.uuidString
        return allVisits
            .filter { $0.clientID == clientID && $0.status == .scheduled && $0.scheduledDate >= Date() }
            .prefix(3)
            .map { $0 }
    }

    private var scheduleSection: some View {
        Section("Upcoming Visits") {
            if upcomingClientVisits.isEmpty {
                Text("No upcoming visits scheduled")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(upcomingClientVisits) { visit in
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .foregroundStyle(.blue)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(visit.scheduledDate, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                                .font(.subheadline)
                            Text(visit.scheduledDate, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label(visit.status.rawValue, systemImage: visit.status.systemImage)
                            .font(.caption2)
                            .foregroundStyle(visit.status.chipColor)
                    }
                }
            }
            Button {
                showingAddVisit = true
            } label: {
                Label("Schedule Visit", systemImage: "calendar.badge.plus")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Photos Section

    private var photosSection: some View {
        Section("Photos") {
            NavigationLink {
                ClientPhotoGalleryView(client: client)
            } label: {
                Label("View Photo Gallery", systemImage: "photo.on.rectangle.angled")
            }
        }
    }

    // MARK: - Data

    private var clientInvoices: [Proposal] {
        allProposals.filter { $0.clientID == client.id.uuidString && $0.isInvoice }
    }

    private var clientDocuments: [Proposal] {
        allProposals
            .filter { $0.clientID == client.id.uuidString }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var outstandingBalance: Double { Payments.owed(clientInvoices) }

    private var totalRevenuePaid: Double { Payments.received(clientInvoices) }

    private var operatorProfile: BusinessProfile? {
        allProfiles.first { $0.operatorID == client.operatorID }
    }

    private var operatorPaymentMethods: [PaymentMethod] {
        allPaymentMethods
            .filter { $0.operatorID == client.operatorID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Document Row

    @ViewBuilder
    private func clientDocumentRow(_ document: Proposal) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    StatusChip(document.invoiceStatus.rawValue, systemImage: document.invoiceStatus.systemImage,
                               color: document.invoiceStatus.chipColor)
                    if !document.revisionOf.isEmpty {
                        StatusChip("Revision", color: .orange)
                    }
                }
                Text(document.isInvoice
                     ? document.invoiceNumber
                     : "Proposal · \(document.createdAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                if document.isInvoice, let due = document.invoiceDueDate {
                    Text("Due \(due.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(String(format: "$%.2f", document.total))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                BalanceDueCaption(document: document)
                HStack(spacing: 4) {
                    Button {
                        $gate.unless(ProGate.shareDocument(access, isInvoice: document.isInvoice,
                                                           owed: Payments.owed([document]))) {
                            shareDocument(document)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    if document.invoiceStatus == .sent || document.invoiceStatus == .overdue {
                        Button("Paid") {
                            Payments.payInFull(document, in: modelContext)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.green)
                        Button("Edit") {
                            editingProposal = document
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.blue)
                    } else if document.invoiceStatus == .draft {
                        Button("Edit") {
                            editingProposal = document
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.blue)
                    } else if document.invoiceStatus == .paid {
                        Button("Revise") {
                            $gate.unless(ProGate.edit(access)) { revisePaidDoc = document }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .tint(.orange)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Document Actions

    private func shareDocument(_ proposal: Proposal) {
        let data = PDFGenerator.generate(
            proposal: proposal,
            zones: client.sortedZones,
            profile: operatorProfile,
            paymentMethods: operatorPaymentMethods,
            forceIsInvoice: proposal.isInvoice,
            madeWithPlowR: access.showsMadeWithPlowR
        )
        let prefix = proposal.isInvoice ? "Invoice" : "Proposal"
        let safe = client.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(safe)-\(proposal.id.uuidString.prefix(6)).pdf")
        try? data.write(to: url)
        documentShare = DocumentShare(proposal: proposal, url: url)
    }

    private func createRevision(of original: Proposal) {
        ServiceLog.revise(original, client: client, in: modelContext)
    }

    private func overwriteForEdit(_ proposal: Proposal) {
        // Reset to Draft so the operator can resend with updated info
        Payments.clear(proposal, in: modelContext)
        proposal.invoiceSentAt = nil
    }

    // MARK: - Map

    @ViewBuilder
    private func zoneMapPreview(zones: [PropertyZone]) -> some View {
        let region = regionForZones(zones)
        Map(initialPosition: .region(region), interactionModes: []) {
            ForEach(zones) { zone in
                MapPolygon(coordinates: zone.coordinates)
                    .foregroundStyle(Color.accentColor.opacity(0.3))
            }
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerMedium, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Label("Edit Zones", systemImage: "pencil")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(8)
        }
        .contentShape(Rectangle())
        .onTapGesture { showingPropertyScanner = true }
    }

    private func regionForZones(_ zones: [PropertyZone]) -> MKCoordinateRegion {
        // Zones sit on one property, so this frames much tighter than the route
        // maps: 3.5× the zones' box, never narrower than 0.0005°.
        guard let bounds = CoordinateBounds(zones.flatMap { $0.coordinates }) else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: client.latitude, longitude: client.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
            )
        }
        return bounds.region(padding: 3.5, minimumDelta: 0.0005)
    }

    // MARK: - Look Around

    private func loadLookAround() {
        isLoadingLookAround = true
        Task {
            let coord = CLLocationCoordinate2D(latitude: client.latitude, longitude: client.longitude)
            let request = MKLookAroundSceneRequest(coordinate: coord)
            lookAroundScene = try? await request.scene
            isLoadingLookAround = false
            if lookAroundScene != nil {
                showingLookAround = true
            } else {
                showingLookAroundUnavailable = true
            }
        }
    }

    // MARK: - Save

    /// A new address typed here and not saved yet, and its pin (picked, or
    /// set by hand): the pin screens show that address and open at that pin.
    private var pendingAddress: String? { draft.address != originalAddress ? draft.address : nil }
    private var pendingPin: PinPlacement.Pin? {
        geocodedCoordinate.map { .init(latitude: $0.latitude, longitude: $0.longitude) } ?? handPin
    }

    /// Adjust Pin and the property scanner's Move Pin save the client's pin,
    /// and the address there, themselves; this screen takes them. Save used
    /// to write back the address it opened with, and could look an address
    /// typed before up again over the pin just set by hand. Which pins keep
    /// what was typed: PinPlacement.field.
    private func takePinFromClient() {
        let before = PinPlacement.Field(
            text: draft.address, original: originalAddress, originalPin: originalPin,
            pickedPin: geocodedCoordinate.map { .init(latitude: $0.latitude, longitude: $0.longitude) },
            handPin: handPin)
        let after = PinPlacement.field(before, afterPinSheetWith: client.address,
                                       .init(latitude: client.latitude, longitude: client.longitude),
                                       chosen: addressChosenOnPinScreen)
        addressChosenOnPinScreen = nil
        originalPin = after.originalPin
        originalAddress = after.original
        draft.address = after.text
        geocodedCoordinate = after.pickedPin.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        handPin = after.handPin
    }

    /// Asks first when Save marks the client inactive and they're on a route.
    /// Read only, Mark Inactive set the locked switch before asking; not
    /// going ahead puts it back, or the page would be stuck with a change it
    /// can't save.
    private func undoReadOnlyMarkInactive() {
        if !access.canEdit { draft.isActive = client.isActive }
    }

    private func save() {
        // Marking them active again: one more client.
        if draft.isActive, let blocked = ProGate.bringBack(client, access) {
            gate = blocked
            return
        }
        if client.isActive, !draft.isActive {
            let footprint = ClientRemoval.footprint(of: client, in: modelContext)
            if !footprint.routeNames.isEmpty {
                deactivatingFootprint = footprint
                return
            }
        }
        saveChanges()
    }

    private func saveChanges() {
        isSaving = true
        draft.applyExceptAddressAndActive(to: client)
        ClientRemoval.setActive(draft.isActive, for: client, in: modelContext)

        // Every path ends with the client's stops following (ClientStops): a
        // new name, phone, address or pin reaches their routes.
        // A picked suggestion's pin, or one set by hand (typing keeps it).
        let pinForSave = geocodedCoordinate ?? handPin.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        if let coord = pinForSave, draft.address != originalAddress {
            client.changeAddress(to: draft.address)
            client.latitude = coord.latitude
            client.longitude = coord.longitude
            ClientStops.update(for: client)
            isSaving = false
            dismiss()
            return
        }

        if draft.address != originalAddress, !draft.address.isEmpty {
            // Taken now: the lookup waits on the network.
            let typed = draft.address
            lookedUpAddress = typed
            lookupProblem = nil
            Task {
                let lookup = await AddressPin.lookUp(typed)
                isSaving = false
                switch lookup {
                case let .found(latitude, longitude):
                    client.changeAddress(to: typed)
                    client.latitude = latitude
                    client.longitude = longitude
                    ClientStops.update(for: client)
                    dismiss()
                case .failed(let problem):
                    // It used to keep the old address's pin, and say nothing.
                    lookupProblem = problem
                }
            }
        } else {
            client.changeAddress(to: draft.address)
            ClientStops.update(for: client)
            isSaving = false
            dismiss()
        }
    }
}
