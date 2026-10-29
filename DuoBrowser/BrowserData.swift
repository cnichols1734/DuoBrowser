import Foundation

/// Only ordinary web destinations may enter app-owned persistent records.
enum WebAddress {
    static func valid(_ url: URL?) -> URL? {
        guard let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(c.scheme?.lowercased() ?? ""),
              let host = c.host, !host.isEmpty, !host.contains(where: \.isWhitespace),
              c.user == nil, c.password == nil, url.absoluteString.count <= 8192 else { return nil }
        return url
    }

    static func resolve(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= 8192 else { return nil }
        if text.contains("://") { return valid(URL(string: text)) }
        let first = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        let hostLike = !text.contains(where: \.isWhitespace) &&
            (first.contains(".") || first == "localhost" || first.hasPrefix("localhost:") || first.hasPrefix("["))
        if hostLike { return valid(URL(string: "https://" + text)) }
        // Explicit executable schemes are never interpreted as navigation.
        if ["javascript:", "data:", "file:", "about:", "blob:"].contains(where: { text.lowercased().hasPrefix($0) }) { return nil }
        var search = URLComponents(string: "https://duckduckgo.com/")!
        search.queryItems = [URLQueryItem(name: "q", value: text)]
        return search.url
    }
}

struct SitePreference: Codable, Equatable {
    var originalLayout = false
    var desktop = false
    var fullWidth: Bool? = nil
    var blockAds: Bool? = nil
}

struct LibraryEntry: Codable, Identifiable {
    var id = UUID()
    var address: String
    var title: String
    var date = Date()
}

struct BrowserArchive: Codable {
    var version = 1
    var session: TabArchive
    var history: [LibraryEntry] = []
    var bookmarks: [LibraryEntry] = []
    var sites: [String: SitePreference] = [:]
    var workspaces: [Workspace]? = nil

    func validated() -> BrowserArchive? {
        guard version == 1, let session = session.validated() else { return nil }
        var result = self
        result.session = session
        var workspaceIDs = Set<UUID>([Workspace.defaultID])
        let defaultName = workspaces?.first { $0.id == Workspace.defaultID }?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Personal"
        let standard = Workspace(id: Workspace.defaultID, name: defaultName.isEmpty ? "Personal" : String(defaultName.prefix(40)))
        result.workspaces = [standard] + (workspaces ?? []).filter {
            $0.id != Workspace.defaultID && workspaceIDs.insert($0.id).inserted && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.prefix(19).map { Workspace(id: $0.id, name: String($0.name.prefix(40))) }
        let allowed = Set((result.workspaces ?? []).map(\.id))
        result.session.tabs = result.session.tabs.map { tab in
            var tab = tab
            if !allowed.contains(tab.workspaceID ?? Workspace.defaultID) { tab.workspaceID = nil }
            return tab
        }
        func clean(_ entries: [LibraryEntry], limit: Int) -> [LibraryEntry] {
            var seen = Set<UUID>()
            return Array(entries.filter { WebAddress.valid(URL(string: $0.address)) != nil && seen.insert($0.id).inserted }
                .prefix(limit)).map { entry in
                    var e = entry; e.title = String(e.title.prefix(512)); return e
                }
        }
        result.history = clean(history, limit: 1000)
        result.bookmarks = clean(bookmarks, limit: 500)
        result.sites = Dictionary(uniqueKeysWithValues: sites.sorted { $0.key < $1.key }
            .filter { !$0.key.isEmpty && $0.key.count <= 253 }.prefix(500).map { ($0.key, $0.value) })
        return result
    }
}

/// Atomic local files, bounded decode and a last-known-good backup. Never receives private data.
final class BrowserArchiveStore {
    let directory: URL
    private let manager = FileManager.default
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrowserState", isDirectory: true)
    }
    private var primary: URL { directory.appendingPathComponent("session.json") }
    private var backup: URL { directory.appendingPathComponent("session.backup.json") }
    private func decode(_ url: URL) -> BrowserArchive? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              (values.fileSize ?? Int.max) <= 8_000_000,
              let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(BrowserArchive.self, from: data) else { return nil }
        return archive.validated()
    }
    func load() -> BrowserArchive? { decode(primary) ?? decode(backup) }
    func write(_ archive: BrowserArchive) throws {
        guard let valid = archive.validated() else { return }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        var folder = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        let data = try JSONEncoder().encode(valid)
        if let old = decode(primary) {
            try JSONEncoder().encode(old).write(to: backup, options: .atomic)
        }
        try data.write(to: primary, options: .atomic)
        #if os(iOS)
        for file in [primary, backup] where manager.fileExists(atPath: file.path) {
            try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
        }
        #endif
    }
    /// Deletion writes both generations so recovery cannot resurrect deleted history.
    func replace(_ archive: BrowserArchive) throws {
        try write(archive)
        try Data(contentsOf: primary).write(to: backup, options: .atomic)
        #if os(iOS)
        try manager.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: backup.path)
        #endif
    }
}

struct Workspace: Codable, Identifiable, Equatable {
    static let defaultID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let standard = Workspace(id: defaultID, name: "Personal")
    var id = UUID()
    var name: String
}

struct SearchResult: Identifiable {
    enum Kind: Int { case tab, bookmark, history }
    var id: String
    var title: String
    var address: String
    var kind: Kind
    var tabID: UUID? = nil
    var detail = ""
}

enum UnifiedSearch {
    static func results(_ query: String, candidates: [SearchResult]) -> [SearchResult] {
        let terms = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(whereSeparator: \.isWhitespace)
        var seen = Set<String>()
        return Array(candidates.enumerated().filter { _, item in
            let haystack = (item.title + " " + item.address + " " + item.detail).lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }.sorted { lhs, rhs in
            if lhs.element.kind != rhs.element.kind { return lhs.element.kind.rawValue < rhs.element.kind.rawValue }
            return lhs.offset < rhs.offset
        }.map(\.element).filter {
            // Keep distinct open tabs, but suppress library duplicates of already-open destinations.
            if $0.kind == .tab { seen.insert($0.address); return true }
            return seen.insert($0.address).inserted
        }.prefix(30))
    }
}
