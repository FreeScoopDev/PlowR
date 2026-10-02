import SwiftUI

/// The Dashboard's storm card (StormWatch): the snowfall forecast, which
/// contract clients' triggers it reaches, a text to those clients, and the
/// routes, each opening its page, where Message All Clients and Start are.
/// Snow-only, so it lives apart from the shared Dashboard.
struct StormCard: View {
    let storm: StormWatch.Storm
    let routes: [PlowRoute]
    let clients: [Client]
    /// Opens the message screen for these clients. The Dashboard holds the
    /// sheet: this card goes when the storm does (midnight, a synced change),
    /// and mustn't take a send part-way through with it.
    let text: ([Client]) -> Void
    /// Marks a client below their trigger that day (true), or takes the mark
    /// off (false): less fell at their place than the forecast said.
    let mark: (StormWatch.Trigger, Bool) -> Void

    static let presets: [(String, String)] = [
        ("Storm Coming", "Snow is in the forecast. We'll be out to clear your property once it reaches the depth in your contract."),
        ("Clearing Today", "We're out clearing snow today and will be at your property as soon as we can."),
        ("Please Move Vehicles", "Please move any vehicles from the driveway so we can clear it fully.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Storm", systemImage: "cloud.snow.fill")
                .font(.subheadline.weight(.semibold))
            DashCard {
                VStack(alignment: .leading, spacing: 0) {
                    forecast.padding(14)
                    if !storm.met.isEmpty || !storm.notMet.isEmpty || !storm.markedBelow.isEmpty {
                        Divider()
                        triggers.padding(14)
                    }
                    if !reachedWithPhones.isEmpty {
                        Divider()
                        textButton
                    }
                    Divider()
                    routeLinks
                }
            }
        }
    }

    /// The clients whose trigger the forecast reaches, with a phone on file.
    private var reachedWithPhones: [Client] {
        let ids = Set(storm.met.map(\.clientID))
        return clients.filter { ids.contains($0.id.uuidString) && !$0.phone.isEmpty }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var textButton: some View {
        // No count: clients who'd rather not be texted are listed but start
        // unticked, as on a route's Message All.
        Button { text(reachedWithPhones) } label: {
            Label("Text Clients Whose Trigger It Reaches", systemImage: "bubble.left.and.bubble.right")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private var forecast: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(StormWatch.dayName(storm.day)): about \(StormWatch.amount(storm.inches)) of snow")
                .font(.headline)
            Text("Forecast for your area over the whole day (a weather model's estimate), not a measurement at each property.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var triggers: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !storm.met.isEmpty {
                DisclosureGroup {
                    names(storm.met, marked: false)
                } label: {
                    Label {
                        Text("\(count(storm.met)) reached")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    .font(.subheadline)
                }
            }
            if !storm.notMet.isEmpty {
                DisclosureGroup {
                    names(storm.notMet, marked: false)
                } label: {
                    Label("\(count(storm.notMet)) not reached", systemImage: "circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if !storm.markedBelow.isEmpty {
                DisclosureGroup {
                    names(storm.markedBelow, marked: true)
                } label: {
                    Label("\(storm.markedBelow.count) marked below trigger at the property",
                          systemImage: "arrow.down.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Less fell at a client's place than forecast? Mark them below trigger: they're left out of the text, and their stops start skipped on the route.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func count(_ triggers: [StormWatch.Trigger]) -> String {
        "\(triggers.count) contract trigger\(triggers.count == 1 ? "" : "s")"
    }

    private func names(_ triggers: [StormWatch.Trigger], marked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(triggers) { trigger in
                HStack {
                    Text(trigger.clientName.isEmpty ? "Client" : trigger.clientName)
                    Spacer()
                    Text(trigger.label).foregroundStyle(.secondary)
                    Menu {
                        if marked && storm.checkedAtStop.contains(trigger.clientID) {
                            // The crew's record, with its photos: removed only on the contract's page.
                            Text("Checked at the stop. Change it on the contract's page.")
                        } else if marked {
                            Button("Not Below Trigger", systemImage: "arrow.uturn.backward") { mark(trigger, false) }
                        } else {
                            Button("Below Trigger at Their Place", systemImage: "arrow.down.circle") {
                                mark(trigger, true)
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .frame(minWidth: 44, minHeight: 32)     // In gloves, too.
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Options for \(trigger.clientName)")
                }
                .font(.subheadline)
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder
    private var routeLinks: some View {
        if routes.isEmpty {
            Text("No routes yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(14)
        } else {
            Text("Open a route to message its clients and start it.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            ForEach(routes) { route in
                NavigationLink { RouteDetailView(route: route) } label: {
                    HStack {
                        Label(route.name, systemImage: "map")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
