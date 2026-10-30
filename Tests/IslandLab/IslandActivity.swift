import ActivityKit
import Foundation

struct IslandActivity: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var end: Date
    }
    var label: String
}
