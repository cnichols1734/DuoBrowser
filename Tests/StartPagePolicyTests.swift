import Foundation

@main struct StartPagePolicyTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ label: String) { precondition(condition, label); checks += 1 }
        let workspace = UUID(), otherWorkspace = UUID(), selected = UUID()
        let first = UUID(), recent = UUID(), privateID = UUID(), other = UUID(), blank = UUID()
        let old = Date(timeIntervalSince1970: 10), now = Date(timeIntervalSince1970: 20)
        let tabs: [StartPagePolicy.Tab] = [
            .init(id: first, address: "https://example.com/first", workspaceID: workspace, lastUsed: old, isPrivate: false),
            .init(id: recent, address: "https://example.com/recent", workspaceID: workspace, lastUsed: now, isPrivate: false),
            .init(id: selected, address: "https://example.com/current", workspaceID: workspace, lastUsed: now, isPrivate: false),
            .init(id: privateID, address: "https://secret.example/private", workspaceID: workspace, lastUsed: now, isPrivate: true),
            .init(id: other, address: "https://example.com/other", workspaceID: otherWorkspace, lastUsed: now, isPrivate: false),
            .init(id: blank, address: "", workspaceID: workspace, lastUsed: now, isPrivate: false)
        ]
        let result = StartPagePolicy.openTabIDs(tabs, selectedID: selected, workspaceID: workspace, isPrivate: false)
        check(result == [recent, first], "continuation chooses recent normal tabs in current workspace and excludes current/blank tabs")
        check(StartPagePolicy.openTabIDs(tabs, selectedID: selected, workspaceID: workspace, isPrivate: true).isEmpty,
              "private start never projects normal or private continuation records")
        check(StartPagePolicy.openTabIDs(tabs, selectedID: selected, workspaceID: workspace, isPrivate: false, limit: -1).isEmpty,
              "negative limits are bounded")
        check(StartPagePolicy.openTabIDs(tabs, selectedID: selected, workspaceID: workspace, isPrivate: false, limit: 1) == [recent],
              "continuation limit preserves recent priority")
        var malicious = tabs
        malicious.append(.init(id: UUID(), address: "javascript:alert(1)", workspaceID: workspace, lastUsed: now, isPrivate: false))
        malicious.append(.init(id: UUID(), address: "https://name:password@example.com", workspaceID: workspace, lastUsed: now, isPrivate: false))
        check(StartPagePolicy.openTabIDs(malicious, selectedID: selected, workspaceID: workspace, isPrivate: false) == result,
              "continuation rejects executable and credential-bearing destinations")
        let favorite = LibraryEntry(address: "https://www.example.com/favorite", title: "Favorite")
        let sameFavoriteSite = LibraryEntry(address: "https://example.com/other", title: "Same site")
        let visit = LibraryEntry(address: "https://news.example/story?private-query=synthetic", title: "News")
        let duplicateVisit = LibraryEntry(address: "https://www.news.example/second", title: "Second news")
        let another = LibraryEntry(address: "https://other.example", title: "Other")
        let history = [sameFavoriteSite, visit, duplicateVisit, another]
        check(StartPagePolicy.recentSites(history, favorites: [favorite], isPrivate: false).map(\.id) == [visit.id, another.id],
              "recent sites deduplicate www variants and omit sites already in favorites")
        check(StartPagePolicy.recentSites(history, favorites: [], isPrivate: true).isEmpty,
              "private start never returns normal history")
        check(StartPagePolicy.recentSites(history, favorites: [favorite], isPrivate: false, limit: 1).map(\.id) == [visit.id],
              "recent site count is bounded")
        let largeHistory = (0..<20_000).map { LibraryEntry(address: "https://site\($0).example/page", title: "Site \($0)") }
        let visitCounter = StartPageHistoryVisitCounter()
        let countedHistory = StartPageCountedHistory(entries: largeHistory, counter: visitCounter)
        check(StartPagePolicy.recentSites(countedHistory, favorites: [], isPrivate: false).count == 4 && visitCounter.count == 4,
              "recent sites stop reading a twenty-thousand-entry history after four eligible unique sites")
        visitCounter.count = 0
        check(StartPagePolicy.recentSites(countedHistory, favorites: [], isPrivate: false, limit: 0).isEmpty && visitCounter.count == 0,
              "zero recent-site limit does not inspect history")
        check(StartPagePolicy.recentSites(countedHistory, favorites: [], isPrivate: true).isEmpty && visitCounter.count == 0,
              "private projection does not inspect normal history")
        check(StartPagePolicy.host(visit.address) == "news.example", "displayed recent site never exposes browsing path or query")
        let folder = UUID()
        let second = LibraryEntry(address: "https://second.example", title: "Second", folderID: folder, isFavorite: true)
        let bookmark = LibraryEntry(address: "https://bookmark.example", title: "Unchanged bookmark", folderID: folder, isFavorite: false)
        let entries = [favorite, bookmark, second]
        let reordered = StartPagePolicy.reorderedBookmarks(entries, favoriteIDs: [second.id, favorite.id])!
        check(reordered.map(\.id) == [second.id, bookmark.id, favorite.id], "favorite order changes only favorite slots")
        check(reordered[0].folderID == folder && reordered[0].date == second.date && reordered[1].isFavorite == false,
              "favorite reordering retains folder, dates and nonfavorite metadata")
        check(StartPagePolicy.reorderedBookmarks(entries, favoriteIDs: [favorite.id]) == nil,
              "stale partial reorder cannot drop a newly added favorite")
        check(StartPagePolicy.reorderedBookmarks(entries, favoriteIDs: [favorite.id, favorite.id]) == nil,
              "duplicate favorite IDs are rejected")
        check(StartPagePolicy.reorderedBookmarks(entries, favoriteIDs: [favorite.id, UUID()]) == nil,
              "unknown favorite IDs are rejected")
        let promoted = StartPagePolicy.favoriteEntry(LibraryEntry(address: "", title: ""),
            address: URL(string: bookmark.address)!, name: "My favorite", bookmarks: entries)
        check(promoted.id == bookmark.id && promoted.folderID == folder && promoted.date == bookmark.date && promoted.isFavorite == true,
              "adding a previously bookmarked address preserves its identity folder and date")
        check(promoted.title == "My favorite", "favorite promotion applies the explicitly chosen name")
        let sameName = StartPagePolicy.favoriteEntry(LibraryEntry(address: "", title: ""),
            address: URL(string: bookmark.address)!, name: "", bookmarks: entries)
        check(sameName.title == bookmark.title, "favorite promotion retains a saved name when no replacement is entered")
        check(StartPagePolicy.favoriteURL(" example.com/path ")?.absoluteString == "https://example.com/path", "favorite editor accepts a bare website")
        check(StartPagePolicy.favoriteURL("http://localhost:8765/fixture")?.scheme == "http", "favorite editor retains explicit HTTP for local sites")
        check(StartPagePolicy.favoriteURL("javascript://example.com") == nil, "favorite editor rejects executable schemes")
        check(StartPagePolicy.favoriteURL("https://name:password@example.com") == nil, "favorite editor rejects embedded credentials")
        check(StartPagePolicy.favoriteURL("file:///tmp/example") == nil, "favorite editor rejects local file URLs")
        check(StartPagePolicy.favoriteURL(" ") == nil, "favorite editor rejects empty input")
        print("\(checks) start-page policy checks passed")
    }
}

private final class StartPageHistoryVisitCounter { var count = 0 }
private struct StartPageCountedHistory: Sequence {
    let entries: [LibraryEntry]
    let counter: StartPageHistoryVisitCounter
    func makeIterator() -> AnyIterator<LibraryEntry> {
        var index = 0
        return AnyIterator {
            guard index < entries.count else { return nil }
            counter.count += 1
            defer { index += 1 }
            return entries[index]
        }
    }
}
