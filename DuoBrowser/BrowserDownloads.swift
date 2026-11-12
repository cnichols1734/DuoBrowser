import Combine
import UIKit
import WebKit

@MainActor
final class BrowserDownload: ObservableObject, Identifiable {
    let id: UUID
    let date: Date
    @Published var name: String
    @Published var state: DownloadRecord.State
    @Published var isDownloading = false
    @Published var received: Int64
    @Published var expected: Int64 = 0
    @Published var message: String?
    @Published var canRetry = false
    var file: URL?
    var request: URLRequest?
    var resumeData: Data?
    weak var retrySource: WKWebView?
    var retryPage: URL?
    var hasRetryContext: Bool { retrySource != nil && retrySource?.url == retryPage }
    var generation = UUID()
    init(_ record: DownloadRecord) {
        id = record.id; date = record.date; name = record.name; state = record.state; received = record.bytes
        if state == .interrupted { message = "Interrupted. Download this file again from the website." }
        else if state == .failed { message = "Download failed. Try the link on the website again." }
        else if state == .recovered { message = "Recovered file. Its completion could not be verified." }
    }
    var record: DownloadRecord { DownloadRecord(id: id, name: name, date: date, bytes: max(0, received), state: isDownloading ? .interrupted : state) }
}

/// Session-owned transfers keep WebKit's profile, and survive closing their originating normal tab.
@MainActor
final class BrowserDownloads: NSObject, ObservableObject, WKDownloadDelegate {
    @Published private(set) var items: [BrowserDownload] = []
    @Published var errorMessage: String?
    @Published var hasUnseenDownloads = false
    let isPrivate: Bool
    let store: DownloadStore
    private let dataStore: WKWebsiteDataStore
    private var retryView: WKWebView?
    private let closedPagePolicy = ClosedDownloadPagePolicy()
    private struct Transfer {
        let item: BrowserDownload
        let download: WKDownload
        let source: WKWebView?
        let owner: UUID?
        var observations: [NSKeyValueObservation] = []
    }
    private var active: [ObjectIdentifier: Transfer] = [:]
    private var pendingRetries = Set<UUID>()
    private var invalidated = false

