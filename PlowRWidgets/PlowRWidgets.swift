import WidgetKit
import SwiftUI

// MARK: - Data (TodayRouteWidgetData, shared with the app: WidgetDataStore.swift)

extension TodayRouteWidgetData {
    /// What the app last wrote, or an empty route.
    static func current() -> TodayRouteWidgetData { WidgetDataStore.read() ?? TodayRouteWidgetData() }

    static let placeholder = TodayRouteWidgetData(
        routeName: "Monday Route",
        totalStops: 8, completedStops: 3,
        nextStopName: "Johnson Residence",
        nextStopAddress: "42 Oak Street",
        isActive: true,
        lastUpdated: Date()
    )
}

// MARK: - Timeline Entry

struct RouteEntry: TimelineEntry {
    let date: Date
    let data: TodayRouteWidgetData
}

// MARK: - Provider

struct PlowRWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> RouteEntry {
        RouteEntry(date: Date(), data: .placeholder)
    }
    func getSnapshot(in context: Context, completion: @escaping (RouteEntry) -> Void) {
        completion(RouteEntry(date: Date(), data: .current()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RouteEntry>) -> Void) {
        let entry = RouteEntry(date: Date(), data: .current())
        let refresh = Date().addingTimeInterval(5 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

// MARK: - Widget Views

struct PlowRWidgetEntryView: View {
    var entry: RouteEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium: mediumView
            default:            smallView
            }
        }
        .widgetURL(URL(string: "plowr://activeRoute"))
    }

    // MARK: Small

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 5) {
                Image(systemName: "truck.box.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.blue)
                Text("PlowR")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if entry.data.isActive {
                Spacer()
                Text(entry.data.routeName)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(entry.data.stopLine)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 1)
                ProgressView(value: entry.data.progress)
                    .tint(.blue)
                    .padding(.vertical, 5)
                Text(entry.data.nextStopName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            } else if entry.data.isComplete {
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("Route Complete")
                    .font(.subheadline.bold())
                    .padding(.top, 4)
                Text("\(entry.data.completedStops) stops done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                Spacer()
                Image(systemName: "map")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No Active\nRoute")
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .padding(.top, 4)
                Spacer()
            }
        }
        .padding(12)
    }

    // MARK: Medium

    private var mediumView: some View {
        HStack(spacing: 14) {
            if entry.data.isActive {
                // Left column — icon + numeric progress
                VStack(spacing: 6) {
                    Image(systemName: "truck.box.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("\(entry.data.completedStops)/\(entry.data.totalStops)")
                        .font(.title3.bold())
                        .foregroundStyle(.blue)
                    Text("stops")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 64)

                Divider()

                // Right column — route name, progress bar, next stop
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(entry.data.routeName)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        Spacer()
                        Label("Active", systemImage: "circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    ProgressView(value: entry.data.progress)
                        .tint(.blue)
                    if !entry.data.nextStopName.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NEXT STOP")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(entry.data.nextStopName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            if !entry.data.nextStopAddress.isEmpty {
                                Text(entry.data.nextStopAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }

            } else if entry.data.isComplete {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Route Complete")
                        .font(.headline.bold())
                    Text(entry.data.routeName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(entry.data.completedStops) stops completed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

            } else {
                Image(systemName: "map.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PlowR")
                        .font(.headline.bold())
                    Text("No active route")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Open the app to start a route")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
            }
        }
        .padding(14)
    }
}

// MARK: - Widget Definition

struct PlowRTodayRouteWidget: Widget {
    let kind: String = "PlowRTodayRoute"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PlowRWidgetProvider()) { entry in
            PlowRWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Route")
        .description("See your active route progress and next stop at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Previews

#Preview("Small — Active", as: .systemSmall) {
    PlowRTodayRouteWidget()
} timeline: {
    RouteEntry(date: .now, data: .placeholder)
}

#Preview("Small — Idle", as: .systemSmall) {
    PlowRTodayRouteWidget()
} timeline: {
    RouteEntry(date: .now, data: TodayRouteWidgetData())
}

#Preview("Medium — Active", as: .systemMedium) {
    PlowRTodayRouteWidget()
} timeline: {
    RouteEntry(date: .now, data: .placeholder)
}
