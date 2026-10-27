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
    @Published var showingTabs = false
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

    var visibleTabs: [BrowserModel] { tabs.filter { $0.isPrivate == privateMode } }
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
            return model
        } ?? [BrowserModel(id: firstID, dataStore: dataStore)]
        history = saved?.history ?? []
        bookmarks = saved?.bookmarks ?? []
        normalSites = saved?.sites ?? [:]
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
        tab.onChange = { [weak self, weak tab] in if tab?.isPrivate == false { self?.scheduleSave() } }
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
        tab.onClose = { [weak self, weak tab] in if let tab { self?.close(tab.id) } }
        tab.onVisit = { [weak self, weak tab] url, title in
            guard let self, let tab, !tab.isPrivate, WebAddress.valid(url) != nil else { return }
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
        let showingOverview = showingTabs
        selected.presentation.cancel()
        rememberSelection()
        privateMode = usePrivate
        let prior = usePrivate ? lastPrivateID : lastNormalID
        if let tab = visibleTabs.first(where: { $0.id == prior }) ?? visibleTabs.first {
            selectedID = tab.id
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
        if !tabs.contains(where: \.isPrivate) { endPrivateSession() }
        if !tabs.contains(where: { !$0.isPrivate }) {
            let replacement = BrowserModel(dataStore: normalStore)
            connect(replacement); tabs.append(replacement)
        }
        if selectedID == id {
            let replacement = tabs.first(where: { $0.isPrivate == privateMode }) ?? tabs[min(index, tabs.count - 1)]
            selectedID = replacement.id
            privateMode = replacement.isPrivate
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
        let retained = Set(tabs.suffix(12).map(\.id) + [selectedID])
        tabs.filter { !retained.contains($0.id) }.forEach { $0.clearSnapshot() }
    }
    func showTabs() { selected.revealControls(); selected.captureSnapshot(); trimSnapshots(); showingTabs = true }

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
        tabs.forEach { $0.presentation.cancel(); if $0.isPrivate { $0.clearSnapshot() } }
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
                      scrollY: $0.loadedWebView.map { Double(max(0, $0.scrollView.contentOffset.y)) } ?? $0.pendingScrollY)
        }, selectedID: normal.contains { $0.id == selectedID } ? selectedID : lastNormalID ?? first.id),
        history: history, bookmarks: bookmarks, sites: normalSites)
        do {
            if replaceBackup { try archiveStore.replace(archive) } else { try archiveStore.write(archive) }
            return true
        } catch { selected.errorMessage = "Your browsing changes could not be saved on this device."; return false }
    }
}
