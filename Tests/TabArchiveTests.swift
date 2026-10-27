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
        print("Passed \(checks) tab-archive checks.")
    }
}
