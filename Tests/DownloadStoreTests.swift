import Foundation

@main
struct DownloadStoreTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool, _ label: String) {
            guard condition else { fatalError(label) }; checks += 1
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DuoDownloadTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DownloadStore(directory: root, persistent: true)
        check(DownloadRecord.safeFilename("../../secret.txt") == "secret.txt", "path traversal")
        check(DownloadRecord.safeFilename("C:\\folder\\report.pdf") == "report.pdf", "Windows separator")
        check(DownloadRecord.safeFilename(".hidden") == "Download", "hidden file")
        check(DownloadRecord.safeFilename("  \n ") == "Download", "blank filename")
        check(DownloadRecord.safeFilename("report\u{202E}txt.exe") == "reporttxt.exe", "bidi spoof removed")
        check(DownloadRecord.safeFilename(String(repeating: "🌍", count: 500)).utf8.count <= 180, "UTF8 filename bounded")
        let id = UUID(), content = Data("Synthetic download".utf8)
        let file = try store.destination(id: id, name: "example.txt")
        try content.write(to: file)
        let completed = DownloadRecord(id: id, name: "example.txt", date: Date(), bytes: Int64(content.count), state: .completed)
        try store.save([completed])
        check(store.load().count == 1, "completed download restores")
        check(store.file(for: completed) == file, "retained file is discoverable")
        check(try Data(contentsOf: file) == content, "metadata save preserves download")
        let encoded = try String(contentsOf: root.appendingPathComponent("downloads.json"), encoding: .utf8)
        check(!encoded.contains("url") && !encoded.contains("request") && !encoded.contains("resume") && !encoded.contains("cookie"), "manifest excludes network credentials and origins")
        var corrupt = completed; corrupt.name = "../example.txt"
        try store.save([corrupt]); check(store.load().first?.state == .recovered && store.load().first?.name == "example.txt", "unsafe metadata replaced by safe recovered file")
        corrupt = completed; corrupt.bytes += 1
        try store.save([corrupt]); check(store.load().first?.state == .recovered, "changed file is recovered without claiming completion")
        try store.save([completed, completed]); check(store.load().count == 1, "duplicate records deduplicated")
        let outside = root.appendingPathComponent("outside.txt")
        try content.write(to: outside)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
        check(store.file(for: completed) == nil, "symlink file rejected")
        try store.remove(id)
        check(FileManager.default.fileExists(atPath: outside.path), "removal does not follow symlink")
        let interrupted = DownloadRecord(id: UUID(), name: "Pending.pdf", date: Date(), bytes: 0, state: .interrupted)
        try store.save([interrupted]); check(store.load().first?.state == .interrupted, "interrupted status restores honestly")
        try store.save(Array(repeating: interrupted, count: 1_000))
        let raw = try JSONDecoder().decode([DownloadRecord].self, from: Data(contentsOf: root.appendingPathComponent("downloads.json")))
        check(raw.count == DownloadStore.itemLimit, "manifest record limit")
        try Data(repeating: 32, count: 300_000).write(to: root.appendingPathComponent("downloads.json"))
        check(store.load().isEmpty, "oversized manifest rejected")
        let privateStore = DownloadStore(directory: root.appendingPathComponent("private"), persistent: false)
        try privateStore.save([completed])
        check(!FileManager.default.fileExists(atPath: privateStore.directory.path), "private manifest never written")
        check(privateStore.load().isEmpty, "private store never restores")
        let privateFile = try privateStore.destination(id: UUID(), name: "Private.txt")
        try content.write(to: privateFile)
        try privateStore.erase()
        check(!FileManager.default.fileExists(atPath: privateFile.path), "private cleanup deletes staged files")
        let failedDelete = DownloadStore(directory: root, persistent: true, removeFile: { _ in throw CocoaError(.fileWriteNoPermission) })
        let retainedID = UUID()
        let retained = try failedDelete.destination(id: retainedID, name: "Retained.txt")
        try content.write(to: retained)
        do { try failedDelete.remove(retainedID); check(false, "deletion failure must propagate") }
        catch { check(FileManager.default.fileExists(atPath: retained.path), "failed deletion remains available for retry") }
        try Data("broken manifest".utf8).write(to: root.appendingPathComponent("downloads.json"))
        check(store.load().contains(where: { $0.id == retainedID && $0.state == .recovered }), "orphan file remains visible after manifest corruption")
        check(store.diskUsage() == Int64(content.count), "storage accounting includes orphan files")
        let oversizedID = UUID()
        let sparse = try store.destination(id: oversizedID, name: "Sparse.bin")
        FileManager.default.createFile(atPath: sparse.path, contents: nil)
        let handle = try FileHandle(forWritingTo: sparse)
        try handle.truncate(atOffset: UInt64(DownloadStore.storageLimit + 1)); try handle.close()
        check(store.diskUsage() > DownloadStore.storageLimit, "actual oversized orphan blocks new downloads without trusting manifest")
        check(store.diskUsage(excluding: oversizedID) == Int64(content.count), "destination accounting excludes only its own partial file")
        check(!store.acceptsResponse(length: -1, excluding: UUID()), "unknown-length retry cannot bypass full or blocked storage")
        try store.remove(oversizedID)
        check(store.acceptsResponse(length: -1, excluding: UUID()), "unknown-length download can proceed when storage is available")
        print("\(checks) download storage checks passed")
    }
}
