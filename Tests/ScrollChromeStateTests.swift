import Foundation

@main
struct ScrollChromeStateTests {
    static func main() {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
            precondition(condition(), description)
            checks += 1
        }
        func downScrolled() -> ScrollChromeState {
            var state = ScrollChromeState()
            state.beginDragging(at: 0)
            state.update(offset: 90, maximumOffset: 1_000, userScrolling: true, keepExpanded: false)
            return state
        }

        var state = downScrolled()
        expect(state.isCollapsed, "A deliberate downward scroll collapses controls")
        state.update(offset: 80, maximumOffset: 1_000, userScrolling: true, keepExpanded: false)
        expect(state.isCollapsed, "A small reverse movement does not flicker the bar")
        state.update(offset: 68, maximumOffset: 1_000, userScrolling: true, keepExpanded: false)
        expect(!state.isCollapsed, "Sustained upward scrolling restores controls")

        state = ScrollChromeState()
        state.beginDragging(at: 100)
        for offset in [110.0, 105, 115, 108, 120, 110] {
            state.update(offset: offset, maximumOffset: 1_000, userScrolling: true, keepExpanded: false)
        }
        expect(!state.isCollapsed, "Direction changes reset the hide threshold")

        state = ScrollChromeState()
        state.beginDragging(at: 0)
        state.update(offset: 60, maximumOffset: 1_000, userScrolling: true, keepExpanded: false)
        expect(!state.isCollapsed, "Controls stay visible near the page top")
        state.update(offset: 500, maximumOffset: 1_000, userScrolling: false, keepExpanded: false)
        expect(!state.isCollapsed, "Programmatic scrolls do not hide controls")

        state = downScrolled()
        state.reveal()
        state.update(offset: 600, maximumOffset: 1_000, userScrolling: true, keepExpanded: false)
        expect(!state.isCollapsed, "A tap during momentum keeps the revealed controls visible")
        state.beginDragging(at: 600)
        state.update(offset: 650, maximumOffset: 1_000, userScrolling: true, keepExpanded: false)
        expect(state.isCollapsed, "The next intentional drag can collapse them again")

        state.beginDragging(at: 990)
        for offset in [1010.0, 1030, 1020, 1010, 1000] {
            state.update(offset: offset, maximumOffset: 1_000, userScrolling: true, keepExpanded: false)
        }
        expect(state.isCollapsed, "Bottom bounce does not masquerade as an upward scroll")
        state.update(offset: 0, maximumOffset: 1_000, userScrolling: false, keepExpanded: false)
        expect(!state.isCollapsed, "Returning to page top restores controls, even programmatically")

        state = downScrolled()
        state.update(offset: 100, maximumOffset: 1_000, userScrolling: true, keepExpanded: true)
        expect(!state.isCollapsed, "Keyboard and accessibility modes force expanded controls")

        state = downScrolled()
        state.update(offset: 50, maximumOffset: 60, userScrolling: true, keepExpanded: false)
        expect(!state.isCollapsed, "Short pages do not collapse the controls")

        state = downScrolled()
        state.resetTracking()
        state.update(offset: 350, maximumOffset: 1_000, userScrolling: false, keepExpanded: false)
        expect(state.isCollapsed, "A background layout change does not expand a collapsed bar")
        state.beginDragging(at: 350)
        state.update(offset: 325, maximumOffset: 1_000, userScrolling: true, keepExpanded: false)
        expect(!state.isCollapsed, "A fresh upward gesture restores controls after layout changes")

        state = ScrollChromeState()
        state.beginDragging(at: 0)
        state.update(offset: 1_500, maximumOffset: 737, userScrolling: true, keepExpanded: false)
        expect(state.isCollapsed, "A fast fling that overshoots the bottom still counts actual page travel")
        for offset in [1600.0, 1300, 1000, 800, 737] {
            state.update(offset: offset, maximumOffset: 737, userScrolling: true, keepExpanded: false)
        }
        expect(state.isCollapsed, "Settling from that fling does not reopen the controls")

        print("Passed \(checks) scroll-chrome behavior checks.")
    }
}
