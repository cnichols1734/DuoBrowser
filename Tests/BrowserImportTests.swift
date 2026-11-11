import Foundation

@main struct BrowserImportTests {
    static var count = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        precondition(condition(), name); count += 1
    }
    static func rejects(_ name: String, _ block: () throws -> Void) {
        do { try block(); fatalError(name) } catch { count += 1 }
    }
    static func main() throws {
        var batch = BrowserImportBatch()
        // A non-English favorites title and child-first order must work without name heuristics.
        try batch.addBookmark(.init(identifier: "leaf", parent: "fav", title: "Favorite", address: "https://example.com/fav", isFolder: false))
        try batch.addBookmark(.init(identifier: "fav", parent: "root", title: "Preferiti", address: nil, isFolder: true))
        try batch.addBookmark(.init(identifier: "root", parent: nil, title: "Saved", address: nil, isFolder: true))
        try batch.addBookmark(.init(identifier: "other", parent: "root", title: "Bookmark", address: "https://example.com/bookmark", isFolder: false))
        try batch.addPage(address: "https://example.com/history", title: "Visit", date: Date(timeIntervalSince1970: 1234), isHistory: true)
        try batch.addPage(address: "https://example.com/read", title: "Read later", date: Date(timeIntervalSince1970: 0), isHistory: false)
        func plan(_ choices: ImportChoices = ImportChoices(), favorite: String? = "fav") throws -> BrowserImportPlan {
            try batch.plan(choices: choices, favoriteFolder: favorite, existingBookmarks: [], existingFolders: [], existingHistory: [], existingReadingList: [])
        }
        let all = try plan()
        check(all.totalAdded == 4, "all supported categories imported")
        check(all.folders.count == 2, "folder hierarchy retained")
        check(all.bookmarks.first?.isFavorite == true, "selected folder maps to favorites")
        check(all.bookmarks.last?.isFavorite == false, "ordinary bookmarks not favorites")
        check(all.history.first?.date == Date(timeIntervalSince1970: 1234), "original history timestamp retained")
        check(all.readingList.first?.address == "https://example.com/read", "reading list separate from bookmarks")
        let onlyFavorites = try plan(.init(bookmarks: false, favorites: true, history: false, readingList: false))
        check(onlyFavorites.totalAdded == 1 && onlyFavorites.bookmarks.count == 1, "favorites only selection")
        let noFavorites = try plan(.init(bookmarks: true, favorites: false, history: false, readingList: false))
        check(noFavorites.totalAdded == 1 && noFavorites.bookmarks.first?.title == "Bookmark", "bookmarks excludes deselected favorites")
        let none = try plan(.init(bookmarks: false, favorites: false, history: false, readingList: false))
        check(none.totalAdded == 0, "no selected data saved")
        let noMapping = try plan(favorite: nil)
        check(noMapping.favoritesAdded == 0 && noMapping.bookmarksAdded == 2, "no favorites inferred from localized names")
        let repeated = try batch.plan(choices: .init(), favoriteFolder: "fav", existingBookmarks: all.bookmarks,
            existingFolders: all.folders, existingHistory: all.history, existingReadingList: all.readingList)
        check(repeated.totalAdded == 0 && repeated.duplicates == 4, "repeated import deduplicates every category")
        check(repeated.folders.count == 2, "repeated import reuses folders")
        try batch.addPage(address: "javascript:alert(1)", title: "Bad", date: Date(), isHistory: true)
        try batch.addPage(address: "https://user:password@example.com", title: "Credentials", date: Date(), isHistory: false)
        try batch.addPage(address: "https://example.com/future", title: "Future", date: Date().addingTimeInterval(172_800), isHistory: true)
        try batch.addPage(address: "https://example.com/nan", title: "Invalid date", date: Date(timeIntervalSince1970: .nan), isHistory: true)
        try batch.skipUnsupported()
        check(batch.skipped == 5, "unsafe URLs, invalid dates and unsupported types excluded")
        let filtered = try plan()
        check(filtered.totalAdded == 4, "invalid items never enter persistence plan")
        rejects("duplicate source identifiers rejected") { try batch.addBookmark(.init(identifier: "root", parent: nil, title: "Duplicate", address: nil, isFolder: true)) }
        var cycle = BrowserImportBatch()
        try cycle.addBookmark(.init(identifier: "a", parent: "b", title: "A", address: nil, isFolder: true))
        try cycle.addBookmark(.init(identifier: "b", parent: "a", title: "B", address: nil, isFolder: true))
        rejects("cycles rejected") { _ = try cycle.folderOptions() }
        var orphan = BrowserImportBatch()
        try orphan.addBookmark(.init(identifier: "a", parent: "missing", title: "A", address: nil, isFolder: true))
        rejects("missing parents rejected") { _ = try orphan.folderOptions() }
        rejects("invalid favorites choice rejected") { _ = try plan(favorite: "leaf") }
        var large = BrowserImportBatch()
        rejects("bounded byte budget") { try large.account([String(repeating: "x", count: 12_000_001)]) }
        var many = BrowserImportBatch()
        rejects("bounded item budget") { for _ in 0...40_000 { try many.skipUnsupported() } }
        let tooMany = (0..<LibraryLimits.bookmarks).map { LibraryEntry(address: "https://example.com/\($0)", title: "Saved") }
        rejects("capacity refuses whole import instead of trimming existing pages") {
            _ = try batch.plan(choices: .init(), favoriteFolder: nil, existingBookmarks: tooMany, existingFolders: [], existingHistory: [], existingReadingList: [])
        }
        var empty = BrowserImportBatch()
        try empty.addBookmark(.init(identifier: "empty", parent: nil, title: "Empty folder", address: nil, isFolder: true))
        let emptyPlan = try empty.plan(choices: .init(), favoriteFolder: nil, existingBookmarks: [], existingFolders: [], existingHistory: [], existingReadingList: [])
        check(emptyPlan.folders.count == 1 && emptyPlan.bookmarks.isEmpty, "empty bookmark folders are preserved")
        let tab = TabRecord(id: UUID(), address: nil, fixture: false)
        let archive = BrowserArchive(session: TabArchive(tabs: [tab], selectedID: tab.id), history: all.history,
            bookmarks: all.bookmarks, bookmarkFolders: all.folders, readingList: all.readingList)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserArchiveStore(directory: directory)
        try store.write(archive)
        check(store.load()?.bookmarkFolders?.count == 2, "folders persist across relaunch")
        check(store.load()?.readingList?.count == 1, "reading list persists across relaunch")
        check(store.load()?.bookmarks.first?.isFavorite == true, "favorites persist across relaunch")
        var invalid = archive
        let cycleID = invalid.bookmarkFolders?[0].id
        invalid.bookmarkFolders?[0].parentID = cycleID
        check(invalid.validated() == nil, "archive rejects folder cycles")
        invalid = archive; invalid.bookmarks[0].folderID = UUID()
        check(invalid.validated() == nil, "archive rejects dangling bookmark folders")
        let legacy = BrowserArchive(session: archive.session, bookmarks: [LibraryEntry(address: "https://example.com", title: "Legacy")])
        let decoded = try JSONDecoder().decode(BrowserArchive.self, from: JSONEncoder().encode(legacy))
        check(decoded.validated()?.bookmarks.first?.isFavorite == nil, "legacy favorites behavior preserved")
        print("Browser import checks passed: \(count)")
    }
}
