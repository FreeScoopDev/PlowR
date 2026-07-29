import SwiftUI

struct WorkOrderRequestView: View {
    let zones: [ClientZoneDraft]
    let business: BusinessResult
    let category: String
    let propertyAddress: String

    @AppStorage("clientName") private var clientName = ""
    @AppStorage("clientPhone") private var clientPhone = ""
    @AppStorage("clientEmail") private var clientEmail = ""
    @Environment(ClientWorkOrderStore.self) private var workOrderStore
    @State private var notes = ""
    @State private var showShareSheet = false
    @State private var shareMessage = ""

    private var totalArea: Double { zones.reduce(0) { $0 + $1.areaSquareFeet } }

    var body: some View {
        Form {
            Section("Your Contact Info") {
                TextField("Full Name", text: $clientName)
                    .textContentType(.name)
                TextField("Phone Number", text: $clientPhone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                TextField("Email (optional)", text: $clientEmail)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }

            Section("Property & Service") {
                LabeledContent("Address", value: propertyAddress)
                LabeledContent("Service", value: category)
                ForEach(zones) { zone in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(zone.label).font(.subheadline)
                            Text(zoneDetail(zone)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(zone.rateType == "flat" ? "Flat rate" : "Per sq ft")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Total Area", value: "\(Int(totalArea)) sq ft")
            }

            Section("Notes") {
                TextField("Special instructions, access codes, obstacles...", text: $notes, axis: .vertical)
                    .lineLimit(4...)
            }

            Section {
                Button {
                    shareMessage = buildMessage()
                    let order = ClientWorkOrder(
                        businessName: business.name,
                        businessPhone: business.phone,
                        category: category,
                        propertyAddress: propertyAddress,
                        totalAreaSqFt: totalArea,
                        notes: notes,
                        submittedAt: Date(),
                        messageText: shareMessage
                    )
                    workOrderStore.add(order)
                    showShareSheet = true
                } label: {
                    Label("Send Work Order Request", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                        .font(.headline)
                }
                .disabled(clientName.isEmpty || clientPhone.isEmpty)
            } footer: {
                if clientName.isEmpty || clientPhone.isEmpty {
                    Text("Add your name and phone number to send.")
                }
            }
        }
        .navigationTitle("Work Order Request")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showShareSheet) {
            WorkOrderShareSheet(message: shareMessage)
        }
    }

    private func zoneDetail(_ zone: ClientZoneDraft) -> String {
        var parts = ["\(Int(zone.areaSquareFeet)) sq ft"]
        if zone.elevationGrade > 1 {
            parts.append("grade \(String(format: "%.1f", zone.elevationGrade))%")
        }
        return parts.joined(separator: " · ")
    }

    private func buildMessage() -> String {
        var lines: [String] = []
        lines.append("SERVICE REQUEST via PlowR")
        lines.append("")
        lines.append("To: \(business.name)")
        if !business.phone.isEmpty { lines.append("Phone: \(business.phone)") }
        if !business.address.isEmpty { lines.append("Address: \(business.address)") }
        lines.append("")
        lines.append("From: \(clientName)")
        lines.append("Phone: \(clientPhone)")
        if !clientEmail.isEmpty { lines.append("Email: \(clientEmail)") }
        lines.append("")
        lines.append("Property: \(propertyAddress)")
        lines.append("Service Requested: \(category)")
        lines.append("")
        lines.append("Property Zones:")
        for zone in zones {
            var line = "• \(zone.label): \(Int(zone.areaSquareFeet)) sq ft"
            if zone.elevationGrade > 1 {
                line += " (grade: \(String(format: "%.1f", zone.elevationGrade))%)"
            }
            line += zone.rateType == "flat" ? " — flat rate" : " — per sq ft"
            lines.append(line)
        }
        lines.append("Total area: \(Int(totalArea)) sq ft")
        if !notes.isEmpty {
            lines.append("")
            lines.append("Notes: \(notes)")
        }
        lines.append("")
        lines.append("— Sent via PlowR")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Share Sheet

struct WorkOrderShareSheet: UIViewControllerRepresentable {
    let message: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [message], applicationActivities: nil)
    }
    func updateUIViewController(_ uvc: UIActivityViewController, context: Context) {}
}
