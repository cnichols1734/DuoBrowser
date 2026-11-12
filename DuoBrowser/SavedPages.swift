import Foundation

/// Data-only article snapshots. Rendering always escapes text and rejects remote image references.
struct OfflineArticle: Codable {
    struct Block: Codable {
        var kind: String
        var text: String
        var jpeg: Data?
    }
    var title: String
    var address: String
    var blocks: [Block]
    var savedAt = Date()

    func validated() -> OfflineArticle? {
        guard title.count <= 512, WebAddress.valid(URL(string: address)) != nil,
              (1...300).contains(blocks.count) else { return nil }
        var characters = 0
        var bytes = 0
        for block in blocks {
            guard ["heading", "paragraph", "caption", "image"].contains(block.kind), block.text.count <= 8000 else { return nil }
            characters += block.text.count
            if let jpeg = block.jpeg {
                guard block.kind == "image", jpeg.count <= 1_048_576,
                      jpeg.starts(with: [0xff, 0xd8, 0xff]) else { return nil }
                bytes += jpeg.count
            }
        }
        return characters <= 150_000 && bytes <= 4_194_304 ? self : nil
    }
}

struct OfflineArticleStore {
    let directory: URL
    private let deleteFile: (URL) throws -> Void
    static let maximumArticleBytes = 6_000_000
    static let maximumStoreBytes = 50_000_000
    init(directory: URL? = nil, deleteFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.deleteFile = deleteFile
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OfflineArticles", isDirectory: true)
    }
    func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString).appendingPathExtension("json") }
    func read(_ id: UUID) throws -> OfflineArticle {
        let file = url(id)
        guard let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.maximumArticleBytes else { throw SavedPageError.invalidArticle }
        let article = try JSONDecoder().decode(OfflineArticle.self, from: Data(contentsOf: file))
        guard let valid = article.validated() else { throw SavedPageError.invalidArticle }
        return valid
    }
    func write(_ article: OfflineArticle, id: UUID) throws {
        guard let valid = article.validated() else { throw SavedPageError.invalidArticle }
        let data = try JSONEncoder().encode(valid)
        guard data.count <= Self.maximumArticleBytes else { throw SavedPageError.articleTooLarge }
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let used = try files.filter { $0 != url(id) }.reduce(0) { try $0 + ($1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) }
        guard used + data.count <= Self.maximumStoreBytes else { throw SavedPageError.storageFull }
        #if os(iOS)
        try data.write(to: url(id), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url(id), options: .atomic)
        #endif
    }
    func remove(_ id: UUID) throws {
        guard FileManager.default.fileExists(atPath: url(id).path) else { return }
        try deleteFile(url(id))
    }
    /// UUID files are the durable cleanup queue. Failed removals remain discoverable on the next pass.
    @discardableResult
    func reconcile(retaining references: Set<UUID>) -> Bool {
        guard FileManager.default.fileExists(atPath: directory.path) else { return true }
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return false }
        var complete = true
        for file in files where file.pathExtension == "json" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent), !references.contains(id) else { continue }
            do { try remove(id) } catch { complete = false }
        }
        return complete
    }

}

enum SavedPageError: LocalizedError {
    case invalidArticle, articleTooLarge, storageFull, invalidFolder, saveFailed, stalePage, removalFailed
    var errorDescription: String? {
        switch self {
        case .invalidArticle: return "This page couldn’t be saved as an offline article. You can still save its link."
        case .articleTooLarge: return "This article is too large to save offline. You can still save its link."
        case .storageFull: return "Offline storage is full. Remove an offline copy in Reading List to make room."
        case .invalidFolder: return "Choose a different folder. A folder can’t contain itself or one of its parents."
        case .saveFailed: return "Your saved pages couldn’t be written. Please try again."
        case .removalFailed: return "The offline copy couldn’t be removed. It is still available in Reading List. Please try again."
        case .stalePage: return "The page changed while saving. Open Save Page again to save the current page."
        }
    }
}

enum SavedPagesPolicy {
    /// Build once for a picker: O(folders + descendants), then at most 31 parent lookups per destination.
    struct Destinations {
        let lookup: [UUID: BookmarkFolder]
        private var descendants = Set<UUID>()
        private var height = 0
        private var valid = true
        init(movingID: UUID?, folders: [BookmarkFolder]) {
            lookup = Dictionary(folders.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            guard let movingID else { return }
            let children = Dictionary(grouping: folders.compactMap { folder in folder.parentID.map { ($0, folder.id) } }, by: { $0.0 })
            var frontier = [movingID]
            while !frontier.isEmpty {
                guard height <= 31 else { valid = false; return }
                var next: [UUID] = []
                for node in frontier {
                    guard descendants.insert(node).inserted else { valid = false; return }
                    next += (children[node] ?? []).map { $0.1 }
                }
                frontier = next
                if !frontier.isEmpty { height += 1 }
            }
        }
        func canMove(to parent: UUID?) -> Bool {
            guard valid else { return false }
            var seen = Set<UUID>()
            var current = parent
            while let next = current {
                guard !descendants.contains(next), seen.insert(next).inserted, seen.count < 32,
                      let folder = lookup[next] else { return false }
                current = folder.parentID
            }
            return height + seen.count <= 31
        }
        func path(_ folder: BookmarkFolder) -> String {
            var names = [folder.title]
            var parent = folder.parentID
            for _ in 0..<32 {
                guard let id = parent, let next = lookup[id] else { break }
                names.insert(next.title, at: 0); parent = next.parentID
            }
            return names.joined(separator: " / ")
        }
    }
    static func canMove(_ id: UUID?, to parent: UUID?, folders: [BookmarkFolder]) -> Bool {
        Destinations(movingID: id, folders: folders).canMove(to: parent)
    }
}
