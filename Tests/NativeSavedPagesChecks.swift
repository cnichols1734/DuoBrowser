#if DEBUG
import UIKit
import SwiftUI
import WebKit

extension NativeCheckRunner {
    func savedPagesPreview() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SavedPagesPreview-" + UUID().uuidString)
        let session = BrowserSession(storage: UserDefaults(suiteName: "DuoBrowser.SavedPagesPreview")!,
                                     archiveStore: BrowserArchiveStore(directory: directory), dataStore: .nonPersistent())
        let controller = UIHostingController(rootView: BrowserZoomPresenter(session: session).ignoresSafeArea(.container))
        host.addChild(controller)
        controller.view.frame = host.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        session.selected.navigate(to: "http://127.0.0.1:8765/upgrades")
    }

    func savedPagesChecks(_ session: BrowserSession) async throws {
        let source = session.selected
        try await load(source, "upgrades")
        _ = try await js(source, "document.querySelector('#kept').value='Private form draft'")
        let expected = source.restorationURL!
        let generation = source.documentGeneration
        let captured = try await source.captureOfflineArticle(expectedURL: expected, generation: generation)
        try check(captured.blocks.count == 3 && !captured.blocks.contains { $0.text.contains("FORM SECRET") }, "Offline capture excludes form values")
        try check(try await js(source, "document.querySelector('#kept').value") as? String == "Private form draft", "Offline capture preserves current form draft")
        var rejectedStale = false
        do { _ = try await source.captureOfflineArticle(expectedURL: expected, generation: UUID()) } catch { rejectedStale = true }
        try check(rejectedStale, "Stale offline capture rejected")
        let folder = BookmarkFolder(title: "Synthetic folder", parentID: nil)
        try session.saveFolder(folder)
        var bookmark = LibraryEntry(address: expected.absoluteString, title: "Edited title", folderID: folder.id, isFavorite: false)
        try session.savePage(bookmark, reading: false)
        try check(session.bookmarks.contains { $0.title == "Edited title" && $0.folderID == folder.id }, "Saved bookmark preserves chosen title and folder")
        bookmark.isFavorite = true; bookmark.folderID = nil
        try session.savePage(bookmark, reading: false)
        try check(session.bookmarks.filter { $0.address == expected.absoluteString }.count == 1 && session.favorites.contains { $0.address == expected.absoluteString }, "Editing bookmark moves to Favorites without duplicate")
        var entry = LibraryEntry(address: expected.absoluteString, title: "Offline fixture")
        try session.savePage(entry, reading: true, offline: captured)
        entry = session.readingList.first { $0.address == expected.absoluteString }!
        let offlineID = entry.offlineID!
        try check(try session.offlineStore.read(offlineID).blocks.count == 3, "Offline article survives durable round trip")
        entry.isRead = true
        try session.savePage(entry, reading: true)
        let archive = BrowserArchiveStore(directory: session.offlineStore.directory.deletingLastPathComponent()).load()
        try check(archive?.readingList?.first { $0.id == entry.id }?.isRead == true && archive?.readingList?.first { $0.id == entry.id }?.offlineID == offlineID,
                  "Reading status and offline reference survive archive reload")

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let jpeg = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).jpegData(withCompressionQuality: 0.7) { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        var document = captured
        document.title = "<script>untrusted title</script>"
        document.blocks.append(.init(kind: "image", text: "Synthetic photo", jpeg: jpeg))
        document.blocks.append(.init(kind: "image", text: "Unavailable image"))
        let article = ReaderArticle.offline(document)!
        try check(article.readerHTML.contains("img-src data:") && !article.readerHTML.contains("img-src https:") && article.readerHTML.contains("&lt;script&gt;"), "Offline template escapes text and blocks remote resources")
        let reader = ReaderRenderer(article: article, sourceBrowser: source)
        defer { reader.close() }
        mount(reader.browser); reader.load()
        try await wait { (try? await self.js(reader.browser, "document.readyState==='complete' && document.images.length===1 && document.images[0].naturalWidth===4")) as? Bool == true }
        try check(reader.browser.webView.configuration.websiteDataStore !== source.webView.configuration.websiteDataStore && !reader.browser.webView.configuration.websiteDataStore.isPersistent, "Offline Reader uses isolated ephemeral data store")
        try check(try await js(reader.browser, "document.body.textContent.includes('Image not saved for offline reading.')") as? Bool == true, "Unavailable offline images are explained")
        _ = try await js(reader.browser, "window.offlineProbe=new Image();offlineProbe.src='http://127.0.0.1:8765/reader-photo-one.png'")
        try await Task.sleep(for: .milliseconds(200))
        try check(try await js(reader.browser, "window.offlineProbe.naturalWidth===0") as? Bool == true, "Offline CSP prevents network image loading")
        try session.removeOfflineCopy(entry)
        try check(session.readingList.first { $0.id == entry.id }?.offlineID == nil && !FileManager.default.fileExists(atPath: session.offlineStore.url(offlineID).path), "Removing offline copy retains Reading List link and removes disk content")
        try session.savePage(entry, reading: true, offline: captured)
        let replaced = session.readingList.first { $0.id == entry.id }!
        session.deleteReadingList(ids: [entry.id])
        try check(!FileManager.default.fileExists(atPath: session.offlineStore.url(replaced.offlineID!).path), "Deleting saved article also deletes offline content")
        let privateTab = session.newTab(privateTab: true)
        try await load(privateTab, "upgrades?private-save=1")
        let count = session.readingList.count
        let privateArticle = try await privateTab.captureOfflineArticle(expectedURL: privateTab.restorationURL!, generation: privateTab.documentGeneration)
        try check(session.readingList.count == count, "Capturing a private article never saves it automatically")
        let privateEntry = LibraryEntry(address: privateArticle.address, title: "Explicit private save")
        try session.savePage(privateEntry, reading: true, offline: privateArticle)
        session.closePrivateTabs()
        try check(session.readingList.contains { $0.id == privateEntry.id && $0.offlineID != nil } && !session.history.contains { $0.address == privateEntry.address },
                  "Explicit private save survives tab closure without private history")
        session.deleteReadingList(ids: [privateEntry.id])
        session.select(source.id)
        session.deleteBookmarks(ids: Set(session.bookmarks.filter { $0.address == expected.absoluteString }.map(\.id)))
        session.deleteBookmarkFolder(folder.id)

        let failedDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let failed = BrowserSession(storage: UserDefaults(suiteName: "DuoBrowser.SavedPageFailure")!,
                                    archiveStore: BrowserArchiveStore(directory: failedDirectory), dataStore: .nonPersistent())
        defer { failed.tabs.forEach { $0.close() }; try? FileManager.default.removeItem(at: failedDirectory) }
        try FileManager.default.createDirectory(at: failedDirectory.appendingPathComponent("session.json"), withIntermediateDirectories: true)
        var rejectedSave = false
        do { try failed.savePage(LibraryEntry(address: captured.address, title: "Failed copy"), reading: true, offline: captured) } catch { rejectedSave = true }
        try check(rejectedSave && failed.readingList.isEmpty, "Failed durable save rolls back Library state")
        let orphaned = (try? FileManager.default.contentsOfDirectory(at: failed.offlineStore.directory, includingPropertiesForKeys: nil)) ?? []
        try check(orphaned.isEmpty, "Failed durable save removes its uncommitted offline file")

        let deletionDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let deletionArchive = BrowserArchiveStore(directory: deletionDirectory)
        let deletionSession = BrowserSession(storage: UserDefaults(suiteName: "DuoBrowser.LibraryDeletionFailure")!,
                                             archiveStore: deletionArchive, dataStore: .nonPersistent())
        defer { deletionSession.tabs.forEach { $0.close() }; try? FileManager.default.removeItem(at: deletionDirectory) }
        let parent = BookmarkFolder(title: "Retained parent", parentID: nil)
        let child = BookmarkFolder(title: "Retained child", parentID: parent.id)
        try deletionSession.saveFolder(parent); try deletionSession.saveFolder(child)
        let nested = LibraryEntry(address: "https://example.test/nested", title: "Nested bookmark", folderID: child.id)
        let unrelated = LibraryEntry(address: "https://example.test/unrelated", title: "Unrelated bookmark")
        try deletionSession.savePage(nested, reading: false); try deletionSession.savePage(unrelated, reading: false)
        // Keep the valid primary intact, but make the backup write fail before any primary commit.
        let blockedBackup = deletionDirectory.appendingPathComponent("session.backup.json")
        try FileManager.default.removeItem(at: blockedBackup)
        try FileManager.default.createDirectory(at: blockedBackup, withIntermediateDirectories: false)
        try check(!deletionSession.deleteBookmarks(ids: [nested.id]) && deletionSession.bookmarks.contains { $0.id == nested.id } &&
                  deletionArchive.load()?.bookmarks.contains { $0.id == nested.id } == true && deletionSession.selected.errorMessage != nil,
                  "Failed bookmark deletion reports error and retains memory and durable records")
        try check(!deletionSession.deleteBookmarkFolder(parent.id) && Set(deletionSession.bookmarkFolders.map(\.id)) == Set([parent.id, child.id]) &&
                  deletionSession.bookmarks.contains { $0.id == nested.id } && deletionArchive.load()?.bookmarkFolders?.count == 2,
                  "Failed folder deletion restores descendants and their bookmarks")
        try FileManager.default.removeItem(at: blockedBackup)
        try check(deletionSession.deleteBookmarkFolder(parent.id) && deletionSession.bookmarkFolders.isEmpty &&
                  deletionSession.bookmarks.map(\.id) == [unrelated.id] && deletionArchive.load()?.bookmarks.map(\.id) == [unrelated.id],
                  "Folder deletion retries successfully without removing unrelated bookmarks")

        let removalDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let removalStore = OfflineArticleStore(directory: removalDirectory.appendingPathComponent("OfflineArticles"),
                                              deleteFile: { _ in throw CocoaError(.fileWriteNoPermission) })
        let removalArchive = BrowserArchiveStore(directory: removalDirectory)
        let removalSession = BrowserSession(storage: UserDefaults(suiteName: "DuoBrowser.OfflineRemovalFailure")!, archiveStore: removalArchive,
                                            dataStore: .nonPersistent(), offlineStore: removalStore)
        defer { removalSession.tabs.forEach { $0.close() }; try? FileManager.default.removeItem(at: removalDirectory) }
        try removalSession.savePage(LibraryEntry(address: captured.address, title: "Retained offline copy"), reading: true, offline: captured)
        let retained = removalSession.readingList[0]
        var removalRejected = false
        do { try removalSession.removeOfflineCopy(retained) } catch { removalRejected = true }
        try check(removalRejected && removalSession.readingList[0].offlineID == retained.offlineID,
                  "Disk removal failure is surfaced with a retryable offline reference")
        try check(removalArchive.load()?.readingList?.first?.offlineID == retained.offlineID && FileManager.default.fileExists(atPath: removalStore.url(retained.offlineID!).path),
                  "Disk removal failure keeps durable reference and offline content")
        try check(!removalSession.deleteReadingList(ids: [retained.id]) && removalSession.readingList.contains { $0.id == retained.id },
                  "Reading List deletion reports disk failure and preserves retryable item")
    }
}
#endif
