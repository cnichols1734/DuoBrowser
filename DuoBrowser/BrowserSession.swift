import Combine
import Foundation
import UIKit
import WebKit

@MainActor
final class BrowserSession: ObservableObject {
    @Published private(set) var tabs: [BrowserModel] = []
    @Published private(set) var selectedID: UUID
    @Published private(set) var privateMode = false
    @Published var history: [LibraryEntry] = []
    @Published var bookmarks: [LibraryEntry] = []
    @Published var bookmarkFolders: [BookmarkFolder] = []
    @Published var readingList: [LibraryEntry] = []
    @Published private(set) var recentlyClosed: [ClosedTabRecord] = []
    @Published var closedTabNotice: UUID?
    @Published var showingSetup = false
    @Published var adBlockingEnabled: Bool {
        didSet {
            settingsStorage.set(adBlockingEnabled, forKey: "browser.adBlockingEnabled")
            tabs.forEach { $0.setAdBlockingEnabled(adBlockingEnabled) }
        }
    }
    @Published var searchEngine: BrowserSearchEngine {
        didSet {
            settingsStorage.set(searchEngine.rawValue, forKey: "browser.searchEngine")
            tabs.forEach { $0.searchEngine = searchEngine }
        }
    }
    @Published var appearance: BrowserAppearance {
        didSet { settingsStorage.set(appearance.rawValue, forKey: "browser.appearance") }
    }
    let websiteData: WebsiteDataController
    let setup: BrowserSetupModel
    let normalDownloads: BrowserDownloads
    private var privateDownloads: BrowserDownloads?
    let redditLinks: RedditLinkRouting
    var favorites: [LibraryEntry] { bookmarks.filter { $0.isFavorite != false } }
    @Published var showingLibrary = false
    @Published var showRegions = false
    @Published var showSystemStatus: Bool {
        didSet { settingsStorage.set(showSystemStatus, forKey: "browser.showSystemStatus") }
    }
    @Published var showingTabs = false
    @Published var workspaces = [Workspace.standard]
    @Published var workspaceID = Workspace.defaultID
    @Published var showingWorkspaces = false
    private var normalSites: [String: SitePreference] = [:]
    private var privateSites: [String: SitePreference] = [:]
    private var privateStore: WKWebsiteDataStore?
    private let privacyCurtain = PrivacyCurtain()
    private let settingsStorage: UserDefaults
    private let normalStore: WKWebsiteDataStore
    let offlineStore: OfflineArticleStore
    private let archiveStore: BrowserArchiveStore
    private var saveTask: Task<Void, Never>?
    private var memoryObserver: AnyCancellable?
    private var filterRefreshObserver: AnyCancellable?
    private var compactTask: Task<Void, Never>?
    private var retainedClosedTab: (recordID: UUID, tab: BrowserModel, index: Int)?
    private var closedTabExpiry: Task<Void, Never>?
    private var lastNormalID: UUID?
    private var lastPrivateID: UUID?

    var visibleTabs: [BrowserModel] {
        tabs.filter { $0.isPrivate == privateMode && (privateMode || $0.workspaceID == workspaceID) }
            .sorted { $0.isPinned && !$1.isPinned }
    }
    var workspaceName: String { workspaces.first { $0.id == workspaceID }?.name ?? "Personal" }
    var selected: BrowserModel { tabs.first { $0.id == selectedID } ?? tabs[0] }

