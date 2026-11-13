import Foundation

struct DownloadRecord: Codable, Identifiable {
    enum State: String, Codable { case interrupted, completed, failed, canceled, recovered }
    var id: UUID
    var name: String
    var date: Date
    var bytes: Int64
    var state: State

    static func safeFilename(_ input: String) -> String {
        let leaf = String(input.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last ?? "Download")
        let clean = leaf.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && ![0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069].contains($0.value)
        }.map(String.init).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        var result = ""
        for character in clean {
            guard result.utf8.count + String(character).utf8.count <= 180 else { break }
            result.append(character)
        }
        return result.isEmpty || result.hasPrefix(".") ? "Download" : result
    }
}

/// A bounded local manifest. URLs, request headers and opaque WebKit resume data never enter it.
struct DownloadStore {
    static let itemLimit = 200
    static let fileLimit: Int64 = 1_073_741_824
    static let storageLimit: Int64 = 2_147_483_648
    let directory: URL
    let persistent: Bool
    var removeFile: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    private var manifest: URL { directory.appendingPathComponent("downloads.json") }

    func destination(id: UUID, name: String) throws -> URL {
        let folder = directory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #if os(iOS)
        let protection: FileProtectionType = persistent ? .completeUntilFirstUserAuthentication : .complete
        try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: folder.path)
        #endif
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var root = directory; try root.setResourceValues(excluded)
        return folder.appendingPathComponent(DownloadRecord.safeFilename(name))
    }

    func file(for record: DownloadRecord) -> URL? {
        guard [.completed, .recovered].contains(record.state), record.bytes >= 0, record.bytes <= Self.fileLimit,
              record.name == DownloadRecord.safeFilename(record.name) else { return nil }
        let folder = directory.appendingPathComponent(record.id.uuidString, isDirectory: true)
        let url = folder.appendingPathComponent(record.name)
        guard let parent = try? folder.resourceValues(forKeys: [.isSymbolicLinkKey]), parent.isSymbolicLink != true,
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              Int64(values.fileSize ?? -1) == record.bytes else { return nil }
        return url
    }

    func load() -> [DownloadRecord] {
        guard persistent else { return [] }
        var saved: [DownloadRecord] = []
        if let size = try? manifest.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 256_000,
           let data = try? Data(contentsOf: manifest), let decoded = try? JSONDecoder().decode([DownloadRecord].self, from: data),
           decoded.count <= Self.itemLimit { saved = decoded }
        var files = inventory().records
        var seen = Set<UUID>(), result: [DownloadRecord] = []
        for record in saved {
            guard seen.insert(record.id).inserted, record.name == DownloadRecord.safeFilename(record.name),
                  record.bytes >= 0, record.date.timeIntervalSince1970.isFinite else { continue }
            let recovered = files.first { $0.id == record.id }
            files.removeAll { $0.id == record.id }
            if record.state == .completed, file(for: record) != nil { result.append(record) }
            else if let recovered { result.append(recovered) }
            else {
                var missing = record; missing.bytes = 0
                if missing.state == .completed || missing.state == .recovered { missing.state = .failed }
                result.append(missing)
            }
        }
        result.append(contentsOf: files.sorted { $0.date > $1.date })
        return Array(result.prefix(Self.itemLimit))
    }

    /// Counts actual UUID-owned folders, including files absent from a damaged manifest.
    /// Unknown or excessive structures fail closed for new transfers but remain removable in the list.
    func acceptsResponse(length: Int64, excluding id: UUID) -> Bool {
        let used = diskUsage(excluding: id)
        return used < Self.storageLimit && length <= Self.fileLimit && (length < 0 || length <= Self.storageLimit - used)
    }

    func diskUsage(excluding id: UUID? = nil) -> Int64 {
        let scan = inventory()
        if scan.blocked { return Self.storageLimit + 1 }
        return scan.records.filter { $0.id != id }.reduce(Int64(0)) { $0 + min(Self.storageLimit + 1, $1.bytes) }
    }

    private func inventory() -> (records: [DownloadRecord], blocked: Bool) {
        guard FileManager.default.fileExists(atPath: directory.path) else { return ([], false) }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var unreadable = false
        guard let folders = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys,
            options: [.skipsSubdirectoryDescendants], errorHandler: { _, _ in unreadable = true; return false }) else { return ([], true) }
        var records: [DownloadRecord] = [], count = 0
        for case let folder as URL in folders {
            count += 1
            if count > 1_000 { unreadable = true; break }
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            var record = DownloadRecord(id: id, name: "Recovered download", date: .distantPast, bytes: 0, state: .recovered)
            guard let parent = try? folder.resourceValues(forKeys: Set(keys)), parent.isDirectory == true, parent.isSymbolicLink != true else {
                record.bytes = Self.storageLimit + 1; records.append(record); continue
            }
            var badFolder = false, fileCount = 0
            if let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
                options: [.skipsSubdirectoryDescendants], errorHandler: { _, _ in badFolder = true; return false }) {
                for case let file as URL in files {
                    fileCount += 1
                    guard fileCount <= 8, let values = try? file.resourceValues(forKeys: Set(keys)),
                          values.isRegularFile == true, values.isSymbolicLink != true else { badFolder = true; break }
                    record.bytes += min(Self.storageLimit + 1, max(0, Int64(values.fileSize ?? 0)))
                    if fileCount == 1, DownloadRecord.safeFilename(file.lastPathComponent) == file.lastPathComponent {
                        record.name = file.lastPathComponent; record.date = values.contentModificationDate ?? .distantPast
                    } else { record.name = "Recovered download" }
                }
            } else { badFolder = true }
            if badFolder { record.bytes = Self.storageLimit + 1 }
            records.append(record)
        }
        return (records, unreadable)
    }

    func save(_ records: [DownloadRecord]) throws {
        guard persistent else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Array(records.prefix(Self.itemLimit)))
        #if os(iOS)
        try data.write(to: manifest, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: manifest, options: .atomic)
        #endif
        var excluded = URLResourceValues(); excluded.isExcludedFromBackup = true
        var root = directory; try root.setResourceValues(excluded)
    }

    func remove(_ id: UUID) throws {
        let folder = directory.appendingPathComponent(id.uuidString)
        // fileExists follows symlinks; a dangling UUID link still needs to be unlinked.
        let isLink = (try? FileManager.default.destinationOfSymbolicLink(atPath: folder.path)) != nil
        if isLink || FileManager.default.fileExists(atPath: folder.path) { try removeFile(folder) }
    }
    func erase() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try removeFile(directory) }
    }
}
