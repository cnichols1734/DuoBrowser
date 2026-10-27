import Combine
import Foundation

@MainActor
final class BrowserSession: ObservableObject {
    @Published private(set) var tabs: [BrowserModel] = []
    @Published private(set) var selectedID: UUID
    @Published var fullWidth = true
    @Published var showRegions = false
    @Published var showingTabs = false
    private let storage: UserDefaults
    private let archiveKey = "browser.tabs.v1"

    var selected: BrowserModel { tabs.first { $0.id == selectedID } ?? tabs[0] }

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        let restored = storage.data(forKey: archiveKey)
            .flatMap { try? JSONDecoder().decode(TabArchive.self, from: $0) }?.validated()
        let firstID = UUID()
        selectedID = restored?.selectedID ?? firstID
        tabs = restored?.tabs.map {
            BrowserModel(id: $0.id, url: $0.address.flatMap(URL.init(string:)), fixture: $0.fixture)
        } ?? [BrowserModel(id: firstID)]
        for tab in tabs { connect(tab) }
        selected.activate()
    }

    private func connect(_ tab: BrowserModel) {
        tab.onChange = { [weak self] in self?.save() }
        tab.onOpenTab = { [weak self] request in
            guard let self, let url = request.url else { return }
            self.newTab(url: url)
        }
    }

    @discardableResult
    func newTab(url: URL? = nil) -> BrowserModel {
        selected.captureSnapshot()
        let tab = BrowserModel(url: url, fixture: false)
        connect(tab)
        tabs.append(tab)
        selectedID = tab.id
        tab.activate()
        showingTabs = false
        save()
        return tab
    }

    func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        if selectedID != id { selected.captureSnapshot() }
        selectedID = id
        selected.revealControls()
        selected.activate()
        showingTabs = false
        save()
    }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let tab = tabs[index]
        // Keep the session valid even when its final tab is closed.
        if tabs.count == 1 {
            let replacement = BrowserModel(fixture: false)
            connect(replacement)
            tabs = [replacement]
            selectedID = replacement.id
            replacement.activate()
        } else {
            tabs.remove(at: index)
            if selectedID == id {
                selectedID = tabs[min(index, tabs.count - 1)].id
                selected.activate()
            }
        }
        tab.close()
        save()
    }

    func showTabs() {
        selected.revealControls()
        selected.captureSnapshot()
        showingTabs = true
    }

    func save() {
        let archive = TabArchive(tabs: tabs.map {
            TabRecord(id: $0.id, address: $0.restorationURL?.absoluteString, fixture: $0.isFixture)
        }, selectedID: selectedID)
        guard let data = try? JSONEncoder().encode(archive), data != storage.data(forKey: archiveKey) else { return }
        storage.set(data, forKey: archiveKey)
    }
}
