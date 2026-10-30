import ActivityKit
import SwiftUI

@main
struct IslandLabApp: App {
    @State private var status = "Synthetic Live Activity for DuoBrowser review"
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 24) {
                Image(systemName: "timer").font(.largeTitle)
                Text("DuoBrowser Island Lab").font(.title)
                Text(status).multilineTextAlignment(.center)
                Button("Start test activity") { start() }.buttonStyle(.borderedProminent)
                Button("End test activity") { Task { await stop() } }
                Text("Return to DuoBrowser, then press and hold the island to expand it. No network or personal data is used.")
                    .font(.footnote).foregroundStyle(.secondary)
            }.padding(32)
            .task {
                if CommandLine.arguments.contains("--stop") { await stop() }
                else if CommandLine.arguments.contains("--start") { start() }
            }
        }
    }
    private func start() {
        do {
            guard Activity<IslandActivity>.activities.isEmpty else { status = "Test activity is already running"; return }
            let content = ActivityContent(state: IslandActivity.ContentState(end: Date().addingTimeInterval(3600)), staleDate: nil)
            _ = try Activity<IslandActivity>.request(attributes: IslandActivity(label: "Browser review"), content: content, pushType: nil)
            status = "Test activity running — return to DuoBrowser"
        } catch { status = "Could not start: \(error.localizedDescription)" }
    }
    private func stop() async {
        for activity in Activity<IslandActivity>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
        status = "Test activity ended"
    }
}