    init(storage: UserDefaults = .standard, archiveStore: BrowserArchiveStore = BrowserArchiveStore(), dataStore: WKWebsiteDataStore = .default(), offlineStore: OfflineArticleStore? = nil) {
        self.settingsStorage = storage
        self.searchEngine = storage.string(forKey: "browser.searchEngine").flatMap(BrowserSearchEngine.init(rawValue:)) ?? .google
        self.appearance = storage.string(forKey: "browser.appearance").flatMap(BrowserAppearance.init(rawValue:)) ?? .system
        self.websiteData = WebsiteDataController(store: WebKitWebsiteDataAccess(store: dataStore))
        self.adBlockingEnabled = storage.object(forKey: "browser.adBlockingEnabled") as? Bool ?? true
        self.redditLinks = RedditLinkRouting(storage: storage)
        self.setup = BrowserSetupModel(storage: storage)
        self.showSystemStatus = storage.bool(forKey: "browser.showSystemStatus")
        self.normalStore = dataStore
        self.archiveStore = archiveStore
        self.offlineStore = offlineStore ?? OfflineArticleStore(directory: archiveStore.directory.appendingPathComponent("OfflineArticles", isDirectory: true))
        normalDownloads = BrowserDownloads(isPrivate: false, dataStore: dataStore,
            directory: archiveStore.directory.appendingPathComponent("Downloads", isDirectory: true))
        let saved = archiveStore.load()
        let legacy = storage.data(forKey: "browser.tabs.v1").flatMap {
            $0.count <= 8_000_000 ? try? JSONDecoder().decode(TabArchive.self, from: $0) : nil
        }?.validated()
        let restored = saved?.session ?? legacy
        let firstID = UUID()
        selectedID = restored?.selectedID ?? firstID
        tabs = restored?.tabs.map {
            let model = BrowserModel(id: $0.id, url: $0.address.flatMap(URL.init(string:)), fixture: $0.fixture, dataStore: dataStore)
            model.pendingScrollY = $0.scrollY
            model.workspaceID = $0.workspaceID ?? Workspace.defaultID
            model.isPinned = $0.pinned ?? false
            return model
        } ?? [BrowserModel(id: firstID, dataStore: dataStore)]
        history = saved?.history ?? []
        bookmarks = saved?.bookmarks ?? []
        bookmarkFolders = saved?.bookmarkFolders ?? []
        readingList = saved?.readingList ?? []
        recentlyClosed = saved?.recentlyClosed ?? []
        normalSites = saved?.sites ?? [:]
        workspaces = saved?.workspaces ?? [Workspace.standard]
        workspaceID = selected.workspaceID
        for tab in tabs { connect(tab) }
        if let warning = normalDownloads.errorMessage { selected.errorMessage = warning }
        selected.activate()
        startFilterUpdates()
        lastNormalID = selectedID
        websiteData.onWillRemove = { [weak self] in self?.releaseClosedTab() }
        // Migrate only after a durable write succeeds; normal cookies remain in WebKit's existing store.
        if legacy != nil, saveNow() { storage.removeObject(forKey: "browser.tabs.v1") }
        memoryObserver = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.releaseClosedTab()
                    self?.tabs.forEach { $0.clearSnapshot() }
                    self?.compactInactiveTabs(target: 2)
                }
            }
    }

    private func startFilterUpdates() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--browser-checks") { return }
        #endif
        if adBlockingEnabled { Task { await FilterCatalog.shared.refreshIfNeeded() } }
        filterRefreshObserver = NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self, !self.privateMode, self.adBlockingEnabled else { return }
                Task { await FilterCatalog.shared.refreshIfNeeded() }
            }
    }

    private func store(isPrivate: Bool) -> WKWebsiteDataStore {
        if !isPrivate { return normalStore }
        if let privateStore { return privateStore }
        let store = WKWebsiteDataStore.nonPersistent()
        privateStore = store
        return store
    }

    private func connect(_ tab: BrowserModel) {
        if tab.isPrivate {
            if privateDownloads == nil {
                privateDownloads = BrowserDownloads(isPrivate: true, dataStore: store(isPrivate: true),
                    directory: BrowserDownloads.stagingRoot.appendingPathComponent(UUID().uuidString))
            }
            tab.downloads = privateDownloads!
        } else { tab.downloads = normalDownloads }
        tab.downloadsOwnedBySession = true
        tab.searchEngine = searchEngine
        tab.redditLinks = redditLinks
        tab.setAdBlockingEnabled(adBlockingEnabled)
        tab.onSnapshot = { [weak self] in self?.trimSnapshots() }
        tab.onChange = { [weak self, weak tab] in
            guard let self, let tab, !tab.isPrivate else { return }
            // WebKit may publish the document title after didFinish records the visit.
            if !tab.isLoading, tab.title != tab.siteName, let address = tab.restorationURL?.absoluteString,
               let index = self.history.firstIndex(where: { $0.address == address }) {
                self.history[index].title = String(tab.title.prefix(512))
            }
            self.scheduleSave()
        }
        tab.onOpenWindow = { [weak self, weak tab] configuration in
            guard let self, let tab, self.tabs.count < 200 else { return nil }
            tab.hasWindowRelationships = true
            let child = self.makeTab(url: nil, privateTab: tab.isPrivate, configuration: configuration)
            child.hasWindowRelationships = true
            child.adoptWindow()
            return child.webView
        }
        tab.onOpenLink = { [weak self, weak tab] url in
            guard let self, let tab else { return }
            _ = self.newTab(url: url, privateTab: tab.isPrivate)
        }
        tab.onCreatePreview = { [weak self, weak tab] url in
            guard let self, let tab, WebAddress.valid(url) != nil else { return nil }
            let preview = BrowserModel(url: url, isPrivate: tab.isPrivate, dataStore: self.store(isPrivate: tab.isPrivate))
            preview.workspaceID = tab.workspaceID
            self.connect(preview)
            preview.onChange = nil
            preview.onOpenWindow = nil
            preview.onCreatePreview = nil
            preview.onPromotePreview = nil
            return preview
        }
        tab.onPromotePreview = { [weak self, weak tab] preview in
            guard let self else { return false }
            guard self.tabs.count < 200 else {
                tab?.errorMessage = "Close a tab before opening this preview (200 tab limit)."
                return false
            }
            self.connect(preview)
            self.tabs.append(preview)
            self.select(preview.id)
            if let url = preview.restorationURL { preview.onVisit?(url, preview.title) }
            self.saveNow()
            return true
        }
        tab.onClose = { [weak self, weak tab] in if let tab { self?.close(tab.id) } }
        tab.onVisit = { [weak self, weak tab] url, title in
            guard let self, let tab, self.tabs.contains(where: { $0.id == tab.id }), !tab.isPrivate, WebAddress.valid(url) != nil else { return }
            if self.history.first?.address == url.absoluteString { self.history.removeFirst() }
            self.history.insert(LibraryEntry(address: url.absoluteString, title: String(title.prefix(512))), at: 0)
            self.history = Array(self.history.prefix(LibraryLimits.history))
            self.scheduleSave()
        }
        tab.preferenceForURL = { [weak self, weak tab] url in
            guard let self, let tab, let host = url.host?.lowercased() else { return SitePreference() }
            return (tab.isPrivate ? self.privateSites : self.normalSites)[host] ?? SitePreference()
        }
        tab.onPreferenceChange = { [weak self, weak tab] host, preference in
            guard let self, let tab else { return }
            if tab.isPrivate { self.privateSites[host] = preference }
            else { self.normalSites[host] = preference; self.scheduleSave() }
        }
    }

    private func makeTab(url: URL?, privateTab: Bool, configuration: WKWebViewConfiguration? = nil) -> BrowserModel {
        selected.presentation.cancel()
        selected.captureSnapshot()
        trimSnapshots()
        let tab = BrowserModel(url: url, isPrivate: privateTab, dataStore: store(isPrivate: privateTab), configuration: configuration)
        tab.workspaceID = workspaceID
        connect(tab)
        tabs.append(tab)
        privateMode = privateTab
        selectedID = tab.id
        rememberSelection()
        compactInactiveTabs()
        showingTabs = false
        scheduleSave()
        return tab
    }

    @discardableResult
    func newTab(url: URL? = nil, privateTab: Bool? = nil) -> BrowserModel {
        guard tabs.count < 200 else { selected.errorMessage = "Close a tab before opening another (200 tab limit)."; return selected }
        let tab = makeTab(url: url, privateTab: privateTab ?? privateMode)
        tab.activate()
        return tab
    }

    /// External links open separately so existing forms/navigation and private mode are preserved.
    @discardableResult
    func openExternalURL(_ url: URL) -> Bool {
        guard let valid = WebAddress.valid(url) else { return false }
        showingLibrary = false
        showingWorkspaces = false
        guard tabs.count < 200 else {
            showingTabs = false
            selected.errorMessage = "Close a tab before opening another (200 tab limit)."
            return false
        }
        newTab(url: valid)
        return true
    }

    private func rememberSelection() {
        if privateMode { lastPrivateID = selectedID } else { lastNormalID = selectedID }
    }
    func switchMode(_ usePrivate: Bool) {
        guard usePrivate != privateMode else { return }
        guard tabs.contains(where: { $0.isPrivate == usePrivate }) || tabs.count < 200 else {
            selected.errorMessage = "Close a tab before opening another (200 tab limit)."; return
        }
        let showingOverview = showingTabs
        selected.presentation.cancel()
        rememberSelection()
        privateMode = usePrivate
        if !usePrivate, let tab = tabs.first(where: { $0.id == lastNormalID }) { workspaceID = tab.workspaceID }
        let prior = usePrivate ? lastPrivateID : lastNormalID
        if let tab = visibleTabs.first(where: { $0.id == prior }) ?? visibleTabs.first {
            selectedID = tab.id
            tab.lastUsed = Date()
            tab.activate()
        } else { newTab(privateTab: usePrivate) }
        showingTabs = showingOverview
    }

    func select(_ id: UUID) {
        guard let tab = tabs.first(where: { $0.id == id }) else { return }
        if selectedID != id { selected.presentation.cancel(); selected.captureSnapshot() }
        selectedID = id
        tab.lastUsed = Date()
        privateMode = tab.isPrivate
        if !tab.isPrivate { workspaceID = tab.workspaceID }
        rememberSelection()
        selected.revealControls()
        selected.activate()
        showingTabs = false
        trimSnapshots()
        compactInactiveTabs()
        scheduleSave()
    }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let order = visibleTabs.map(\.id)
        let visibleIndex = order.firstIndex(of: id)
        let adjacent = visibleIndex.flatMap { position in
            position + 1 < order.count ? order[position + 1] : (position > 0 ? order[position - 1] : nil)
        }
        let tab = tabs.remove(at: index)
        if !tab.isPrivate, let url = tab.restorationURL {
            let record = ClosedTabRecord(address: url.absoluteString, title: tab.title,
                scrollY: tab.loadedWebView.map { Double(max(0, $0.scrollView.contentOffset.y)) } ?? tab.pendingScrollY,
                workspaceID: tab.workspaceID, pinned: tab.isPinned)
            recentlyClosed = ClosedTabRecord.validated([record] + recentlyClosed)
            closedTabNotice = record.id
            if let view = tab.loadedWebView, !view.isLoading, !tab.hasWindowRelationships, !tab.hasRequestedWebsitePermission,
               view.cameraCaptureState == .none, view.microphoneCaptureState == .none {
                retainForUndo(tab, recordID: record.id, index: index)
            } else { tab.close() }
        } else { tab.close() }
        if !tabs.contains(where: \.isPrivate) {
            endPrivateSession()
        }
        if !tabs.contains(where: { !$0.isPrivate }) {
            let replacement = BrowserModel(dataStore: normalStore)
            connect(replacement); tabs.append(replacement)
        }
        if selectedID == id {
            let replacement = tabs.first(where: { $0.id == adjacent })
                ?? tabs.first(where: { $0.isPrivate == privateMode && (privateMode || $0.workspaceID == workspaceID) })
                ?? tabs.first(where: { $0.isPrivate == privateMode }) ?? tabs[min(index, tabs.count - 1)]
            selectedID = replacement.id
            privateMode = replacement.isPrivate
            if !replacement.isPrivate { workspaceID = replacement.workspaceID }
            selected.activate()
        }
        rememberSelection()
        saveNow()
    }

    @discardableResult
    func reopenClosedTab(_ id: UUID) -> Bool {
        guard !privateMode, tabs.count < 200,
              let record = recentlyClosed.first(where: { $0.id == id }),
              let url = WebAddress.valid(URL(string: record.address)) else { return false }
        let targetWorkspace = workspaces.contains { $0.id == record.workspaceID } ? record.workspaceID : Workspace.defaultID
        if let retained = retainedClosedTab, retained.recordID == id {
            closedTabExpiry?.cancel(); closedTabExpiry = nil; retainedClosedTab = nil
            let tab = retained.tab
            tab.isRetainedForUndo = false
            tab.workspaceID = targetWorkspace
            connect(tab)
            tab.loadedWebView?.setAllMediaPlaybackSuspended(false)
            tabs.insert(tab, at: min(retained.index, tabs.count))
            recentlyClosed.removeAll { $0.id == id }
            if closedTabNotice == id { closedTabNotice = nil }
            select(tab.id)
            saveNow()
            return true
        }
        let tab = makeTab(url: url, privateTab: false)
        tab.restoreClosedTabTitle(record.title)
        tab.pendingScrollY = record.scrollY
        tab.workspaceID = targetWorkspace
        tab.isPinned = record.pinned
        workspaceID = targetWorkspace
        recentlyClosed.removeAll { $0.id == id }
        if closedTabNotice == id { closedTabNotice = nil }
        tab.activate()
        saveNow()
        return true
    }

    private func retainForUndo(_ tab: BrowserModel, recordID: UUID, index: Int) {
        releaseClosedTab()
        tab.isRetainedForUndo = true
        tab.cancelReader()
        tab.presentation.cancel()
        tab.loadedWebView?.setAllMediaPlaybackSuspended(true)
        tab.loadedWebView?.removeFromSuperview()
        // A closed page cannot initiate new native UI or mutate the session while retained.
        tab.onChange = nil; tab.onVisit = nil; tab.onOpenWindow = nil; tab.onOpenLink = nil
        tab.onCreatePreview = nil; tab.onPromotePreview = nil; tab.onClose = nil; tab.onSnapshot = nil
        retainedClosedTab = (recordID, tab, index)
        closedTabExpiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.releaseClosedTab()
        }
    }

    func releaseClosedTab() {
        closedTabExpiry?.cancel(); closedTabExpiry = nil
        retainedClosedTab?.tab.close(); retainedClosedTab = nil
    }

    @discardableResult
    func clearRecentlyClosed() -> Bool {
        guard !privateMode else { return false }
        releaseClosedTab()
        let prior = recentlyClosed
        recentlyClosed.removeAll()
        closedTabNotice = nil
        guard saveNow(replaceBackup: true) else { recentlyClosed = prior; return false }
        return true
    }

    func switchAdjacentTab(_ direction: Int) {
        let candidates = visibleTabs
        guard let index = candidates.firstIndex(where: { $0.id == selectedID }),
              candidates.indices.contains(index + direction) else { return }
        select(candidates[index + direction].id)
    }

    func closePrivateTabs() {
        let wasPrivate = privateMode
        let closing = tabs.filter(\.isPrivate)
        tabs.removeAll(where: \.isPrivate)
        closing.forEach { $0.close() }
        endPrivateSession()
        if wasPrivate {
            privateMode = false
            selectedID = tabs.first(where: { $0.id == lastNormalID })?.id ?? tabs[0].id
            workspaceID = selected.workspaceID
            selected.activate()
        }
        saveNow()
    }
    private func endPrivateSession() {
        if privateDownloads?.cancelAll() == false {
            for tab in tabs where !tab.isPrivate { tab.errorMessage = privateDownloads?.errorMessage }
        }
        privateDownloads = nil
        let old = privateStore
        privateStore = nil
        privateSites.removeAll()
        lastPrivateID = nil
        old?.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
    }
    private func compactInactiveTabs(target: Int = 6) {
        compactTask?.cancel()
        compactTask = Task { [weak self] in
            // Let SwiftUI finish reparenting the selected view before checking inactive candidates.
            try? await Task.sleep(for: .milliseconds(400))
            guard let self, !Task.isCancelled else { return }
            for tab in self.tabs.sorted(by: { $0.lastUsed < $1.lastUsed }) {
                guard !Task.isCancelled, self.tabs.filter({ $0.loadedWebView != nil }).count > target else { break }
                _ = await tab.suspendIfIdle { [weak self, weak tab] in
                    guard let self, let tab else { return false }
                    return !Task.isCancelled && self.selectedID != tab.id && self.tabs.contains { $0.id == tab.id }
                }
            }
        }
    }
    private func trimSnapshots() {
        // Prefer the selected/recently used tabs, and enforce bytes after asynchronous captures finish.
        let ranked = tabs.sorted {
            if $0.id == selectedID { return $1.id != selectedID }
            if $1.id == selectedID { return false }
            return $0.lastUsed > $1.lastUsed
        }
        var bytes = 0
        var count = 0
        for tab in ranked where tab.snapshot != nil {
            let cost = tab.snapshotByteCount
            if !tab.isPrivate, count < 12, bytes + cost <= 8 * 1024 * 1024 {
                bytes += cost; count += 1
            } else { tab.clearSnapshot() }
        }
    }
    func showTabs() { selected.revealControls(); selected.captureSnapshot(); trimSnapshots(); showingTabs = true }

    func blockingExceptions(isPrivate: Bool) -> [String] {
        (isPrivate ? privateSites : normalSites).filter { $0.value.blockAds == false }.keys.sorted()
    }
    func restoreBlocking(host: String, isPrivate: Bool) {
        let host = host.lowercased()
        if isPrivate { privateSites[host]?.blockAds = true }
        else { normalSites[host]?.blockAds = true }
        for tab in tabs where tab.isPrivate == isPrivate && tab.restorationURL?.host?.lowercased() == host {
            tab.blockAds = true
        }
        objectWillChange.send()
        if !isPrivate { saveNow() }
    }

    func searchResults(_ query: String, isPrivate: Bool) -> [SearchResult] {
        var savedTitles: [String: String] = [:]
        for entry in bookmarks + (isPrivate ? [] : history) where savedTitles[entry.address] == nil {
            savedTitles[entry.address] = entry.title
        }
        let openTabs = tabs.filter { $0.isPrivate == isPrivate }.sorted { $0.lastUsed > $1.lastUsed }.map { tab in
            let address = tab.restorationURL?.absoluteString ?? ""
            let title = tab.title == tab.siteName ? savedTitles[address] ?? tab.title : tab.title
            return SearchResult(id: tab.id.uuidString, title: title, address: address,
                                kind: .tab, tabID: tab.id,
                                detail: tab.isPrivate ? "Private tab" : workspaces.first { $0.id == tab.workspaceID }?.name ?? "Tab")
        }
        let savedBookmarks = bookmarks.map {
            SearchResult(id: $0.id.uuidString, title: $0.title, address: $0.address, kind: .bookmark)
        }
        // Private searches never surface normal history or normal tabs.
        let savedHistory = isPrivate ? [] : history.map {
            SearchResult(id: $0.id.uuidString, title: $0.title, address: $0.address, kind: .history)
        }
        return UnifiedSearch.results(query, candidates: openTabs + savedBookmarks + savedHistory)
    }

    func switchWorkspace(_ id: UUID) {
        guard workspaces.contains(where: { $0.id == id }) else { return }
        let existing = tabs.filter { !$0.isPrivate && $0.workspaceID == id }.max { $0.lastUsed < $1.lastUsed }
        guard existing != nil || tabs.count < 200 else {
            selected.errorMessage = "Close a tab before opening this workspace (200 tab limit)."; return
        }
        workspaceID = id
        privateMode = false
        if let existing { select(existing.id) } else { newTab() }
    }
    func createWorkspace(_ name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty, workspaces.count < 20, tabs.count < 200 else { return }
        let workspace = Workspace(name: name)
        workspaces.append(workspace)
        switchWorkspace(workspace.id)
        saveNow()
    }
    func renameWorkspace(_ id: UUID, to name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
        guard !name.isEmpty, let index = workspaces.firstIndex(where: { $0.id == id }) else { return }
        workspaces[index].name = name
        saveNow()
    }
    func removeWorkspace(_ id: UUID) {
        guard id != Workspace.defaultID else { return }
        tabs.filter { $0.workspaceID == id }.forEach { $0.workspaceID = Workspace.defaultID }
        workspaces.removeAll { $0.id == id }
        if workspaceID == id { workspaceID = Workspace.defaultID }
        saveNow()
    }
    func move(_ tab: BrowserModel, to id: UUID) {
        guard !tab.isPrivate, workspaces.contains(where: { $0.id == id }) else { return }
        tab.workspaceID = id
        if selectedID == tab.id { workspaceID = id }
        objectWillChange.send()
        saveNow()
    }
    func togglePin(_ tab: BrowserModel) {
        tab.isPinned.toggle()
        objectWillChange.send()
        saveNow()
    }
    func addBookmark() {
        guard let url = selected.restorationURL else { return }
        // Deliberate Save is allowed in private mode; automatic history is never recorded there.
        guard !bookmarks.contains(where: { $0.address == url.absoluteString }) else { return }
        guard bookmarks.count < LibraryLimits.bookmarks else {
            selected.errorMessage = "Your bookmark library is full. Delete a bookmark before saving another page."
            return
        }
        bookmarks.insert(LibraryEntry(address: url.absoluteString, title: selected.title), at: 0)
        bookmarks = Array(bookmarks.prefix(LibraryLimits.bookmarks))
        saveNow()
    }
    @discardableResult
    func clearHistoryFromSettings() -> Bool {
        guard !privateMode else { return false }
        let priorHistory = history
        let priorRecovery = recentlyClosed
        releaseClosedTab()
        history.removeAll()
        recentlyClosed.removeAll()
        closedTabNotice = nil
        WebsiteIconStore.shared.clear()
        guard saveNow(replaceBackup: true) else {
            // Restore only retryable records. A released page and Undo notice must stay released.
            history = priorHistory
            recentlyClosed = priorRecovery
            return false
        }
        return true
    }

    func deleteHistory(ids: Set<UUID>? = nil) {
        WebsiteIconStore.shared.clear()
        if let ids {
            let removed = Set(history.filter { ids.contains($0.id) }.map(\.address))
            recentlyClosed.removeAll { removed.contains($0.address) }
            history.removeAll { ids.contains($0.id) }
        } else { history.removeAll(); recentlyClosed.removeAll() }
        if !recentlyClosed.contains(where: { $0.id == closedTabNotice }) { closedTabNotice = nil }
        if let retained = retainedClosedTab, !recentlyClosed.contains(where: { $0.id == retained.recordID }) { releaseClosedTab() }
        saveNow(replaceBackup: true)
    }
    func deleteBookmarks(ids: Set<UUID>) {
        WebsiteIconStore.shared.clear()
        bookmarks.removeAll { ids.contains($0.id) }
        saveNow(replaceBackup: true)
    }
    @discardableResult
    func deleteReadingList(ids: Set<UUID>) -> Bool {
        let old = readingList
        readingList.removeAll { ids.contains($0.id) }
        guard saveNow(replaceBackup: true) else { readingList = old; return false }
        var failed = Set<UUID>()
        for entry in old where ids.contains(entry.id) {
            if let id = entry.offlineID {
                do { try offlineStore.remove(id) } catch { failed.insert(entry.id) }
            }
        }
        if !failed.isEmpty {
            readingList = old.filter { !ids.contains($0.id) || failed.contains($0.id) }
            _ = saveNow(replaceBackup: true)
            selected.errorMessage = SavedPageError.removalFailed.localizedDescription
            return false
        }
        return true
    }

    func deleteBookmarkFolder(_ id: UUID) {
        var ids: Set<UUID> = [id]
        for _ in 0..<32 {
            let children = bookmarkFolders.filter { $0.parentID.map(ids.contains) ?? false }.map(\.id)
            let previous = ids.count
            ids.formUnion(children)
            if previous == ids.count { break }
        }
        bookmarkFolders.removeAll { ids.contains($0.id) }
        bookmarks.removeAll { $0.folderID.map(ids.contains) ?? false }
        WebsiteIconStore.shared.clear()
        saveNow(replaceBackup: true)
    }

    func applyImport(_ plan: BrowserImportPlan) throws {
        guard !privateMode else { throw BrowserImportError.saveFailed }
        let previous = (bookmarks, bookmarkFolders, history, readingList)
        bookmarks = plan.bookmarks; bookmarkFolders = plan.folders
        history = plan.history; readingList = plan.readingList
        guard saveNow() else {
            (bookmarks, bookmarkFolders, history, readingList) = previous
            throw BrowserImportError.saveFailed
        }
    }

    func background() {
        releaseClosedTab()
        tabs.forEach { $0.presentation.cancel(); if $0.isPrivate { $0.clearSnapshot(); $0.cancelReader() } }
        saveNow()
    }
    func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard !Task.isCancelled else { return }
            self?.saveTask = nil
            self?.saveNow()
        }
    }
    @discardableResult
    func saveNow(replaceBackup: Bool = false) -> Bool {
        let saveError = "Your browsing changes could not be saved on this device."
        saveTask?.cancel(); saveTask = nil
        let normal = tabs.filter { !$0.isPrivate }
        guard let first = normal.first else { return false }
        let archive = BrowserArchive(session: TabArchive(tabs: normal.map {
            TabRecord(id: $0.id, address: $0.restorationURL?.absoluteString, fixture: $0.isFixture,
                      scrollY: $0.loadedWebView.map { Double(max(0, $0.scrollView.contentOffset.y)) } ?? $0.pendingScrollY, workspaceID: $0.workspaceID, pinned: $0.isPinned)
        }, selectedID: normal.contains { $0.id == selectedID } ? selectedID : lastNormalID ?? first.id),
        history: history, bookmarks: bookmarks, sites: normalSites, workspaces: workspaces,
        bookmarkFolders: bookmarkFolders, readingList: readingList, recentlyClosed: recentlyClosed)
        do {
            if replaceBackup { try archiveStore.replace(archive) } else { try archiveStore.write(archive) }
            if selected.errorMessage == saveError { selected.errorMessage = nil }
            return true
        } catch { selected.errorMessage = saveError; return false }
    }
}