    init(isPrivate: Bool, dataStore: WKWebsiteDataStore, directory: URL,
         removeFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        let cleanupFailed = Self.previousCleanupFailed
        self.isPrivate = isPrivate; self.dataStore = dataStore
        store = DownloadStore(directory: directory, persistent: !isPrivate, removeFile: removeFile)
        super.init()
        if cleanupFailed { errorMessage = "Previous private download files couldn’t be removed. Restart DuoBrowser to retry cleanup." }
        items = store.load().map { record in
            let item = BrowserDownload(record); item.file = store.file(for: record)
            return item
        }
    }
    private static let previousCleanupFailed: Bool = {
        guard FileManager.default.fileExists(atPath: stagingRoot.path) else { return false }
        do { try FileManager.default.removeItem(at: stagingRoot); return false }
        catch { return true }
    }()
    static var stagingRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("BrowserDownloads", isDirectory: true) }
    static func safeFilename(_ input: String) -> String { DownloadRecord.safeFilename(input) }
    var activeCount: Int { active.count + pendingRetries.count }
    var hasWork: Bool { activeCount > 0 }
    func hasWork(for owner: UUID) -> Bool { active.values.contains { $0.owner == owner } }
    var completedCount: Int { items.filter { $0.state == .completed }.count }
    func sourceClosed(_ owner: UUID) {
        for transfer in active.values where transfer.owner == owner {
            transfer.item.retrySource = nil
            transfer.source?.navigationDelegate = closedPagePolicy
            transfer.source?.setAllMediaPlaybackSuspended(true, completionHandler: nil)
        }
    }


    func add(_ download: WKDownload, owner: UUID? = nil, source: WKWebView? = nil) {
        guard !invalidated, activeCount < 10, items.count < DownloadStore.itemLimit else {
            download.cancel { _ in }
            errorMessage = "Remove a download or wait for a transfer to finish before starting another."
            return
        }
        guard store.diskUsage() < DownloadStore.storageLimit else {
            download.cancel { _ in }
            errorMessage = "Download storage is full or needs cleanup. Remove saved or recovered files in Downloads, then try again."
            return
        }
        let item = BrowserDownload(DownloadRecord(id: UUID(), name: "Downloading…", date: Date(), bytes: 0, state: .interrupted))
        item.message = nil
        items.insert(item, at: 0)
        hasUnseenDownloads = true
        attach(download, to: item, owner: owner, source: source)
        persist()
    }

    private func attach(_ download: WKDownload, to item: BrowserDownload, owner: UUID?, source: WKWebView? = nil) {
        item.isDownloading = true; item.canRetry = false; item.message = nil
        if let request = download.originalRequest, request.httpMethod == nil || request.httpMethod == "GET",
           WebAddress.valid(request.url) != nil, request.httpBody == nil, request.httpBodyStream == nil { item.request = request }
        if let source = source ?? download.webView, source !== retryView { item.retrySource = source; item.retryPage = source.url }
        let key = ObjectIdentifier(download), generation = item.generation
        active[key] = Transfer(item: item, download: download, source: source ?? download.webView, owner: owner)
        download.delegate = self
        let receivedObservation = download.progress.observe(\.completedUnitCount, options: [.initial, .new]) { [weak self] progress, _ in
            let received = progress.completedUnitCount, expected = progress.totalUnitCount
            Task { @MainActor [weak self] in self?.updateProgress(key, generation: generation, received: received, expected: expected) }
        }
        let totalObservation = download.progress.observe(\.totalUnitCount, options: [.initial, .new]) { [weak self] progress, _ in
            let received = progress.completedUnitCount, expected = progress.totalUnitCount
            Task { @MainActor [weak self] in self?.updateProgress(key, generation: generation, received: received, expected: expected) }
        }
        active[key]?.observations = [receivedObservation, totalObservation]
        objectWillChange.send()
    }

    private func updateProgress(_ key: ObjectIdentifier, generation: UUID, received: Int64, expected: Int64) {
        guard let transfer = active[key], transfer.item.generation == generation else { return }
        transfer.item.received = max(transfer.item.received, max(0, received))
        transfer.item.expected = max(transfer.item.expected, max(0, expected))
        let total = items.reduce(Int64(0)) { $0 + min(DownloadStore.fileLimit + 1, max(0, $1.received)) }
        if received > DownloadStore.fileLimit || expected > DownloadStore.fileLimit || total > DownloadStore.storageLimit {
            failLimit(transfer.item, message: "This download exceeds the available download storage. Save or remove existing files, then try again.")
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        guard let transfer = active[ObjectIdentifier(download)] else { completionHandler(nil); return }
        let item = transfer.item
        guard store.acceptsResponse(length: response.expectedContentLength, excluding: item.id) else {
            completionHandler(nil); failLimit(item, message: "This file is too large for the download storage. The per-file limit is 1 GB."); return
        }
        do {
            item.name = Self.safeFilename(suggestedFilename)
            // A destination callback requires a nonexistent file, including a server restarting a resume.
            if let file = item.file, FileManager.default.fileExists(atPath: file.path) {
                try store.remove(item.id); item.received = 0
            }
            item.file = try store.destination(id: item.id, name: item.name)
            item.expected = max(0, response.expectedContentLength)
            persist()
            completionHandler(item.file)
        } catch {
            completionHandler(nil)
            failLimit(item, message: "The file could not be saved. Check available device storage and try again.")
        }
    }

    func download(_ download: WKDownload, didReceive challenge: URLAuthenticationChallenge,
                  completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Keep platform certificate validation and authentication handling; never trust a certificate ourselves.
        completionHandler(.performDefaultHandling, nil)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let transfer = active.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let item = transfer.item
        hasUnseenDownloads = true
        item.isDownloading = false; item.state = .completed; item.resumeData = nil
        item.received = Int64((try? item.file?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        if store.file(for: item.record) == nil || store.diskUsage() > DownloadStore.storageLimit {
            item.state = .failed; item.message = "The downloaded file is unavailable or exceeds the storage limit."
            item.canRetry = item.request != nil && item.hasRetryContext
            _ = discardFile(item)
        } else { item.request = nil }

        download.delegate = nil
        objectWillChange.send(); persist()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let transfer = active.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let item = transfer.item
        hasUnseenDownloads = true
        item.isDownloading = false; item.state = .failed
        item.resumeData = item.request == nil ? nil : resumeData.flatMap { $0.count <= 16_000_000 ? $0 : nil }
        item.canRetry = item.resumeData != nil || (item.request != nil && item.hasRetryContext)
        item.message = item.canRetry ? "Download interrupted. Try again when you’re connected." : "Download failed. Try the link on the website again."
        // WebKit's opaque resume token may refer to the partial destination. Keep it until retry/removal.
        if item.resumeData == nil { _ = discardFile(item) }
        download.delegate = nil
        objectWillChange.send(); persist()
    }

    private func failLimit(_ item: BrowserDownload, message: String) {
        cancel(item)
        item.generation = UUID(); _ = discardFile(item)
        item.state = .failed; item.message = message; item.canRetry = item.request != nil && item.hasRetryContext; item.resumeData = nil
        persist()
    }

    @discardableResult
    func cancel(_ item: BrowserDownload) -> Bool {
        item.generation = UUID(); pendingRetries.remove(item.id)
        if let entry = active.first(where: { $0.value.item.id == item.id }) {
            active.removeValue(forKey: entry.key)
            entry.value.download.delegate = nil
            let generation = item.generation
            entry.value.download.cancel { [weak self, weak item] data in
                guard let self, let item, !self.invalidated, item.generation == generation,
                      self.items.contains(where: { $0 === item }), item.request != nil,
                      let data, data.count <= 16_000_000 else { return }
                item.resumeData = data; item.canRetry = true
            }
        }
        item.isDownloading = false; item.state = .canceled; item.message = "Canceled"
        item.resumeData = nil; item.canRetry = item.request != nil && item.hasRetryContext
        objectWillChange.send(); persist()
        return true
    }

    func retry(_ item: BrowserDownload) {
        guard !invalidated, items.contains(where: { $0 === item }), !item.isDownloading,
              item.canRetry, item.resumeData != nil || item.request != nil else { return }
        guard activeCount < 10 else {
            errorMessage = "Wait for a transfer to finish before retrying this download."
            return
        }
        let view: WKWebView
        if item.resumeData != nil {
            let config = WKWebViewConfiguration(); config.websiteDataStore = dataStore
            if retryView == nil { retryView = WKWebView(frame: .zero, configuration: config) }
            guard let retryView else { return }; view = retryView
        } else if item.hasRetryContext, let source = item.retrySource { view = source }
        else {
            item.canRetry = false; item.message = "Open the original website to download this file again."; return
        }
        let token = UUID(); item.generation = token
        let resume = item.resumeData; item.resumeData = nil
        item.isDownloading = true; item.canRetry = false; item.message = nil
        pendingRetries.insert(item.id); objectWillChange.send()
        let completion: @MainActor @Sendable (WKDownload) -> Void = { [weak self, weak item] download in
            guard let self, let item, !self.invalidated, item.generation == token,
                  self.pendingRetries.remove(item.id) != nil, self.items.contains(where: { $0 === item }) else {
                download.cancel { _ in }; return
            }
            self.attach(download, to: item, owner: nil)
        }
        if let resume { view.resumeDownload(fromResumeData: resume, completionHandler: completion) }
        else if let request = item.request {
            guard discardFile(item) else {
                pendingRetries.remove(item.id); item.isDownloading = false; item.state = .failed
                objectWillChange.send(); persist(); return
            }
            view.startDownload(using: request, completionHandler: completion)
        }
        persist()
    }

    func remove(_ item: BrowserDownload) {
        if item.isDownloading || pendingRetries.contains(item.id) { cancel(item) }
        let removed = discardFile(item)
        guard removed else { persist(); return }
        item.generation = UUID()
        items.removeAll { $0.id == item.id }; item.request = nil; item.resumeData = nil
        persist()
        let known = Set(items.map(\.id))
        for record in store.load() where !known.contains(record.id) && items.count < DownloadStore.itemLimit {
            let recovered = BrowserDownload(record); recovered.file = store.file(for: record); items.append(recovered)
        }
    }
    @discardableResult
    func cancelAll() -> Bool {
        invalidated = true
        var failures = Set<UUID>()
        for item in items { cancel(item); if !discardFile(item) { failures.insert(item.id) } }
        items.removeAll { !failures.contains($0.id) }; retryView = nil
        if isPrivate {
            do { try store.erase(); items.removeAll(); return true }
            catch { errorMessage = "Private download files couldn’t all be removed. Restart DuoBrowser to retry cleanup."; return false }
        }
        persist()
        return failures.isEmpty
    }
    private func discardFile(_ item: BrowserDownload) -> Bool {
        do {
            try store.remove(item.id); item.file = nil; item.received = 0
            return true
        } catch {
            errorMessage = "This download couldn’t be removed. Please try Remove Download again."
            if item.state != .completed || store.file(for: item.record) == nil {
                item.state = .failed; item.message = errorMessage; item.canRetry = false
            }
            return false
        }
    }
    private func persist() {
        do { try store.save(items.map(\.record)) }
        catch { errorMessage = "Download history couldn’t be saved. Keep this session open and save important files to Files." }
    }
}


/// A retained transfer must not let a closed page navigate or open another document.
@MainActor
private final class ClosedDownloadPagePolicy: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        decisionHandler(.cancel)
    }
}
