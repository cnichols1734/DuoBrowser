import ActivityKit
import SwiftUI
import WidgetKit

@main
struct IslandLabWidgets: WidgetBundle {
    var body: some Widget { IslandLabWidget() }
}

struct IslandLabWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IslandActivity.self) { context in
            HStack {
                Image(systemName: "timer")
                Text(context.attributes.label)
                Spacer()
                Text(timerInterval: min(Date(), context.state.end)...context.state.end, countsDown: true).monospacedDigit()
            }.padding().activityBackgroundTint(.orange.opacity(0.15))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { Image(systemName: "timer").foregroundStyle(.orange) }
                DynamicIslandExpandedRegion(.trailing) { Text("TEST").font(.caption) }
                DynamicIslandExpandedRegion(.center) { Text(context.attributes.label) }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(timerInterval: min(Date(), context.state.end)...context.state.end, countsDown: true).font(.title2).monospacedDigit()
                }
            } compactLeading: {
                Image(systemName: "timer").foregroundStyle(.orange)
            } compactTrailing: {
                Text(timerInterval: min(Date(), context.state.end)...context.state.end, countsDown: true).monospacedDigit().frame(width: 48)
            } minimal: {
                Image(systemName: "timer").foregroundStyle(.orange)
            }.keylineTint(.orange)
        }
    }
}
