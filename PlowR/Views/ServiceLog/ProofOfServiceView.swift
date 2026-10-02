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
    /// A report whose weather couldn't be looked up, while that's asked.
    @State private var failedSnapshot: Snapshot?

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

    private var checks: [ProofOfService.Check] {
        ProofOfService.checks(of: client, placeID: placeID, from: period.start, to: period.end, in: modelContext)
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
                    let checks = checks
                    if !checks.isEmpty {
                        LabeledContent("Days Below Trigger", value: "\(checks.count)")
                    }
                } footer: {
                    Text("What PlowR recorded (route stops' times, including travel to them, where each record came from, the services, notes and photos), and each visit day's estimated weather, looked up when it's made.")
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
            // Nothing changes under a report being made.
            .disabled(isMaking)
            .alert("Weather couldn't be looked up", isPresented: Binding(get: { failedSnapshot != nil },
                                                                         set: { if !$0 { failedSnapshot = nil } })) {
                Button("Try Again") {
                    failedSnapshot = nil
                    makePDF()
                }
                Button("Make Without Weather") {
                    if let snapshot = failedSnapshot { write(snapshot, weather: .failed) }
                    failedSnapshot = nil
                }
                Button("Cancel", role: .cancel) { failedSnapshot = nil }
            } message: {
                Text("No signal, or the weather service didn't answer. Without it, the report says the weather couldn't be looked up.")
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

    /// What a report is made from, taken when Make PDF is tapped: changing
    /// the place or period while the weather is looked up can't mix them.
    private struct Snapshot {
        let place: ProofOfService.ReportPlace
        let period: ProofOfService.Period
        let visits: [ProofOfService.Visit]
        let checks: [ProofOfService.Check]
    }

    private func makePDF() {
        let snapshot = Snapshot(
            place: places.first { $0.id == placeID }
                ?? ProofOfService.ReportPlace(id: placeID, label: client.name, address: client.address),
            period: period, visits: visits, checks: checks)
        isMaking = true
        Task { @MainActor in
            let weather = await VisitWeather.lookUp(
                latitude: snapshot.place.latitude, longitude: snapshot.place.longitude,
                visitDays: snapshot.visits.map { $0.record.startedAt ?? $0.record.performedAt }
                    + snapshot.checks.map(\.check.day))
            isMaking = false
            if weather == .failed {
                failedSnapshot = snapshot
            } else {
                write(snapshot, weather: weather)
            }
        }
    }

    private func write(_ snapshot: Snapshot, weather: VisitWeather.Lookup) {
        let profile = allProfiles.first { $0.operatorID == client.operatorID }
        let data = ProofOfService.pdf(client: client, place: snapshot.place, period: snapshot.period,
                                      visits: snapshot.visits, checks: snapshot.checks, profile: profile,
                                      weather: weather)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(ProofOfService.fileName(client: client, period: snapshot.period))
        if (try? data.write(to: url)) != nil { pdfURL = url }
    }
}
