import SwiftUI
import SwiftData
import MapKit
import CoreLocation

struct EditClientView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AuthManager.self) private var authManager

    let client: Client
    private let originalAddress: String

    @Query private var allProposals: [Proposal]
    @Query private var allProfiles: [BusinessProfile]
    @Query private var allPaymentMethods: [PaymentMethod]
    @Query(sort: \ScheduledVisit.scheduledDate) private var allVisits: [ScheduledVisit]

    @State private var name: String
    @State private var phone: String
    @State private var email: String
    @State private var address: String
    @State private var skipNotificationPrompt: Bool
    @State private var goalMinutes: Int
    @State private var defaultStopNotes: String
    @State private var preferredPayment: String
    @State private var isComped: Bool
    @State private var defaultDiscountPercent: Double
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var geocodedCoordinate: CLLocationCoordinate2D?
    @State private var isSaving = false
    @State private var showingPropertyScanner = false
    @State private var addressCompleter = AddressCompleter()

    // Look Around
    @State private var lookAroundScene: MKLookAroundScene?
    @State private var showingLookAround = false
    @State private var isLoadingLookAround = false
    @State private var showingLookAroundUnavailable = false
    @State private var showingLocationAdjust = false

    // Documents
    @State private var revisePaidDoc: Proposal?
    @State private var editingProposal: Proposal?
    @State private var notes: String
    @State private var isActive: Bool
    @State private var showingProposalBuilder = false
    @State private var showingInvoiceBuilder = false
    @State private var showingAddVisit = false
    @State private var showingMessageComposer = false

    init(client: Client) {
        self.client = client
        self.originalAddress = client.address
        _name = State(initialValue: client.name)
        _phone = State(initialValue: client.phone)
        _email = State(initialValue: client.email)
        _address = State(initialValue: client.address)
        _skipNotificationPrompt = State(initialValue: client.skipNotificationPrompt)
        _goalMinutes = State(initialValue: client.goalMinutes)
        _defaultStopNotes = State(initialValue: client.defaultStopNotes)
        _preferredPayment = State(initialValue: client.preferredPayment)
        _isComped = State(initialValue: client.isComped)
        _defaultDiscountPercent = State(initialValue: client.defaultDiscountPercent)
        _tags = State(initialValue: client.tags)
        _notes = State(initialValue: client.notes)
        _isActive = State(initialValue: client.isActive)
    }

    // MARK: - Body

    var body: some View {
        Form {
            actionTilesSection
            contactSection
            tagsSection
            notesSection
            billingSection
            stopNotesSection
            serviceAddressSection
            historySection
            scheduleSection
            documentsSection
            photosSection
            propertySection
        }
        .navigationTitle(name.isEmpty ? "Client" : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView().scaleEffect(0.8)
                } else {
                    Button("Save") { saveChanges() }
                        .disabled(name.isEmpty || phone.isEmpty)
                }
            }
        }
        .sheet(isPresented: $showingPropertyScanner) {
            PropertyScannerView(client: client)
        }
        .sheet(isPresented: $showingLocationAdjust) {
            NavigationStack {
                LocationAdjustView(client: client)
            }
        }
        .sheet(item: $editingProposal) { proposal in
            ProposalEditView(proposal: proposal)
        }
        .sheet(isPresented: $showingProposalBuilder) {
            NavigationStack { ProposalBuilderView(client: client, isInvoiceMode: false) }
        }
        .sheet(isPresented: $showingInvoiceBuilder) {
            NavigationStack { ProposalBuilderView(client: client, isInvoiceMode: true) }
        }
        .sheet(isPresented: $showingAddVisit) {
            AddVisitView(client: client)
        }
        .sheet(isPresented: $showingMessageComposer) {
            if !phone.isEmpty {
                MessageComposer(recipients: [phone], body: "") {
                    client.lastMessageSentAt = Date()
                    client.clientRespondedAt = nil
                }
            }
        }
        .lookAroundViewer(isPresented: $showingLookAround, initialScene: lookAroundScene)
        .alert("Street View Unavailable", isPresented: $showingLookAroundUnavailable) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Apple Maps doesn't have Street View coverage for this location.")
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
                Text("'\(doc.invoiceNumber)' is marked paid. 'Save as Revision Copy' creates \(doc.invoiceNumber)-R1 as a new draft. 'Overwrite' resets it to Draft so you can resend.")
            }
        }
    }

    // MARK: - Action Tiles

    private var actionTilesSection: some View {
        Section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    actionTile(title: "Call", icon: "phone.fill", color: .green) {
                        if let url = URL(string: "tel:\(phone.filter { $0.isNumber })"),
                           !phone.isEmpty {
                            openURL(url)
                        }
                    }
                    actionTile(title: "Message", icon: "message.fill", color: .blue) {
                        showingMessageComposer = true
                    }
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
                        actionTileLabel(title: "Photos", icon: "photo.on.rectangle.angled", color: .teal)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 8)
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
        }
    }

    private func actionTile(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            actionTileLabel(title: title, icon: icon, color: color)
        }
        .buttonStyle(.plain)
    }

    private func actionTileLabel(title: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 50, height: 40)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 64)
    }

    // MARK: - Contact Section

    private var contactSection: some View {
        Section("Contact") {
            TextField("Full Name", text: $name)
                .textContentType(.name)
            HStack {
                TextField("Phone Number", text: $phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                if !phone.isEmpty,
                   let url = URL(string: "tel:\(phone.filter { $0.isNumber })") {
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
                TextField("Email (optional)", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                if !email.isEmpty, let url = URL(string: "mailto:\(email)") {
                    Button {
                        openURL(url)
                    } label: {
                        Image(systemName: "envelope.fill")
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.borderless)
                }
            }
            Toggle(isOn: $skipNotificationPrompt) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Skip arrival message prompt")
                    Text("Won't ask to notify when you arrive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Stepper(value: $goalMinutes, in: 0...180, step: 5) {
                HStack {
                    Text("Stop goal time")
                    Spacer()
                    Text(goalMinutes == 0 ? "Not set" : "\(goalMinutes) min")
                        .foregroundStyle(goalMinutes == 0 ? .secondary : .primary)
                }
            }
            Toggle(isOn: $isActive) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Active client")
                    Text("Inactive clients appear separately in the list")
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
            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.caption.weight(.semibold))
                                Button {
                                    tags.removeAll { $0 == tag }
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
            let suggestions = Self.tagSuggestions.filter { !tags.contains($0) }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { suggestion in
                            Button {
                                tags.append(suggestion)
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
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        tags.append(trimmed)
        newTag = ""
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        Section {
            TextField("Internal notes…", text: $notes, axis: .vertical)
                .lineLimit(3...8)
        } header: {
            Text("Notes")
        } footer: {
            Text("Private notes about this client — not shown on route or documents.")
                .font(.caption)
        }
    }

    // MARK: - Billing Section

    private var billingSection: some View {
        Section("Billing & Preferences") {
            Picker("Preferred Payment", selection: $preferredPayment) {
                Text("Not set").tag("")
                Text("Cash").tag("cash")
                Text("Check").tag("check")
                Text("Zelle").tag("zelle")
                Text("Card").tag("card")
            }

            Toggle("Comped / No Charge", isOn: $isComped)

            if !isComped {
                HStack {
                    Text("Default Discount")
                    Spacer()
                    Picker("Discount", selection: $defaultDiscountPercent) {
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
            TextField("Notes shown during active route (gate codes, special instructions…)", text: $defaultStopNotes, axis: .vertical)
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
        Section("Service Address") {
            TextField("Street Address", text: $address)
                .textContentType(.fullStreetAddress)
                .onChange(of: address) { _, v in
                    geocodedCoordinate = nil
                    addressCompleter.search(v)
                }

            if !addressCompleter.completions.isEmpty {
                ForEach(addressCompleter.completions, id: \.self) { completion in
                    Button {
                        Task {
                            let result = await addressCompleter.resolve(completion)
                            address = result.address
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
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        Section("Service History") {
            if client.totalVisits == 0 {
                Text("No visits recorded yet")
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
                if goalMinutes > 0 && client.averageServiceMinutes > 0 {
                    let diff = client.averageServiceMinutes - Double(goalMinutes)
                    LabeledContent("vs. Goal (\(goalMinutes)m)") {
                        let label = abs(diff) < 1
                            ? "On target"
                            : (diff > 0 ? "\(Int(diff))m over" : "\(Int(-diff))m under")
                        Text(label)
                            .foregroundStyle(abs(diff) < 2 ? .green : (diff > 0 ? .orange : .green))
                    }
                }
            }
            if outstandingBalance > 0 {
                LabeledContent("Outstanding Balance") {
                    Text(outstandingBalance, format: .currency(code: "USD"))
                        .foregroundStyle(.red)
                        .fontWeight(.semibold)
                }
            } else if !clientInvoices.isEmpty {
                LabeledContent("Balance") {
                    Text("Paid in full").foregroundStyle(.green)
                }
            }

            if let sent = client.lastMessageSentAt {
                let responded = client.clientRespondedAt
                let awaitingResponse = responded == nil || responded! < sent
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(awaitingResponse ? "Awaiting Response" : "Client Responded")
                            .font(.subheadline)
                            .foregroundStyle(awaitingResponse ? .orange : .green)
                        Text("Last message sent \(sent, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if awaitingResponse {
                        Button("Mark Responded") {
                            client.clientRespondedAt = Date()
                        }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
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
        Section("Property") {
            let zones = client.sortedZones
            if !zones.isEmpty {
                zoneMapPreview(zones: zones)
                    .listRowInsets(EdgeInsets())
            }

            if client.latitude != 0 {
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
                .disabled(client.latitude == 0 && client.longitude == 0)
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
                Text("No upcoming visits scheduled.")
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

    private var outstandingBalance: Double {
        clientInvoices
            .filter { $0.invoicePaidAt == nil }
            .reduce(0) { $0 + $1.total }
    }

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
                    Label(document.invoiceStatus.rawValue, systemImage: document.invoiceStatus.systemImage)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(document.invoiceStatus.chipColor.opacity(0.15))
                        .foregroundStyle(document.invoiceStatus.chipColor)
                        .clipShape(Capsule())
                    if !document.revisionOf.isEmpty {
                        Text("Revision")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
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
                HStack(spacing: 4) {
                    Button {
                        shareDocument(document)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    if document.invoiceStatus == .sent || document.invoiceStatus == .overdue {
                        Button("Paid") {
                            document.invoicePaidAt = Date()
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
                            revisePaidDoc = document
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
            forceIsInvoice: proposal.isInvoice
        )
        let prefix = proposal.isInvoice ? "Invoice" : "Proposal"
        let safe = client.name.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(safe)-\(proposal.id.uuidString.prefix(6)).pdf")
        try? data.write(to: url)

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else { return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = window
        var topVC = window.rootViewController
        while let presented = topVC?.presentedViewController { topVC = presented }
        topVC?.present(vc, animated: true)
    }

    private func createRevision(of original: Proposal) {
        let revisionCount = clientDocuments.filter { $0.revisionOf == original.invoiceNumber }.count
        let revision = Proposal(operatorID: original.operatorID, client: client)
        revision.invoiceNumber = "\(original.invoiceNumber)-R\(revisionCount + 1)"
        revision.revisionOf = original.invoiceNumber
        revision.discountAmount = original.discountAmount
        revision.taxRate = original.taxRate
        revision.disclaimer = original.disclaimer
        revision.notes = original.notes
        revision.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
        let copies = original.makeLineItemCopies()
        copies.forEach { modelContext.insert($0) }
        revision.lineItems = copies
        modelContext.insert(revision)
    }

    private func overwriteForEdit(_ proposal: Proposal) {
        // Reset to Draft so the operator can resend with updated info
        proposal.invoicePaidAt = nil
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
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
        let coords = zones.flatMap { $0.coordinates }
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: client.latitude, longitude: client.longitude),
                span: MKCoordinateSpan(latitudeDelta: 0.002, longitudeDelta: 0.002)
            )
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(
                latitudeDelta: max(0.0005, (maxLat - minLat) * 3.5),
                longitudeDelta: max(0.0005, (maxLon - minLon) * 3.5)
            )
        )
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

    private func saveChanges() {
        isSaving = true
        client.name = name
        client.phone = phone
        client.email = email
        client.skipNotificationPrompt = skipNotificationPrompt
        client.goalMinutes = goalMinutes
        client.defaultStopNotes = defaultStopNotes
        client.preferredPayment = preferredPayment
        client.isComped = isComped
        client.defaultDiscountPercent = defaultDiscountPercent
        client.tags = tags
        client.notes = notes
        client.isActive = isActive

        if let coord = geocodedCoordinate, address != originalAddress {
            client.address = address
            client.latitude = coord.latitude
            client.longitude = coord.longitude
            isSaving = false
            dismiss()
            return
        }

        if address != originalAddress, !address.isEmpty {
            client.address = address
            Task {
                let geocoder = CLGeocoder()
                if let placemark = try? await geocoder.geocodeAddressString(address).first,
                   let location = placemark.location {
                    client.latitude = location.coordinate.latitude
                    client.longitude = location.coordinate.longitude
                }
                await MainActor.run { isSaving = false; dismiss() }
            }
        } else {
            client.address = address
            isSaving = false
            dismiss()
        }
    }
}
