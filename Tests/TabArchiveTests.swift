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
        let prefix = "https://example.com/#"
        var boundary = closed; boundary.address = prefix + String(repeating: "x", count: 8192 - prefix.count)
        expect(ClosedTabRecord.validated([boundary]).count == 1, "Reopenable 8192-character URL remains recoverable")
        boundary.address += "x"
        expect(ClosedTabRecord.validated([boundary]).isEmpty, "Overlong URL never offers unusable recovery")
        boundary.address = prefix + String(repeating: "é", count: 1500)
        expect(ClosedTabRecord.validated([boundary]).isEmpty, "URL limit uses the same encoded address as reopening")
        expect(closed.noticeRemaining(at: closed.closedAt, persistent: false) == 8, "Ordinary notice starts with eight seconds")
        expect(recovered.noticeRemaining(at: closed.closedAt.addingTimeInterval(4), persistent: false) == 4,
               "Recreated notice keeps only time remaining from original close")
        expect(closed.noticeRemaining(at: closed.closedAt.addingTimeInterval(60), persistent: false) == 0,
               "Returning from Private cannot revive an expired notice")
        expect(closed.noticeRemaining(at: closed.closedAt.addingTimeInterval(60), persistent: true) == nil,
               "VoiceOver and accessibility text retain explicit dismissal")
        expect(closed.noticeRemaining(at: closed.closedAt.addingTimeInterval(-60), persistent: false) == 8,
               "Clock rollback never schedules an unbounded notice")
        print("Passed \(checks) tab-archive checks.")
    }
}
