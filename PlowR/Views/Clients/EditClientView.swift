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

    @State private var name: String
    @State private var phone: String
    @State private var address: String
    @State private var skipNotificationPrompt: Bool
    @State private var goalMinutes: Int
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
    @State private var sharingDocumentURL: URL?
    @State private var showingShareSheet = false
    @State private var revisePaidDoc: Proposal?
    @State private var editingProposal: Proposal?

    init(client: Client) {
        self.client = client
        self.originalAddress = client.address
        _name = State(initialValue: client.name)
        _phone = State(initialValue: client.phone)
        _address = State(initialValue: client.address)
        _skipNotificationPrompt = State(initialValue: client.skipNotificationPrompt)
        _goalMinutes = State(initialValue: client.goalMinutes)
    }

    // MARK: - Body

    var body: some View {
        Form {
            contactSection
            serviceAddressSection
            historySection
            documentsSection
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
        .sheet(isPresented: $showingShareSheet) {
            if let url = sharingDocumentURL {
                ProposalShareSheet(url: url)
            }
        }
        .sheet(item: $editingProposal) { proposal in
            ProposalEditView(proposal: proposal)
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
                HStack(spacing: 12) {
                    Button {
                        showingLocationAdjust = true
                    } label: {
                        Label("Adjust Pin", systemImage: "mappin.and.ellipse")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        loadLookAround()
                    } label: {
                        if isLoadingLookAround {
                            ProgressView().scaleEffect(0.8)
                        } else {
                            Label("Street View", systemImage: "binoculars")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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

                    if document.invoiceStatus == .draft || document.invoiceStatus == .sent {
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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(client.name).pdf")
        try? data.write(to: url)
        sharingDocumentURL = url
        showingShareSheet = true
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
        let copies = (original.lineItems ?? []).map { item in
            ProposalLineItem(
                serviceName: item.serviceName,
                zoneLabel: item.zoneLabel,
                quantity: item.quantity,
                unitType: item.unitType,
                unitPrice: item.unitPrice,
                sortOrder: item.sortOrder,
                itemNotes: item.itemNotes
            )
        }
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
        client.skipNotificationPrompt = skipNotificationPrompt
        client.goalMinutes = goalMinutes

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
