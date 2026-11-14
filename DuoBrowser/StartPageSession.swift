import Foundation

extension BrowserSession {
    @discardableResult
    func saveStartPageFavorite(_ proposed: LibraryEntry, address: URL, name: String) -> Bool {
        guard !privateMode, name.count <= 512, WebAddress.valid(address) != nil else { return false }
        let updated = StartPagePolicy.favoriteEntry(proposed, address: address, name: name, bookmarks: bookmarks)
        do { try savePage(updated, reading: false); return true }
        catch { return false }
    }

    /// Favorites are deliberately edited in normal mode; private starts never expose this action.
    @discardableResult
    func reorderStartPageFavorites(_ ids: [UUID]) -> Bool {
        guard !privateMode, let ordered = StartPagePolicy.reorderedBookmarks(bookmarks, favoriteIDs: ids) else { return false }
        let previous = bookmarks
        bookmarks = ordered
        guard saveNow() else { bookmarks = previous; return false }
        return true
    }

    @discardableResult
    func removeStartPageFavorite(_ id: UUID) -> Bool {
        guard !privateMode, var entry = bookmarks.first(where: { $0.id == id && $0.isFavorite != false }) else { return false }
        entry.isFavorite = false
        do { try savePage(entry, reading: false); return true }
        catch { return false }
    }
}
