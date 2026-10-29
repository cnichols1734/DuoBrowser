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
    @Published var showingLibrary = false
    @Published var showRegions = false
    #if DEBUG
    @Published var showSystemStatus = false
    #endif
    @Published var showingTabs = false
    @Published var workspaces = [Workspace.standard]
    @Published var workspaceID = Workspace.defaultID
    @Published var showingWorkspaces = false
    private var normalSites: [String: SitePreference] = [:]
    private var privateSites: [String: SitePreference] = [:]
    private var privateStore: WKWebsiteDataStore?
    private let privacyCurtain = PrivacyCurtain()
    private let normalStore: WKWebsiteDataStore
    private let archiveStore: BrowserArchiveStore
    private var saveTask: Task<Void, Never>?
    private var memoryObserver: AnyCancellable?
    private var compactTask: Task<Void, Never>?
    private var lastNormalID: UUID?
    private var lastPrivateID: UUID?

    var visibleTabs: [BrowserModel] {
        tabs.filter { $0.isPrivate == privateMode && (privateMode || $0.workspaceID == workspaceID) }
            .sorted { $0.isPinned && !$1.isPinned }
    }
    var workspaceName: String { workspaces.first { $0.id == workspaceID }?.name ?? "Personal" }
    var selected: BrowserModel { tabs.first { $0.id == selectedID } ?? tabs[0] }

    init(storage: UserDefaults = .standard, archiveStore: BrowserArchiveStore = BrowserArchiveStore(), dataStore: WKWebsiteDataStore = .default()) {
        self.normalStore = dataStore
        self.archiveStore = archiveStore
        BrowserDownloads.cleanPreviousSession()
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
        normalSites = saved?.sites ?? [:]
        workspaces = saved?.workspaces ?? [Workspace.standard]
        workspaceID = selected.workspaceID
        for tab in tabs { connect(tab) }
        selected.activate()
        lastNormalID = selectedID
        // Migrate only after a durable write succeeds; normal cookies remain in WebKit's existing store.
        if legacy != nil, saveNow() { storage.removeObject(forKey: "browser.tabs.v1") }
        memoryObserver = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.tabs.forEach { $0.clearSnapshot() }
                    self?.compactInactiveTabs(target: 2)
                }
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
            self.history = Array(self.history.prefix(1000))
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
        let tab = tabs.remove(at: index)
        tab.close()
        if !tabs.contains(where: \.isPrivate) {
            endPrivateSession()
        }
        if !tabs.contains(where: { !$0.isPrivate }) {
            let replacement = BrowserModel(dataStore: normalStore)
            connect(replacement); tabs.append(replacement)
        }
        if selectedID == id {
            let replacement = tabs.first(where: { $0.isPrivate == privateMode && (privateMode || $0.workspaceID == workspaceID) })
                ?? tabs.first(where: { $0.isPrivate == privateMode }) ?? tabs[min(index, tabs.count - 1)]
            selectedID = replacement.id
            privateMode = replacement.isPrivate
            if !replacement.isPrivate { workspaceID = replacement.workspaceID }
            selected.activate()
        }
        rememberSelection()
        saveNow()
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
        bookmarks.insert(LibraryEntry(address: url.absoluteString, title: selected.title), at: 0)
        bookmarks = Array(bookmarks.prefix(500))
        saveNow()
    }
    func deleteHistory(ids: Set<UUID>? = nil) {
        if let ids { history.removeAll { ids.contains($0.id) } } else { history.removeAll() }
        saveNow(replaceBackup: true)
    }
    func deleteBookmarks(ids: Set<UUID>) {
        bookmarks.removeAll { ids.contains($0.id) }
        saveNow(replaceBackup: true)
    }
    func background() {
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
        saveTask?.cancel(); saveTask = nil
        let normal = tabs.filter { !$0.isPrivate }
        guard let first = normal.first else { return false }
        let archive = BrowserArchive(session: TabArchive(tabs: normal.map {
            TabRecord(id: $0.id, address: $0.restorationURL?.absoluteString, fixture: $0.isFixture,
                      scrollY: $0.loadedWebView.map { Double(max(0, $0.scrollView.contentOffset.y)) } ?? $0.pendingScrollY, workspaceID: $0.workspaceID, pinned: $0.isPinned)
        }, selectedID: normal.contains { $0.id == selectedID } ? selectedID : lastNormalID ?? first.id),
        history: history, bookmarks: bookmarks, sites: normalSites, workspaces: workspaces)
        do {
            if replaceBackup { try archiveStore.replace(archive) } else { try archiveStore.write(archive) }
            return true
        } catch { selected.errorMessage = "Your browsing changes could not be saved on this device."; return false }
    }
}
