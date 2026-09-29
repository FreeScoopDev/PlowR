import SwiftUI
import SwiftData
import PhotosUI

struct StopServiceRecorderView: View {
    let stop: RouteStop
    let client: Client?
    let operatorID: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allServices: [ServiceItem]

    @State private var selectedServiceIDs: Set<String>
    @State private var notes: String
    @State private var servicePriceOverrides: [String: String] = [:]
    @State private var customItems: [CustomLineItem] = []

    // Photos
    @State private var beforePickerItems: [PhotosPickerItem] = []
    @State private var afterPickerItems: [PhotosPickerItem] = []
    @State private var beforeImages: [UIImage] = []
    @State private var afterImages: [UIImage] = []
    @State private var showingCamera = false
    @State private var cameraIsBefore = true

    init(stop: RouteStop, client: Client?, operatorID: String) {
        self.stop = stop
        self.client = client
        self.operatorID = operatorID
        _selectedServiceIDs = State(initialValue: Set(stop.completedServiceIDs))
        _notes = State(initialValue: stop.completedNotes)
    }

    private var myServices: [ServiceItem] {
        allServices
            .filter { $0.operatorID == operatorID && $0.isActive }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var pricingZones: [InvoiceLines.Zone] {
        client?.sortedZones.map { InvoiceLines.Zone(label: $0.label, areaSquareFeet: $0.areaSquareFeet) } ?? []
    }

    // For per-sqft services, the meaningful price is rate × total client area.
    // Drivers see and override the dollar total, not the per-sqft unit rate.
    private func defaultPrice(for service: ServiceItem) -> Double {
        InvoiceLines.propertyPrice(unitType: service.unitType, pricePerUnit: service.pricePerUnit,
                                   zones: pricingZones)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let client {
                    Section {
                        LabeledContent("Client", value: client.name)
                        if !client.address.isEmpty {
                            LabeledContent("Address", value: client.address)
                        }
                    }
                }

                photoSection(isBefore: true)
                photoSection(isBefore: false)

                Section("Services Performed") {
                    if myServices.isEmpty {
                        // A business that went straight to a route had none, and had
                        // to leave the route for Settings to get any.
                        StandardServicesOffer(operatorID: operatorID)
                    } else {
                        ForEach(myServices) { service in
                            let key = service.id.uuidString
                            let isOn = selectedServiceIDs.contains(key)
                            VStack(alignment: .leading, spacing: 0) {
                                Toggle(isOn: Binding(
                                    get: { isOn },
                                    set: { on in
                                        UIImpactFeedbackGenerator(style: on ? .medium : .light).impactOccurred()
                                        if on {
                                            selectedServiceIDs.insert(key)
                                            if servicePriceOverrides[key] == nil {
                                                servicePriceOverrides[key] = String(format: "%.2f", defaultPrice(for: service))
                                            }
                                        } else {
                                            selectedServiceIDs.remove(key)
                                        }
                                    }
                                )) {
                                    Text(service.name)
                                }
                                if isOn {
                                    HStack(spacing: 4) {
                                        Text("Price: $").font(.caption).foregroundStyle(.secondary)
                                        TextField("0.00", text: Binding(
                                            get: { servicePriceOverrides[key] ?? String(format: "%.2f", defaultPrice(for: service)) },
                                            set: { servicePriceOverrides[key] = $0 }
                                        ))
                                        .keyboardType(.decimalPad)
                                        .font(.caption)
                                        .frame(width: 72)
                                        if service.unitType == "perSqFt",
                                           case let area = InvoiceLines.totalArea(pricingZones),
                                           area > 0 {
                                            Text("(\(Int(area)) sqft)")
                                                .font(.caption2).foregroundStyle(.tertiary)
                                        }
                                    }
                                    .padding(.leading, 48)
                                    .padding(.bottom, 6)
                                }
                            }
                        }
                    }
                }

                Section("Custom Services") {
                    ForEach($customItems) { $item in
                        HStack(spacing: 8) {
                            TextField("Service name", text: $item.name)
                            Divider()
                            Text("$").foregroundStyle(.secondary)
                            TextField("0.00", text: $item.price)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                customItems.removeAll { $0.id == item.id }
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        customItems.append(CustomLineItem())
                    } label: {
                        Label("Add Custom Item", systemImage: "plus")
                    }
                }

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
                    Button("Skip") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu("Save Invoice") {
                        Button {
                            saveInvoice(markSent: false)
                        } label: {
                            Label("Save as Draft", systemImage: "doc.badge.clock")
                        }
                        Button {
                            saveInvoice(markSent: true)
                        } label: {
                            Label("Save & Mark Sent", systemImage: "paperplane.fill")
                        }
                    }
                    .disabled(selectedServiceIDs.isEmpty || client == nil)
                }
            }
            .sheet(isPresented: $showingCamera) {
                CameraPickerView { image in
                    if cameraIsBefore { beforeImages.append(image) }
                    else { afterImages.append(image) }
                }
            }
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
                                Image(uiImage: images[idx])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 80, height: 80)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)

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
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Image Loading

    private func loadImages(from items: [PhotosPickerItem], appending: @escaping (UIImage) -> Void) {
        for item in items {
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data) = result, let data, let image = UIImage(data: data) {
                    DispatchQueue.main.async { appending(image) }
                }
            }
        }
    }

    // MARK: - Save

    private func saveInvoice(markSent: Bool) {
        stop.completedServiceIDs = Array(selectedServiceIDs)
        stop.completedNotes = notes

        // Save photos
        let clientID = client?.id.uuidString ?? ""
        let routeID = stop.route?.id.uuidString ?? ""
        for image in beforeImages {
            if let data = image.jpegData(compressionQuality: 0.8) {
                let photo = StopPhoto(operatorID: operatorID, clientID: clientID, routeID: routeID, isBefore: true, imageData: data)
                modelContext.insert(photo)
            }
        }
        for image in afterImages {
            if let data = image.jpegData(compressionQuality: 0.8) {
                let photo = StopPhoto(operatorID: operatorID, clientID: clientID, routeID: routeID, isBefore: false, imageData: data)
                modelContext.insert(photo)
            }
        }

        guard let client else { dismiss(); return }

        let proposal = Proposal(operatorID: operatorID, client: client)
        proposal.invoiceNumber = InvoiceNumbering.next(operatorID: operatorID, in: modelContext)
        proposal.invoiceDueDate = Date().addingTimeInterval(30 * 86400)
        if !notes.isEmpty { proposal.notes = notes }

        var lineItems: [ProposalLineItem] = []
        var sortIndex = 0

        for service in myServices where selectedServiceIDs.contains(service.id.uuidString) {
            let key = service.id.uuidString
            // The whole-property figure the driver saw, or typed over. An empty
            // or unreadable field means it was left alone (see InvoiceLines).
            let lines = InvoiceLines.lines(serviceName: service.name, unitType: service.unitType,
                                           pricePerUnit: service.pricePerUnit,
                                           zones: pricingZones, typedPrice: servicePriceOverrides[key])
            for line in lines {
                let item = ProposalLineItem(
                    serviceName: line.serviceName,
                    zoneLabel: line.zoneLabel,
                    quantity: line.quantity,
                    unitType: line.unitType,
                    unitPrice: line.unitPrice,
                    sortOrder: sortIndex
                )
                item.lineTotal = line.lineTotal
                lineItems.append(item)
                sortIndex += 1
            }
        }

        for (i, custom) in customItems.enumerated() {
            guard !custom.name.isEmpty, let price = Double(custom.price), price > 0 else { continue }
            let item = ProposalLineItem(
                serviceName: custom.name,
                zoneLabel: "",
                quantity: 1,
                unitType: "flat",
                unitPrice: price,
                sortOrder: sortIndex + i
            )
            lineItems.append(item)
        }

        lineItems.forEach { modelContext.insert($0) }
        proposal.lineItems = lineItems
        if markSent {
            proposal.invoiceSentAt = Date()
        }
        modelContext.insert(proposal)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Supporting Types

private struct CustomLineItem: Identifiable {
    let id = UUID()
    var name: String = ""
    var price: String = ""
}

// MARK: - Camera Picker

struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        init(onCapture: @escaping (UIImage) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
