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
    var retryOwner: UUID?
    weak var retryBrowser: BrowserModel?
    var retryDocument: UUID?
    var hasRetryContext: Bool {
        guard let browser = retryBrowser, let source = retrySource, let retryDocument else { return false }
        return browser.documentGeneration == retryDocument && browser.loadedWebView === source && source.url == retryPage
    }
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
    #if DEBUG
    // Opt-in synthetic harness observer; normal browsing never installs a sink.
    var testDownloadObserver: ((String) -> Void)?
    #endif
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
    private struct PendingRetry {
        let source: WKWebView
        let owner: UUID?
    }
    private var pendingRetries: [UUID: PendingRetry] = [:]
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
    func hasWork(for owner: UUID) -> Bool {
        active.values.contains { $0.owner == owner } || pendingRetries.values.contains { $0.owner == owner }
    }
    var completedCount: Int { items.filter { $0.state == .completed }.count }
    func sourceClosed(_ owner: UUID) {
        #if DEBUG
        testDownloadObserver?("source closed work=\(hasWork(for: owner)) active=\(active.count) pending=\(pendingRetries.count)")
        #endif
        // Also clear stopped jobs whose weak source may still be retained by another transfer.
        for item in items where item.retryOwner == owner { item.retrySource = nil }
        for transfer in active.values where transfer.owner == owner { closeSource(transfer.source) }
        for retry in pendingRetries.values where retry.owner == owner { closeSource(retry.source) }
    }
    func sourceDocumentChanged(_ owner: UUID) {
        for item in items where item.retryOwner == owner {
            item.retrySource = nil; item.retryBrowser = nil; item.retryDocument = nil
            if !item.isDownloading {
                item.canRetry = item.resumeData != nil
                if !item.canRetry && item.request != nil { item.message = "Open the original website to download this file again." }
            }
        }
    }
    private func closeSource(_ source: WKWebView?) {
        source?.navigationDelegate = closedPagePolicy
        source?.setAllMediaPlaybackSuspended(true, completionHandler: nil)
    }


    func add(_ download: WKDownload, owner: UUID? = nil, source: WKWebView? = nil, browser: BrowserModel? = nil) {
        #if DEBUG
        testDownloadObserver?("transfer add invalidated=\(invalidated) active=\(activeCount) items=\(items.count)")
        #endif
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
        attach(download, to: item, owner: owner, source: source, browser: browser)
        persist()
    }

    private func attach(_ download: WKDownload, to item: BrowserDownload, owner: UUID?, source: WKWebView? = nil,
                        captureRetryContext: Bool = true, browser: BrowserModel? = nil) {
        item.isDownloading = true; item.canRetry = false; item.message = nil
        if let request = download.originalRequest, request.httpMethod == nil || request.httpMethod == "GET",
           WebAddress.valid(request.url) != nil, request.httpBody == nil, request.httpBodyStream == nil { item.request = request }
        if captureRetryContext, let source = source ?? download.webView, source !== retryView {
            item.retrySource = source; item.retryPage = source.url; item.retryOwner = owner
            item.retryBrowser = browser; item.retryDocument = browser?.documentGeneration
        }
        let key = ObjectIdentifier(download), generation = item.generation
        active[key] = Transfer(item: item, download: download, source: source ?? download.webView, owner: owner)
        download.delegate = self
        #if DEBUG
        testDownloadObserver?("transfer delegate attached owner=\(owner != nil) request=\(item.request?.url?.absoluteString ?? "nil")")
        #endif
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
        #if DEBUG
        if transfer.item.received == 0 && received > 0 { testDownloadObserver?("first progress received=\(received) expected=\(expected)") }
        #endif
        transfer.item.received = max(transfer.item.received, max(0, received))
        transfer.item.expected = max(transfer.item.expected, max(0, expected))
        let total = items.reduce(Int64(0)) { $0 + min(DownloadStore.fileLimit + 1, max(0, $1.received)) }
        if received > DownloadStore.fileLimit || expected > DownloadStore.fileLimit || total > DownloadStore.storageLimit {
            failLimit(transfer.item, message: "This download exceeds the available download storage. Save or remove existing files, then try again.")
        }
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        #if DEBUG
        testDownloadObserver?("destination callback active=\(active[ObjectIdentifier(download)] != nil) length=\(response.expectedContentLength)")
        #endif
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
            #if DEBUG
            testDownloadObserver?("destination provided name=\(item.name)")
            #endif
            completionHandler(item.file)
        } catch {
            #if DEBUG
            testDownloadObserver?("destination failed domain=\((error as NSError).domain) code=\((error as NSError).code)")
            #endif
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
        #if DEBUG
        testDownloadObserver?("finish callback active=\(active[ObjectIdentifier(download)] != nil)")
        #endif
        guard let transfer = active.removeValue(forKey: ObjectIdentifier(download)) else { return }
        let item = transfer.item
        hasUnseenDownloads = true
        item.isDownloading = false; item.state = .completed; item.resumeData = nil
        item.received = Int64((try? item.file?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        #if DEBUG
        testDownloadObserver?("finish measured fileBytes=\(item.received)")
        #endif
        if store.file(for: item.record) == nil || store.diskUsage() > DownloadStore.storageLimit {
            item.state = .failed; item.message = "The downloaded file is unavailable or exceeds the storage limit."
            item.canRetry = item.request != nil && item.hasRetryContext
            _ = discardFile(item)
        } else { item.request = nil }
        #if DEBUG
        testDownloadObserver?("finish validated state=\(item.state.rawValue) bytes=\(item.received)")
        #endif

        download.delegate = nil
        objectWillChange.send(); persist()
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        #if DEBUG
        testDownloadObserver?("failure callback active=\(active[ObjectIdentifier(download)] != nil) domain=\((error as NSError).domain) code=\((error as NSError).code) resumeBytes=\(resumeData?.count ?? 0)")
        #endif
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
        #if DEBUG
        testDownloadObserver?("cancel invoked state=\(item.state.rawValue) received=\(item.received)")
        #endif
        item.generation = UUID(); pendingRetries.removeValue(forKey: item.id)
        if let entry = active.first(where: { $0.value.item.id == item.id }) {
            active.removeValue(forKey: entry.key)
            entry.value.download.delegate = nil
            let generation = item.generation
            entry.value.download.cancel { [weak self, weak item] data in
                #if DEBUG
                self?.testDownloadObserver?("cancel completed currentGeneration=\(item?.generation == generation) resumeBytes=\(data?.count ?? 0)")
                #endif
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
        #if DEBUG
        testDownloadObserver?("retry requested state=\(item.state.rawValue) eligible=\(item.canRetry) context=\(item.hasRetryContext) resume=\(item.resumeData != nil)")
        #endif
        guard !invalidated, items.contains(where: { $0 === item }), !item.isDownloading,
              item.canRetry, item.resumeData != nil || item.request != nil else { return }
        guard activeCount < 10 else {
            errorMessage = "Wait for a transfer to finish before retrying this download."
            return
        }
        let view: WKWebView
        let owner: UUID?
        if item.resumeData != nil {
            // Native resume belongs to the manager's dedicated web view, not the former tab.
            owner = nil
            let config = WKWebViewConfiguration(); config.websiteDataStore = dataStore
            if retryView == nil { retryView = WKWebView(frame: .zero, configuration: config) }
            guard let retryView else { return }; view = retryView
        } else if item.hasRetryContext, let source = item.retrySource { view = source; owner = item.retryOwner }
        else {
            item.canRetry = false; item.message = "Open the original website to download this file again."; return
        }
        let token = UUID(); item.generation = token
        let resume = item.resumeData; item.resumeData = nil
        item.isDownloading = true; item.canRetry = false; item.message = nil
        // Keep the original view alive and owned while WebKit asynchronously creates the download.
        pendingRetries[item.id] = PendingRetry(source: view, owner: owner); objectWillChange.send()
        let completion: @MainActor @Sendable (WKDownload) -> Void = { [weak self, weak item] download in
            #if DEBUG
            self?.testDownloadObserver?("retry callback currentGeneration=\(item?.generation == token)")
            #endif
            guard let self, let item, !self.invalidated, item.generation == token,
                  self.items.contains(where: { $0 === item }),
                  let pending = self.pendingRetries.removeValue(forKey: item.id) else {
                download.cancel { _ in }; return
            }
            self.attach(download, to: item, owner: pending.owner, source: pending.source, captureRetryContext: false)
        }
        if let resume { view.resumeDownload(fromResumeData: resume, completionHandler: completion) }
        else if let request = item.request {
            guard discardFile(item) else {
                pendingRetries.removeValue(forKey: item.id); item.isDownloading = false; item.state = .failed
                objectWillChange.send(); persist(); return
            }
            view.startDownload(using: request, completionHandler: completion)
        }
        persist()
    }

    func remove(_ item: BrowserDownload) {
        if item.isDownloading || pendingRetries[item.id] != nil { cancel(item) }
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
