import SwiftUI

/// The Dashboard's storm card (StormWatch): the snowfall forecast, which
/// contract clients' triggers it reaches, and the routes, each opening its
/// page, where Message All Clients and Start are. Snow-only, so it lives
/// apart from the shared Dashboard.
struct StormCard: View {
    let storm: StormWatch.Storm
    let routes: [PlowRoute]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Storm", systemImage: "cloud.snow.fill")
                .font(.subheadline.weight(.semibold))
            VStack(alignment: .leading, spacing: 0) {
                forecast.padding(14)
                if !storm.met.isEmpty || !storm.notMet.isEmpty {
                    Divider()
                    triggers.padding(14)
                }
                Divider()
                routeLinks
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: PlowRLayout.cornerLarge, style: .continuous))
        }
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
                    names(storm.met)
                } label: {
                    Label("\(count(storm.met)) at or below the forecast", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }
                .tint(.green)
            }
            if !storm.notMet.isEmpty {
                DisclosureGroup {
                    names(storm.notMet)
                } label: {
                    Label("\(count(storm.notMet)) above it", systemImage: "circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func count(_ triggers: [StormWatch.Trigger]) -> String {
        "\(triggers.count) contract trigger\(triggers.count == 1 ? "" : "s")"
    }

    private func names(_ triggers: [StormWatch.Trigger]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(triggers) { trigger in
                HStack {
                    Text(trigger.clientName.isEmpty ? "Client" : trigger.clientName)
                    Spacer()
                    Text("\(StormWatch.amount(trigger.inches)) trigger").foregroundStyle(.secondary)
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
