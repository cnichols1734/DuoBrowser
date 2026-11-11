import Foundation

struct ImportChoices: Codable, Equatable {
    var bookmarks = true
    var favorites = true
    var history = true
    var readingList = true
    var hasSelection: Bool { bookmarks || favorites || history || readingList }
}

struct ImportBookmark {
    var identifier: String
    var parent: String?
    var title: String
    var address: String?
    var isFolder: Bool
}

enum BrowserImportError: LocalizedError {
    case tooLarge, invalidFolders, saveFailed
    var errorDescription: String? {
        switch self {
        case .tooLarge: return "This transfer exceeds DuoBrowser’s storage limit. Nothing was added. Try fewer categories."
        case .invalidFolders: return "The bookmark folders could not be read safely. Nothing was added. Try the transfer again."
        case .saveFailed: return "The transfer could not be saved on this device. Nothing was added. Free some space and try again."
        }
    }
}

/// Untrusted transfer data is bounded and staged in memory until the person confirms it.
struct BrowserImportBatch {
    private(set) var bookmarks: [String: ImportBookmark] = [:]
    private(set) var bookmarkOrder: [String] = []
    private(set) var history: [LibraryEntry] = []
    private(set) var readingList: [LibraryEntry] = []
    private(set) var skipped = 0
    private(set) var received = 0
    private var bytes = 0

    mutating func account(_ strings: [String] = []) throws {
        received += 1
        bytes += strings.reduce(0) { $0 + $1.utf8.count }
        guard received <= 40_000, bytes <= 12_000_000 else { throw BrowserImportError.tooLarge }
    }

    mutating func addBookmark(_ item: ImportBookmark) throws {
        try account([item.identifier, item.parent ?? "", item.title, item.address ?? ""])
        guard !item.identifier.isEmpty, item.identifier.utf8.count <= 512,
              (item.parent?.utf8.count ?? 0) <= 512, bookmarks[item.identifier] == nil else {
            throw BrowserImportError.invalidFolders
        }
        guard item.isFolder || WebAddress.valid(item.address.flatMap(URL.init(string:))) != nil else { skipped += 1; return }
        var bounded = item
        bounded.title = String(item.title.prefix(512))
        bookmarks[item.identifier] = bounded
        bookmarkOrder.append(item.identifier)
    }

    mutating func addPage(address: String, title: String, date: Date, isHistory: Bool) throws {
        try account([address, title])
        guard WebAddress.valid(URL(string: address)) != nil, date.timeIntervalSince1970.isFinite,
              date.timeIntervalSince1970 >= 0, date <= Date().addingTimeInterval(86_400) else { skipped += 1; return }
        let entry = LibraryEntry(address: address, title: String(title.prefix(512)), date: date)
        if isHistory { history.append(entry) } else { readingList.append(entry) }
    }

    mutating func skipUnsupported() throws { try account(); skipped += 1 }

    func ancestors(of identifier: String) throws -> [String] {
        var result: [String] = [], seen: Set<String> = [identifier]
        var parent = bookmarks[identifier]?.parent
        while let id = parent {
            guard seen.insert(id).inserted, result.count < 32,
                  let folder = bookmarks[id], folder.isFolder else { throw BrowserImportError.invalidFolders }
            result.append(id)
            parent = folder.parent
        }
        return result.reversed()
    }

    func folderOptions() throws -> [(id: String, title: String)] {
        try bookmarkOrder.compactMap { id in
            guard let item = bookmarks[id] else { return nil }
            let path = try ancestors(of: id)
            guard item.isFolder else { return nil }
            return (id, (path + [id]).compactMap { bookmarks[$0]?.title }.joined(separator: " / "))
        }
    }

