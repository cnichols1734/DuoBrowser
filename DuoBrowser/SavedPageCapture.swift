import UIKit
import WebKit
import ImageIO

extension ReaderArticle {
    static func offline(_ document: OfflineArticle) -> ReaderArticle? {
        guard let document = document.validated(), let source = URL(string: document.address) else { return nil }
        var images: [Int: Data] = [:]
        let blocks = document.blocks.enumerated().map { index, block in
            if let jpeg = block.jpeg { images[index] = jpeg }
            return Block(kind: block.kind, text: block.text)
        }
        return ReaderArticle(title: document.title, source: source, blocks: blocks, offlineImages: images)
    }
}

/// Explicit offline saves use anonymous, bounded image requests. No redirects, shared cookies, or credentials.
final class OfflineImageClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }

    func image(_ url: URL, source: URL) async throws -> Data? {
        guard url.scheme == "https", source.scheme == "https", url.host == source.host,
              (url.port ?? 443) == (source.port ?? 443), WebAddress.valid(url) != nil else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 4
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              ["image/jpeg", "image/png", "image/webp", "image/gif"].contains(http.mimeType ?? ""),
              response.expectedContentLength <= 1_048_576 else { return nil }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 1_048_576 else { return nil }
            data.append(byte)
        }
        guard let image = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(image, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 20_000, height <= 20_000, width * height <= 40_000_000,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(image, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.75), jpeg.count <= 1_048_576 else { return nil }
        return jpeg
    }
}

extension BrowserModel {
    func captureOfflineArticle(expectedURL: URL, generation: UUID) async throws -> OfflineArticle {
        guard !isLoading, documentGeneration == generation, restorationURL == expectedURL,
              let view = loadedWebView, let scriptURL = Bundle.main.url(forResource: "Reader", withExtension: "js") else { throw SavedPageError.stalePage }
        let script = try String(contentsOf: scriptURL, encoding: .utf8)
        let value = try await view.evaluateJavaScript(script, in: nil, contentWorld: .world(name: "DuoBrowser.Reader"))
        guard let article = ReaderArticle.parse(value, source: expectedURL) else { throw SavedPageError.invalidArticle }
        var blocks: [OfflineArticle.Block] = []
        var budget = 4_194_304
        var imageCount = 0
        let client = OfflineImageClient()
        for block in article.blocks {
            try Task.checkCancellation()
            var jpeg: Data?
            if let url = block.imageURL, imageCount < 8, budget > 0 {
                imageCount += 1
                if let data = try? await client.image(url, source: expectedURL), data.count <= budget {
                    jpeg = data; budget -= data.count
                }
            }
            blocks.append(.init(kind: block.kind, text: block.text, jpeg: jpeg))
        }
        try Task.checkCancellation()
        guard documentGeneration == generation, loadedWebView === view, restorationURL == expectedURL else { throw SavedPageError.stalePage }
        return OfflineArticle(title: article.title, address: expectedURL.absoluteString, blocks: blocks)
    }
}

extension BrowserSession {
    func savePage(_ entry: LibraryEntry, reading: Bool, offline: OfflineArticle? = nil) throws {
        guard entry.title.count <= 512, WebAddress.valid(URL(string: entry.address)) != nil,
              offline == nil || offline?.address == entry.address,
              SavedPagesPolicy.canMove(nil, to: entry.folderID, folders: bookmarkFolders) else { throw SavedPageError.invalidFolder }
        let old = reading ? readingList : bookmarks
        var updated = entry
        let index = old.firstIndex { $0.id == entry.id || $0.address == entry.address }
        let previous = index.map { old[$0] }
        if let previous { updated.id = previous.id; updated.offlineID = previous.offlineID }
        let store = offlineStore
        if let offline {
            let id = UUID()
            do { try store.write(offline, id: id) }
            catch let error as SavedPageError { throw error }
            catch { throw SavedPageError.saveFailed }
            updated.offlineID = id
        }
        var entries = old
        if let index { entries[index] = updated }
        else {
            guard entries.count < (reading ? LibraryLimits.readingList : LibraryLimits.bookmarks) else {
                if let id = updated.offlineID, id != previous?.offlineID { try? store.remove(id) }
                throw SavedPageError.saveFailed
            }
            entries.insert(updated, at: 0)
        }
        if reading { readingList = entries } else { bookmarks = entries }
        // write() commits the primary last; do not roll back after a backup-only post-commit error.
        guard saveNow() else {
            if reading { readingList = old } else { bookmarks = old }
            if let id = updated.offlineID, id != previous?.offlineID { try? store.remove(id) }
            throw SavedPageError.saveFailed
        }
        if let id = previous?.offlineID, id != updated.offlineID { try? store.remove(id) }
    }

    func saveFolder(_ folder: BookmarkFolder) throws {
        guard !folder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              folder.title.count <= 512, SavedPagesPolicy.canMove(folder.id, to: folder.parentID, folders: bookmarkFolders) else { throw SavedPageError.invalidFolder }
        let old = bookmarkFolders
        if let index = bookmarkFolders.firstIndex(where: { $0.id == folder.id }) { bookmarkFolders[index] = folder }
        else {
            guard bookmarkFolders.count < LibraryLimits.folders else { throw SavedPageError.saveFailed }
            bookmarkFolders.append(folder)
        }
        guard saveNow() else { bookmarkFolders = old; throw SavedPageError.saveFailed }
    }

    func removeOfflineCopy(_ entry: LibraryEntry) throws {
        guard let index = readingList.firstIndex(where: { $0.id == entry.id }), let id = readingList[index].offlineID else { return }
        let old = readingList[index]
        readingList[index].offlineID = nil
        guard saveNow(replaceBackup: true) else { readingList[index] = old; throw SavedPageError.saveFailed }
        do { try offlineStore.remove(id) }
        catch {
            readingList[index] = old
            _ = saveNow()
            throw SavedPageError.removalFailed
        }
    }
}
