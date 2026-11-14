import Foundation
import Combine

/// This projection observes data changes once; scrolling never re-scans normal history.
@MainActor
final class StartPageRecentSitesProjection: ObservableObject {
    @Published private(set) var sites: [LibraryEntry] = []
    private weak var session: BrowserSession?
    private var observation: AnyCancellable?

    func bind(to session: BrowserSession, enabled: Bool) {
        guard enabled, !session.privateMode else {
            observation = nil
            self.session = nil
            if !sites.isEmpty { sites = [] }
            return
        }
        guard self.session !== session || observation == nil else { return }
        observation = nil
        self.session = session
        observation = session.$history.combineLatest(session.$bookmarks).sink { [weak self, weak session] history, bookmarks in
            guard let self, let session, !session.privateMode else { self?.sites = []; return }
            sites = StartPagePolicy.recentSites(history, favorites: bookmarks.filter { $0.isFavorite != false }, isPrivate: false)
        }
    }
}

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
