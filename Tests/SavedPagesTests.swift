import Foundation

@main struct SavedPagesTests {
    static func main() throws {
        var checks = 0
        func check(_ result: Bool, _ message: String) { precondition(result, message); checks += 1 }
        let root = BookmarkFolder(title: "Root", parentID: nil)
        let child = BookmarkFolder(title: "Child", parentID: root.id)
        let sibling = BookmarkFolder(title: "Sibling", parentID: nil)
        let folders = [root, child, sibling]
        check(SavedPagesPolicy.canMove(child.id, to: sibling.id, folders: folders), "valid folder move")
        check(!SavedPagesPolicy.canMove(root.id, to: child.id, folders: folders), "descendant cycle rejected")
        check(!SavedPagesPolicy.canMove(root.id, to: root.id, folders: folders), "self rejected")
        check(!SavedPagesPolicy.canMove(nil, to: UUID(), folders: folders), "missing parent rejected")
        var deep: [BookmarkFolder] = []
        for index in 0..<32 { deep.append(BookmarkFolder(title: "\(index)", parentID: deep.last?.id)) }
        check(!SavedPagesPolicy.canMove(root.id, to: deep.last!.id, folders: folders + deep), "deep reparent rejected")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = OfflineArticleStore(directory: directory)
        let id = UUID()
        var article = OfflineArticle(title: "<script>untrusted</script>", address: "https://example.test/article", blocks: [.init(kind: "paragraph", text: "Saved text.")])
        try store.write(article, id: id)
        check(try store.read(id).blocks.first?.text == "Saved text.", "offline text survives disk reload")
        article.blocks[0].kind = "script"
        check(article.validated() == nil, "unrecognized block rejected")
        article.blocks[0].kind = "paragraph"
        article.blocks[0].jpeg = Data([0xff, 0xd8, 0xff])
        check(article.validated() == nil, "images forbidden in text blocks")
        article.blocks[0].kind = "image"
        article.blocks[0].jpeg = Data("<svg><script/></svg>".utf8)
        check(article.validated() == nil, "nonraster image rejected")
        article.blocks[0].jpeg = Data([0xff, 0xd8, 0xff]) + Data(repeating: 0, count: 1_048_576)
        check(article.validated() == nil, "per-image bytes bounded")
        article.blocks = [.init(kind: "paragraph", text: "Saved")]
        article.address = "file:///etc/passwd"
        check(article.validated() == nil, "nonweb source rejected")
        article.address = "https://user:secret@example.test"
        check(article.validated() == nil, "credential-bearing source rejected")
        try Data(repeating: 0, count: OfflineArticleStore.maximumArticleBytes + 1).write(to: store.url(id))
        do { _ = try store.read(id); preconditionFailure("oversized file accepted") } catch { checks += 1 }
        try store.remove(id)
        check(!FileManager.default.fileExists(atPath: store.url(id).path), "offline deletion removes file")
        let entry = LibraryEntry(address: "https://example.test", title: "Old bookmark")
        let oldJSON = try JSONEncoder().encode(entry)
        check(try JSONDecoder().decode(LibraryEntry.self, from: oldJSON).offlineID == nil, "optional schema fields remain compatible")
        let protectedID = UUID()
        let protectedArticle = OfflineArticle(title: "Keep me", address: "https://example.test/protected", blocks: [.init(kind: "paragraph", text: "Saved")])
        try store.write(protectedArticle, id: protectedID)
        let failing = OfflineArticleStore(directory: directory, deleteFile: { _ in throw CocoaError(.fileWriteNoPermission) })
        do { try failing.remove(protectedID); preconditionFailure("removal failure hidden") } catch { checks += 1 }
        check(FileManager.default.fileExists(atPath: store.url(protectedID).path), "failed deletion retains offline copy")
        let orphan = UUID()
        try store.write(protectedArticle, id: orphan)
        check(!failing.reconcile(retaining: [protectedID]) && FileManager.default.fileExists(atPath: store.url(orphan).path),
              "failed cleanup keeps durable orphan for a later retry")
        check(store.reconcile(retaining: [protectedID]) && !FileManager.default.fileExists(atPath: store.url(orphan).path) &&
              FileManager.default.fileExists(atPath: store.url(protectedID).path), "cleanup retry removes only unreferenced copies")
        let broadRoot = BookmarkFolder(title: "Broad root", parentID: nil)
        let descendants = (0..<999).map { BookmarkFolder(title: "Child \($0)", parentID: broadRoot.id) }
        let destinations = (0..<1000).map { BookmarkFolder(title: "Destination \($0)", parentID: nil) }
        let choices = SavedPagesPolicy.Destinations(movingID: broadRoot.id, folders: [broadRoot] + descendants + destinations)
        check(destinations.allSatisfy { choices.canMove(to: $0.id) } && descendants.allSatisfy { !choices.canMove(to: $0.id) },
              "2000-folder picker computes every destination without rescanning the subtree")
        check(choices.path(descendants[0]) == "Broad root / Child 0", "folder paths use shared parent index")
        let full = directory.appendingPathComponent("capacity.json")
        try Data(repeating: 0, count: OfflineArticleStore.maximumStoreBytes).write(to: full)
        let valid = OfflineArticle(title: "Article", address: "https://example.test", blocks: [.init(kind: "paragraph", text: "Saved")])
        do { try store.write(valid, id: UUID()); preconditionFailure("storage budget ignored") } catch { checks += 1 }
        print("Saved pages: \(checks) checks passed")
    }
}