    func plan(choices: ImportChoices, favoriteFolder: String?, existingBookmarks: [LibraryEntry],
              existingFolders: [BookmarkFolder], existingHistory: [LibraryEntry], existingReadingList: [LibraryEntry]) throws -> BrowserImportPlan {
        var plan = BrowserImportPlan(bookmarks: existingBookmarks, folders: existingFolders,
                                     history: existingHistory, readingList: existingReadingList, skipped: skipped)
        var folderMap: [String: UUID] = [:]
        // Validate all relationships before constructing a destination. Stream order is not tree order.
        let paths = try Dictionary(uniqueKeysWithValues: bookmarkOrder.map { ($0, try ancestors(of: $0)) })
        if let favoriteFolder, bookmarks[favoriteFolder]?.isFolder != true { throw BrowserImportError.invalidFolders }
        var bookmarkIndex = Dictionary(existingBookmarks.enumerated().map {
            (BookmarkKey(address: $0.element.address, folder: $0.element.folderID), $0.offset)
        }, uniquingKeysWith: { first, _ in first })
        var folderIndex = Dictionary(existingFolders.map {
            (FolderKey(title: $0.title, parent: $0.parentID), $0)
        }, uniquingKeysWith: { first, _ in first })
        for id in bookmarkOrder {
            guard let item = bookmarks[id] else { continue }
            let path = (paths[id] ?? []) + (item.isFolder ? [id] : [])
            let favorite = favoriteFolder.map { path.contains($0) } ?? false
            guard favorite ? choices.favorites : choices.bookmarks else { continue }
            var parentID: UUID?
            for sourceID in path {
                if let mapped = folderMap[sourceID] { parentID = mapped; continue }
                let title = bookmarks[sourceID]?.title ?? ""
                let key = FolderKey(title: title, parent: parentID)
                let folder = folderIndex[key] ?? BookmarkFolder(title: title, parentID: parentID)
                if folderIndex[key] == nil { plan.folders.append(folder); folderIndex[key] = folder }
                folderMap[sourceID] = folder.id
                parentID = folder.id
            }
            guard !item.isFolder, let address = item.address else { continue }
            let key = BookmarkKey(address: address, folder: parentID)
            if let index = bookmarkIndex[key] {
                if favorite && plan.bookmarks[index].isFavorite != true {
                    plan.bookmarks[index].isFavorite = true
                    plan.favoritesAdded += 1
                }
                plan.duplicates += 1
                continue
            }
            bookmarkIndex[key] = plan.bookmarks.count
            plan.bookmarks.append(LibraryEntry(address: address, title: item.title, folderID: parentID, isFavorite: favorite))
            if favorite { plan.favoritesAdded += 1 } else { plan.bookmarksAdded += 1 }
        }
        if choices.history {
            var keys = Set(plan.history.map { HistoryKey(address: $0.address, date: $0.date) })
            for item in history {
                if keys.insert(HistoryKey(address: item.address, date: item.date)).inserted {
                    plan.history.append(item); plan.historyAdded += 1
                } else { plan.duplicates += 1 }
            }
            plan.history.sort { $0.date > $1.date }
        }
        if choices.readingList {
            var keys = Set(plan.readingList.map(\.address))
            for item in readingList {
                if keys.insert(item.address).inserted { plan.readingList.append(item); plan.readingListAdded += 1 }
                else { plan.duplicates += 1 }
            }
        }
        guard plan.bookmarks.count <= LibraryLimits.bookmarks, plan.folders.count <= LibraryLimits.folders,
              plan.history.count <= LibraryLimits.history, plan.readingList.count <= LibraryLimits.readingList else {
            throw BrowserImportError.tooLarge
        }
        return plan
    }

    private struct BookmarkKey: Hashable { let address: String; let folder: UUID? }
    private struct FolderKey: Hashable { let title: String; let parent: UUID? }
    private struct HistoryKey: Hashable { let address: String; let date: Date }
}

struct BrowserImportPlan {
    var bookmarks: [LibraryEntry]
    var folders: [BookmarkFolder]
    var history: [LibraryEntry]
    var readingList: [LibraryEntry]
    var skipped = 0
    var duplicates = 0
    var bookmarksAdded = 0
    var favoritesAdded = 0
    var historyAdded = 0
    var readingListAdded = 0
    var totalAdded: Int { bookmarksAdded + favoritesAdded + historyAdded + readingListAdded }
    var summary: String {
        "Added: \(bookmarksAdded) bookmarks · \(favoritesAdded) favorites · \(historyAdded) history · \(readingListAdded) Reading List. Skipped: \(duplicates) duplicates · \(skipped) unsupported or invalid items."
    }
}
