import SwiftData
import SwiftUI

/// The Service Report for one of a client's places over a period: which
/// place (an inactive or removed one too), which period (a contract's
/// season, the last 30 days, this year, or chosen dates), how many visits
/// that covers, and the PDF to share (ProofOfService).
struct ProofOfServiceView: View {
    let client: Client

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allProfiles: [BusinessProfile]

    @State private var placeID: String
    @State private var periodID: String?
    @State private var customStart = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now
    @State private var customEnd = Date.now
    @State private var pdfURL: URL?
    @State private var isMaking = false

    init(client: Client) {
        self.client = client
        _placeID = State(initialValue: client.id.uuidString)
    }

    private static let customID = "custom"

    private var places: [ProofOfService.ReportPlace] { ProofOfService.places(of: client, in: modelContext) }
    private var periods: [ProofOfService.Period] { ProofOfService.periods(for: client, placeID: placeID) }

    private var period: ProofOfService.Period {
        if periodID == Self.customID {
            return ProofOfService.Period(label: "Chosen Dates", start: customStart, end: max(customStart, customEnd))
        }
        return periods.first { $0.id == periodID } ?? periods.first
            ?? ProofOfService.Period(label: "This Year", start: .now, end: .now)
    }

    private var visits: [ProofOfService.Visit] {
        ProofOfService.visits(of: client, placeID: placeID, from: period.start, to: period.end, in: modelContext)
    }

    var body: some View {
        NavigationStack {
            Form {
                if places.count > 1 {
                    Picker("Property", selection: $placeID) {
                        ForEach(places) { place in Text(place.label).tag(place.id) }
                    }
                }
                Section {
                    Picker("Period", selection: Binding(get: { periodID ?? periods.first?.id }, set: { periodID = $0 })) {
                        ForEach(periods) { Text($0.label).tag(Optional($0.id)) }
                        Text("Chosen Dates").tag(Optional(Self.customID))
                    }
                    if periodID == Self.customID {
                        DatePicker("From", selection: $customStart, in: ...Date.now, displayedComponents: .date)
                        DatePicker("To", selection: $customEnd, in: customStart...Date.now, displayedComponents: .date)
                    }
                    let visits = visits
                    LabeledContent("Visits", value: "\(visits.count)")
                    LabeledContent("Photos", value: "\(visits.reduce(0) { $0 + $1.photos.count })")
                } footer: {
                    Text("Only what PlowR recorded: route stops' times (including travel to them), where each record came from, the services, notes and photos.")
                }
                Section {
                    if let pdfURL {
                        ShareLink(item: pdfURL) {
                            Label("Share Service Report", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button {
                            makePDF()
                        } label: {
                            if isMaking {
                                ProgressView()
                            } else {
                                Label("Make PDF", systemImage: "doc.richtext")
                            }
                        }
                        .disabled(isMaking)
                    }
                } footer: {
                    Text("Every visit at the property in the period: for an insurer, a lawyer, or a client who asks.")
                }
            }
            .navigationTitle("Service Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            // A different place or period: the PDF is made again.
            .onChange(of: placeID) { pdfURL = nil; periodID = nil }
            .onChange(of: periodID) { pdfURL = nil }
            .onChange(of: customStart) { pdfURL = nil }
            .onChange(of: customEnd) { pdfURL = nil }
        }
    }

    private func makePDF() {
        isMaking = true
        Task { @MainActor in
            await Task.yield()
            let place = places.first { $0.id == placeID }
                ?? ProofOfService.ReportPlace(id: placeID, label: client.name, address: client.address)
            let profile = allProfiles.first { $0.operatorID == client.operatorID }
            let data = ProofOfService.pdf(client: client, place: place, period: period, visits: visits, profile: profile)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(ProofOfService.fileName(client: client, period: period))
            if (try? data.write(to: url)) != nil { pdfURL = url }
            isMaking = false
        }
    }
}
