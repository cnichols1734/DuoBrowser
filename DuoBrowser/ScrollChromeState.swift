import Foundation

/// Scroll policy independent of UIKit, so bounce and direction changes can be tested directly.
struct ScrollChromeState {
    private(set) var isCollapsed = false
    private var previousOffset: Double?
    private var directionalDistance = 0.0
    private var waitingForDrag = false

    mutating func beginDragging(at offset: Double) {
        previousOffset = offset
        directionalDistance = 0
        waitingForDrag = false
    }

    mutating func reveal() {
        isCollapsed = false
        previousOffset = nil
        directionalDistance = 0
        // Tapping the pill during deceleration must not immediately hide it again.
        waitingForDrag = true
    }

    mutating func resetTracking() {
        previousOffset = nil
        directionalDistance = 0
    }

    mutating func update(offset: Double, maximumOffset: Double,
                         userScrolling: Bool, keepExpanded: Bool) {
        let maximum = max(0, maximumOffset)
        let position = min(maximum, max(0, offset))
        defer { previousOffset = position }

        if keepExpanded || maximum < 80 || position <= 12 || waitingForDrag {
            isCollapsed = false
            directionalDistance = 0
            return
        }

        // Compare clamped positions: a fast fling can first report beyond the bottom,
        // but its real travel to the edge still counts. The elastic rebound then adds no delta.
        guard userScrolling, let previousOffset else {
            directionalDistance = 0
            return
        }

        let delta = position - previousOffset
        guard abs(delta) > 0.1 else { return }
        if delta * directionalDistance < 0 { directionalDistance = 0 }
        directionalDistance += delta

        if !isCollapsed, position > 72, directionalDistance >= 44 {
            isCollapsed = true
            directionalDistance = 0
        } else if isCollapsed, directionalDistance <= -20 {
            isCollapsed = false
            directionalDistance = 0
        }
    }
}
