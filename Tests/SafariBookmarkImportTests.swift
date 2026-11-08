import Foundation

@main struct SafariBookmarkImportTests {
    static func main() throws {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ message: String) {
            precondition(value(), message); count += 1
        }
        func rejects(_ data: Data, _ message: String) {
            do { _ = try SafariBookmarkImport.parse(data); preconditionFailure(message) } catch { count += 1 }
        }
        let html = try Data(contentsOf: URL(fileURLWithPath: "Tests/Fixtures/SafariImport/Bookmarks.html"))
        let result = try SafariBookmarkImport.parse(html)
        check(result.items.count == 13, "Exclude Reading List")
        check(result.preferredFolder == "Favorites", "Select Favorites by metadata")
        check(result.entries(in: "Favorites").count == 12, "Import chosen folder only")
        check(result.items.last?.title == "News & Notes", "Decode numeric and named entities")
        check(result.items.last?.address == "https://example.org/?a=1&b=2", "Decode URL entities")
        check(result.items.first?.title == "YouTube", "Preserve exported order")
        let bad = "<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><A HREF='javascript:alert(1)'>Bad</A><A HREF='file:///tmp/x'>Local</A><A HREF='https://user:secret@example.org'>Credentials</A></DL>"
        rejects(Data(bad.utf8), "Reject unsafe URL schemes and credentials")
        rejects(Data("<html><a href='https://example.org'>Unrelated HTML</a></html>".utf8), "Require bookmarks format")
        rejects(Data(repeating: 0, count: SafariBookmarkImport.maximumFileSize + 1), "Bound file bytes")
        rejects(Data([0x50, 0x4b, 3, 4]), "Reject truncated ZIP")
        for name in ["stored", "deflated", "localized"] {
            let zip = try Data(contentsOf: URL(fileURLWithPath: "work/checks/" + name + ".zip"))
            check(tryParse(zip)?.items.count == 13, "Import " + name + " ZIP without other export records")
        }
        var corrupt = try Data(contentsOf: URL(fileURLWithPath: "work/checks/stored.zip"))
        corrupt[60] ^= 0xff
        rejects(corrupt, "Verify member CRC")
        let nested = "<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><H3 PERSONAL_TOOLBAR_FOLDER='true'>Favoriten</H3><DL><H3>Work</H3><DL><A HREF='https://example.org'>Work</A></DL></DL></DL>"
        let localized = try SafariBookmarkImport.parse(Data(nested.utf8))
        check(localized.preferredFolder == "Favoriten", "Localized Favorites attribute")
        check(localized.entries(in: "Favoriten").count == 1, "Include nested folder descendants")
        let duplicated = "<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><A HREF='https://example.org'>One</A><A HREF='https://example.org'>Two</A></DL>"
        check(tryParse(Data(duplicated.utf8))?.items.count == 1, "Deduplicate imported links")
        let hidden = "<!DOCTYPE NETSCAPE-Bookmark-file-1><DL><SCRIPT><A HREF='https://evil.example'>Evil</A></SCRIPT><A HREF='https://example.org'>Safe</A></DL>"
        check(tryParse(Data(hidden.utf8))?.items.count == 1, "Never interpret script content")
        print("Safari bookmark import: \(count) checks passed")
    }
    static func tryParse(_ data: Data) -> SafariBookmarkImport.Preview? { try? SafariBookmarkImport.parse(data) }
}
