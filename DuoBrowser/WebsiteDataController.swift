import Combine
import Foundation
import WebKit

struct BrowsingDataSelection {
    var history = false
    var siteData = false
    var cache = false
    var isEmpty: Bool { !history && !siteData && !cache }
    static let cacheTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]
    static let siteTypes: Set<String> = [WKWebsiteDataTypeCookies, WKWebsiteDataTypeSessionStorage,
        WKWebsiteDataTypeLocalStorage, WKWebsiteDataTypeIndexedDBDatabases, WKWebsiteDataTypeWebSQLDatabases,
        WKWebsiteDataTypeServiceWorkerRegistrations, WKWebsiteDataTypeFileSystem, WKWebsiteDataTypeMediaKeys,
        WKWebsiteDataTypeHashSalt]
    static var managedTypes: Set<String> { cacheTypes.union(siteTypes) }
    var types: Set<String> { (siteData ? Self.siteTypes : []).union(cache ? Self.cacheTypes : []) }
}

@MainActor
protocol WebsiteDataAccess {
    func records() async throws -> [WKWebsiteDataRecord]
    func remove(types: Set<String>, records: [WKWebsiteDataRecord]?) async throws
}

@MainActor
struct WebKitWebsiteDataAccess: WebsiteDataAccess {
    let store: WKWebsiteDataStore
    func records() async throws -> [WKWebsiteDataRecord] {
        await store.dataRecords(ofTypes: BrowsingDataSelection.managedTypes)
    }
    func remove(types: Set<String>, records: [WKWebsiteDataRecord]?) async throws {
        guard !types.isEmpty else { return }
        if let records { await store.removeData(ofTypes: types, for: records) }
        else { await store.removeData(ofTypes: types, modifiedSince: .distantPast) }
    }
}

/// Bound to the owning session's normal store. Row handles carry actual WebKit records,
/// not URL/string guesses about public-suffix or subdomain ownership.
@MainActor
final class WebsiteDataController: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let record: WKWebsiteDataRecord
        var name: String { record.displayName }
    }
    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isBusy = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var isRemoving = false
    @Published private(set) var message: String?
    private let store: any WebsiteDataAccess
    private var generation = UUID()
    init(store: any WebsiteDataAccess) { self.store = store }

    func cancelRefresh() { guard !isRemoving else { return }; generation = UUID(); entries = []; hasLoaded = false; isBusy = false }

    func reload() async {
        guard !isBusy else { return }
        let request = UUID(); generation = request
        isBusy = true; hasLoaded = false; message = nil
        defer { if generation == request { isBusy = false } }
        do {
            let records = try await store.records()
            guard generation == request, !Task.isCancelled else { return }
            hasLoaded = true
            entries = records.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }.map(Entry.init)
        } catch {
            guard generation == request else { return }
            message = "Website data couldn’t be loaded. Try again."
        }
        if generation == request { isBusy = false }
    }

    @discardableResult
    func removeEntry(_ id: UUID) async -> Bool {
        guard !isBusy else { return false }
        guard let entry = entries.first(where: { $0.id == id }) else {
            message = "The website list changed. Select the website again."; return false
        }
        return await remove(types: BrowsingDataSelection.managedTypes, records: [entry.record])
    }

    @discardableResult
    func clear(_ selection: BrowsingDataSelection) async -> Bool {
        guard !isBusy else { return false }
        return await remove(types: selection.types, records: nil)
    }

    private func remove(types: Set<String>, records: [WKWebsiteDataRecord]?) async -> Bool {
        guard !types.isEmpty else { message = nil; return true }
        let request = UUID(); generation = request
        isBusy = true; isRemoving = true; message = nil
        defer { isRemoving = false }
        do {
            try await store.remove(types: types, records: records)
            guard generation == request else { return false }
            entries = []; hasLoaded = false // Every old confirmation handle is now invalid.
            isBusy = false
            await reload()
            if message == nil { message = "Website data removed. Open pages can save new data; reload them when you’re ready." }
            return true
        } catch {
            guard generation == request else { return false }
            isBusy = false
            message = "Website data couldn’t be removed. Try again."
            return false
        }
    }
}
