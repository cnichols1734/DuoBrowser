import Foundation

@main
struct TabArchiveTests {
    static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
            checks += 1
        }
        let a = TabRecord(id: UUID(), address: "https://www.apple.com/", fixture: false)
        let b = TabRecord(id: UUID(), address: nil, fixture: true)
        let original = TabArchive(tabs: [a, b], selectedID: b.id)
        let decoded = try JSONDecoder().decode(TabArchive.self, from: JSONEncoder().encode(original)).validated()!
        expect(decoded.tabs.map(\.id) == [a.id, b.id], "Round trip preserves order and stable identity")
        expect(decoded.selectedID == b.id, "Round trip restores selection")
        expect(decoded.tabs[0].address == a.address && decoded.tabs[1].fixture, "Web and local fixture destinations survive")
        expect(TabArchive(tabs: [], selectedID: a.id).validated() == nil, "Empty archives need a fresh session")
        let duplicate = TabArchive(tabs: [a, a, b], selectedID: UUID()).validated()!
        expect(duplicate.tabs.count == 2, "Duplicate tab IDs cannot create ambiguous selections")
        expect(duplicate.selectedID == a.id, "Missing selection falls back to the first tab")
        for address in ["javascript:alert(1)", "file:///etc/passwd", "https://name:password@example.com", "https:///", "data:text/html,hello"] {
            let invalid = TabRecord(id: UUID(), address: address, fixture: false)
            let result = TabArchive(tabs: [invalid, b], selectedID: invalid.id).validated()!
            expect(result.tabs.count == 1 && result.selectedID == b.id, "Unsafe or malformed restoration destination is excluded")
        }
        let many = (0..<100).map { TabRecord(id: UUID(), address: "https://example.com/\($0)", fixture: false) }
        let manyRestored = TabArchive(tabs: many, selectedID: many[50].id).validated()!
        expect(manyRestored.tabs.count == 100 && manyRestored.selectedID == many[50].id, "Restoration does not silently truncate tabs")
        let closed = ClosedTabRecord(address: "https://example.com/article", title: "Saved title", scrollY: 432,
                                     workspaceID: UUID(), pinned: true)
        let recovered = try JSONDecoder().decode(ClosedTabRecord.self, from: JSONEncoder().encode(closed))
        expect(recovered.title == closed.title && recovered.workspaceID == closed.workspaceID && recovered.pinned,
               "Closed record preserves title, workspace and pin")
        expect(recovered.scrollY == 432, "Closed record preserves reading position")
        expect(ClosedTabRecord.validated([closed, closed]).count == 1, "Duplicate closed records are excluded")
        for address in ["javascript:alert(1)", "file:///secret", "https://user:password@example.com", "https://", String(repeating: "a", count: 20_000)] {
            var invalid = closed; invalid.address = address
            expect(ClosedTabRecord.validated([invalid]).isEmpty, "Unsafe closed destination is rejected")
        }
        var malformed = closed; malformed.scrollY = .infinity; malformed.title = String(repeating: "a", count: 800)
        let cleaned = ClosedTabRecord.validated([malformed])[0]
        expect(cleaned.scrollY == nil && cleaned.title.count == 512, "Closed metadata is bounded")
        let closedMany = (0..<30).map { _ in ClosedTabRecord(address: closed.address, title: "Page", scrollY: nil, workspaceID: UUID(), pinned: false) }
        expect(ClosedTabRecord.validated(closedMany).count == 20, "Recovery history is bounded to 20")
        print("Passed \(checks) tab-archive checks.")
    }
}
