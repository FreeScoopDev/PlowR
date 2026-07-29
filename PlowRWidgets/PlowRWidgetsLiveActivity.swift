import ActivityKit
import WidgetKit
import SwiftUI

struct PlowRWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PlowRRouteAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color(.systemBackground))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "truck.box.fill")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.attributes.routeName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Text("Stop \(context.state.currentStopNumber) of \(context.state.totalStops)")
                                .font(.caption.bold())
                        }
                    }
                    .padding(.leading, 4)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ProgressView(
                        value: Double(context.state.currentStopNumber),
                        total: Double(context.state.totalStops)
                    )
                    .tint(.blue)
                    .frame(width: 60)
                    .padding(.trailing, 8)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.state.currentStopName)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            if !context.state.currentStopAddress.isEmpty {
                                Text(context.state.currentStopAddress)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Image(systemName: "location.fill")
                            .foregroundStyle(.blue)
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            } compactLeading: {
                HStack(spacing: 4) {
                    Image(systemName: "truck.box.fill")
                        .foregroundStyle(.blue)
                        .font(.caption2)
                    Text("\(context.state.currentStopNumber)/\(context.state.totalStops)")
                        .font(.caption2.bold())
                }
            } compactTrailing: {
                Text(context.state.currentStopName)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(maxWidth: 70)
            } minimal: {
                Image(systemName: "truck.box.fill")
                    .foregroundStyle(.blue)
            }
            .widgetURL(URL(string: "plowr://activeRoute"))
            .keylineTint(.blue)
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<PlowRRouteAttributes>

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "truck.box.fill")
                .font(.system(size: 28))
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text(context.attributes.routeName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(context.state.currentStopName)
                    .font(.headline)
                    .lineLimit(1)
                if !context.state.currentStopAddress.isEmpty {
                    Text(context.state.currentStopAddress)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(context.state.currentStopNumber)/\(context.state.totalStops)")
                    .font(.title3.bold())
                    .foregroundStyle(.blue)
                ProgressView(
                    value: Double(context.state.currentStopNumber),
                    total: Double(context.state.totalStops)
                )
                .tint(.blue)
                .frame(width: 50)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Previews

extension PlowRRouteAttributes {
    fileprivate static var preview: PlowRRouteAttributes {
        PlowRRouteAttributes(routeID: "preview", routeName: "Monday North Side")
    }
}

extension PlowRRouteAttributes.ContentState {
    fileprivate static var stop2: PlowRRouteAttributes.ContentState {
        .init(currentStopName: "Johnson Residence", currentStopAddress: "42 Oak St",
              currentStopNumber: 2, totalStops: 7, routeName: "Monday North Side")
    }
    fileprivate static var stop5: PlowRRouteAttributes.ContentState {
        .init(currentStopName: "Williams Commercial", currentStopAddress: "100 Main Ave",
              currentStopNumber: 5, totalStops: 7, routeName: "Monday North Side")
    }
}

#Preview("Lock Screen", as: .content, using: PlowRRouteAttributes.preview) {
    PlowRWidgetsLiveActivity()
} contentStates: {
    PlowRRouteAttributes.ContentState.stop2
    PlowRRouteAttributes.ContentState.stop5
}
