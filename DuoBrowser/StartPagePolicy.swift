import Foundation

/// Start-page projections contain only normal destinations. They never create or load a web view.
enum StartPagePolicy {
    struct Tab: Identifiable {
        var id: UUID
        var address: String
        var workspaceID: UUID
        var lastUsed: Date
        var isPrivate: Bool
    }

    static func openTabIDs(_ tabs: [Tab], selectedID: UUID, workspaceID: UUID, isPrivate: Bool, limit: Int = 3) -> [UUID] {
        guard !isPrivate else { return [] }
        return Array(tabs.enumerated().filter {
            !$0.element.isPrivate && $0.element.id != selectedID && $0.element.workspaceID == workspaceID
                && WebAddress.valid(URL(string: $0.element.address)) != nil
        }.sorted {
            if $0.element.lastUsed != $1.element.lastUsed { return $0.element.lastUsed > $1.element.lastUsed }
            return $0.offset < $1.offset
        }.prefix(max(0, min(6, limit))).map { $0.element.id })
    }

    static func recentSites(_ history: [LibraryEntry], favorites: [LibraryEntry], isPrivate: Bool, limit: Int = 4) -> [LibraryEntry] {
        guard !isPrivate else { return [] }
        var hosts = Set(favorites.compactMap { host($0.address) })
        return Array(history.filter {
            guard WebAddress.valid(URL(string: $0.address)) != nil, let name = host($0.address) else { return false }
            return hosts.insert(name).inserted
        }.prefix(max(0, min(8, limit))))
    }

    /// Reorder favorite slots while preserving every bookmark, folder, and other metadata.
    /// A stale or partial drag must not silently discard a newly saved favorite.
    static func reorderedBookmarks(_ bookmarks: [LibraryEntry], favoriteIDs: [UUID]) -> [LibraryEntry]? {
        let favorites = bookmarks.filter { $0.isFavorite != false }
        guard favoriteIDs.count == favorites.count, Set(favoriteIDs).count == favoriteIDs.count,
              Set(favoriteIDs) == Set(favorites.map(\.id)) else { return nil }
        let lookup = Dictionary(favorites.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var next = favoriteIDs.makeIterator()
        return bookmarks.map { entry in
            guard entry.isFavorite != false, let id = next.next(), let favorite = lookup[id] else { return entry }
            return favorite
        }
    }

    static func host(_ address: String) -> String? {
        guard let host = URL(string: address)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func favoriteURL(_ input: String) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return WebAddress.valid(URL(string: value.contains("://") ? value : "https://" + value))
    }

    /// Promoting a saved bookmark to Favorites must not reset its folder, date, or stable identity.
    static func favoriteEntry(_ proposed: LibraryEntry, address: URL, name: String, bookmarks: [LibraryEntry]) -> LibraryEntry {
        var updated = bookmarks.first { $0.id == proposed.id }
            ?? bookmarks.first { $0.address == address.absoluteString } ?? proposed
        updated.address = address.absoluteString
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !title.isEmpty { updated.title = title }
        else if updated.title.isEmpty { updated.title = host(updated.address) ?? updated.address }
        updated.isFavorite = true
        return updated
    }
}
