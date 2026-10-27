import Foundation

@main struct BrowserDataTests {
    static func main() throws {
        var checks = 0
        func check(_ value: Bool, _ name: String) { precondition(value, name); checks += 1 }
        check(WebAddress.resolve(" example.com:8443/a ")?.absoluteString == "https://example.com:8443/a", "host port")
        check(WebAddress.resolve("localhost:8080")?.host == "localhost", "localhost")
        check(WebAddress.resolve("[::1]:8080") != nil, "IPv6")
        check(WebAddress.resolve("https://user:password@example.com") == nil, "credentials")
        check(WebAddress.resolve("javascript:alert(1)") == nil, "executable URL")
        check(WebAddress.resolve("file:///tmp/test") == nil, "file URL")
        check(WebAddress.resolve("data:text/html,hi") == nil, "data URL")
        check(WebAddress.resolve("   ") == nil, "empty")
        check(WebAddress.resolve("weather: Chicago")?.host == "duckduckgo.com", "colon search")
        check(WebAddress.resolve("why a&b?")?.query?.contains("q=") == true, "search encoding")
        check(WebAddress.resolve("https://") == nil, "missing host")
        check(WebAddress.resolve("https://exa mple.com") == nil, "bad host")
        let id = UUID()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = BrowserArchiveStore(directory: folder)
        let record = TabRecord(id: id, address: "https://example.com/", fixture: false, scrollY: 500)
        var archive = BrowserArchive(session: TabArchive(tabs: [record], selectedID: id))
        archive.history = [LibraryEntry(address: "https://example.com/", title: "Example")]
        try store.write(archive)
        check(store.load()?.session.tabs.first?.scrollY == 500, "scroll restore")
        try store.write(archive)
        try Data("broken".utf8).write(to: folder.appendingPathComponent("session.json"))
        check(store.load()?.session.selectedID == id, "backup recovery")
        archive.history = []
        try store.replace(archive)
        try Data("broken".utf8).write(to: folder.appendingPathComponent("session.json"))
        check(store.load()?.history.isEmpty == true, "deletion cannot return from backup")
        var invalid = archive
        invalid.version = 99
        check(invalid.validated() == nil, "unknown version")
        invalid = archive
        invalid.history = [LibraryEntry(address: "javascript:alert(1)", title: "Unsafe")]
        check(invalid.validated()?.history.isEmpty == true, "history destination validation")
        invalid.session.tabs = (0..<250).map { _ in TabRecord(id: UUID(), address: nil, fixture: false) }
        check(invalid.validated()?.session.tabs.count == 200, "bounded tabs")
        invalid.session.tabs = [TabRecord(id: id, address: nil, fixture: false, scrollY: .infinity)]
        check(invalid.validated()?.session.tabs.first?.scrollY == nil, "invalid scroll")
        print("\(checks) browser data checks passed")
    }
}
