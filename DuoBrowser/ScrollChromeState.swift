import Foundation

/// A continuous gesture-driven transition, with a small reversal deadband to ignore jitter.
struct ScrollChromeState {
    private(set) var progress = 0.0
    var isCollapsed: Bool { progress > 0.5 }
    private var previousOffset: Double?
    private var directionalDistance = 0.0
    private var anchorProgress = 0.0
    private var waitingForDrag = false

    mutating func beginDragging(at offset: Double) {
        previousOffset = offset
        directionalDistance = 0
        anchorProgress = progress
        waitingForDrag = false
    }

    mutating func reveal() {
        progress = 0
        previousOffset = nil
        directionalDistance = 0
        anchorProgress = 0
        waitingForDrag = true
    }

    mutating func resetTracking() {
        previousOffset = nil
        directionalDistance = 0
        anchorProgress = progress
    }

    mutating func settle() {
        progress = isCollapsed ? 1 : 0
        resetTracking()
    }

    mutating func update(offset: Double, maximumOffset: Double,
                         userScrolling: Bool, keepExpanded: Bool) {
        let maximum = max(0, maximumOffset)
        let position = min(maximum, max(0, offset))
        defer { previousOffset = position }
        if keepExpanded || maximum < 80 || position <= 12 || waitingForDrag {
            progress = 0
            directionalDistance = 0
            anchorProgress = 0
            return
        }
        guard userScrolling, let previousOffset else {
            directionalDistance = 0
            anchorProgress = progress
            return
        }
        // Clamping both positions counts fast flings but excludes elastic bounce travel.
        let delta = position - min(maximum, max(0, previousOffset))
        guard abs(delta) > 0.1 else { return }
        if delta * directionalDistance < 0 {
            directionalDistance = 0
            anchorProgress = progress
        }
        directionalDistance += delta
        if directionalDistance > 0, position > 72 {
            progress = min(1, anchorProgress + max(0, directionalDistance - 12) / 64)
        } else if directionalDistance < 0 {
            progress = max(0, anchorProgress - max(0, -directionalDistance - 12) / 20)
        }
    }
}
