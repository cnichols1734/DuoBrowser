import Combine
import CryptoKit
import WebKit

@MainActor
enum ContentBlocking {
    static let changed = Notification.Name("DuoBrowser.ContentBlocking.changed")
    #if DEBUG
    private static var testRules: [String]?
    private static var testCompilation: Task<[WKContentRuleList], Never>?
    static func useTestRules(_ json: String?) {
        useTestRuleChunks(json.map { [$0] })
    }
    static func useTestRuleChunks(_ sources: [String]?) {
        testRules = sources; testCompilation = nil
        NotificationCenter.default.post(name: changed, object: nil)
    }
    #endif
    static func rules() async -> [WKContentRuleList] {
        #if DEBUG
        if let sources = testRules {
            if let testCompilation { return await testCompilation.value }
            let task = Task<[WKContentRuleList], Never> { @MainActor in
                var lists: [WKContentRuleList] = []
                for source in sources {
                    guard let rule = try? await WKContentRuleListStore.default().compileContentRuleList(
                        forIdentifier: "DuoBrowser.Synthetic." + FilterCatalog.digest(Data(source.utf8)), encodedContentRuleList: source) else { return [] }
                    lists.append(rule)
                }
                return lists
            }
            testCompilation = task
            return await task.value
        }
        #endif
        return await FilterCatalog.shared.rules()
    }
}

/// Global filter metadata only. Never receives visited URLs, page contents, or request logs.
@MainActor
final class FilterCatalog: ObservableObject {
    static let shared = FilterCatalog()
    struct Source: Codable, Sendable {
        let id: String
        let text: String
    }
    struct Snapshot: Codable, Sendable {
        let date: Date
        let sources: [Source]
    }
    struct Definition: Sendable {
        let id: String
        let title: String
        let url: URL
    }
    nonisolated static let definitions = [
        Definition(id: "easylist", title: "EasyList", url: URL(string: "https://easylist.to/easylist/easylist.txt")!),
        Definition(id: "easyprivacy", title: "EasyPrivacy", url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!),
        Definition(id: "cookies", title: "EasyList Cookie List", url: URL(string: "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt")!)
    ]
    @Published private(set) var updatedAt: Date?
    @Published private(set) var updating = false
    @Published private(set) var message: String?
    @Published private(set) var usingFallback = false
    @Published private(set) var ruleCount = 0
    @Published private(set) var skippedCount = 0
    @Published var automaticUpdates: Bool {
        didSet { defaults.set(automaticUpdates, forKey: "browser.filterAutomaticUpdates") }
    }
    @Published var hideCookieNotices: Bool {
        didSet {
            defaults.set(hideCookieNotices, forKey: "browser.hideCookieNotices")
            NotificationCenter.default.post(name: ContentBlocking.changed, object: nil)
        }
    }
    private let defaults: UserDefaults
    private let cacheURL: URL
    private var active: [String: [WKContentRuleList]] = [:]
    private var loading: Task<Void, Never>?
    private var attemptedAt: Date?
    private var snapshot: Snapshot?
    private init() {
        defaults = .standard
        automaticUpdates = defaults.object(forKey: "browser.filterAutomaticUpdates") as? Bool ?? true
        hideCookieNotices = defaults.bool(forKey: "browser.hideCookieNotices")
        cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ContentFilters", isDirectory: true).appendingPathComponent("sources.json")
    }
    nonisolated static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    func rules() async -> [WKContentRuleList] {
        if active.isEmpty {
            if loading == nil { loading = Task { await self.loadInitial() } }
            await loading?.value
        }
        return active[hideCookieNotices ? "withCookies" : "standard"] ?? []
    }
    private func loadInitial() async {
        if let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16_000_000,
           let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode(Snapshot.self, from: data),
           Self.valid(saved), await install(saved) { return }
        let sources = Self.definitions.compactMap { definition -> Source? in
            guard let url = Bundle.main.url(forResource: definition.id, withExtension: "txt", subdirectory: "FilterLists"),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            return Source(id: definition.id, text: text)
        }
        // The bundled provenance receipt is generated alongside the source lists.
        let date = Bundle.main.url(forResource: "metadata", withExtension: "json", subdirectory: "FilterLists")
            .flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(BundleDate.self, from: $0) }?.date ?? Date(timeIntervalSince1970: 0)
        let bundled = Snapshot(date: date, sources: sources)
        if Self.valid(bundled), await install(bundled) { return }
        // Preserve a bounded last-resort baseline if the maintained bundle cannot compile.
        if let url = Bundle.main.url(forResource: "BlockingRules", withExtension: "json"),
           let json = try? String(contentsOf: url, encoding: .utf8),
           let rule = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "DuoBrowser.Fallback.v1", encodedContentRuleList: json) {
            active = ["standard": [rule], "withCookies": [rule]]
            usingFallback = true
            message = "Basic fallback is active. Update filters to restore full protection."
        } else { message = "Protection couldn’t start. Try updating filters." }
    }
    private struct BundleDate: Decodable { let date: Date }
    nonisolated static func valid(_ snapshot: Snapshot) -> Bool {
        Set(snapshot.sources.map(\.id)) == Set(definitions.map(\.id)) && snapshot.sources.count == definitions.count &&
        snapshot.sources.allSatisfy { $0.text.utf8.count <= 5_000_000 && $0.text.hasPrefix("[Adblock Plus") } &&
        snapshot.date <= Date().addingTimeInterval(86_400)
    }
    #if DEBUG
    func rejectInvalidUpdateForTesting() async -> Bool {
        let before = active.values.flatMap { $0.map(\.identifier) }.sorted()
        let invalid = Snapshot(date: Date(), sources: Self.definitions.map { Source(id: $0.id, text: "<html>Unavailable</html>") })
        let installed = await install(invalid, persist: true)
        return !installed && before == active.values.flatMap { $0.map(\.identifier) }.sorted()
    }
    #endif
    private func install(_ next: Snapshot, persist: Bool = false) async -> Bool {
        guard Self.valid(next) else { return false }
        do {
            var compiled: [String: [WKContentRuleList]] = [:]
            var count = 0, skipped = 0
            // Convert enabled sources together so all network AND selector exemptions
            // override matching rules in every source/chunk. Cookie exceptions are opt-in too.
            for mode in ["standard", "withCookies"] {
                let sources = next.sources.filter { mode == "withCookies" || $0.id != "cookies" }
                let converted = try await Task.detached(priority: .utility) {
                    for source in sources {
                        let result = try FilterListConverter.convert(source.text)
                        let minimum = source.id == "easylist" ? 5_000 : source.id == "easyprivacy" ? 1_000 : 100
                        guard result.count >= minimum else { throw FilterListConverter.Failure.invalidList }
                    }
                    let result = try FilterListConverter.convert(sources.map(\.text).joined(separator: "\n"), combined: true)
                    return (try result.chunks(), result.count, result.skipped)
                }.value
                guard !converted.0.isEmpty, converted.0.count <= 20 else { throw FilterListConverter.Failure.tooLarge }
                var lists: [WKContentRuleList] = []
                for data in converted.0 {
                    let identifier = "DuoBrowser.Filters.v2." + Self.digest(data)
                    let store = WKContentRuleListStore.default()!
                    if let cached = try? await store.contentRuleList(forIdentifier: identifier) { lists.append(cached) }
                    else {
                        guard let list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: String(decoding: data, as: UTF8.self)) else {
                            throw FilterListConverter.Failure.invalidList
                        }
                        lists.append(list)
                    }
                }
                compiled[mode] = lists
                if mode == "withCookies" { count = converted.1; skipped = converted.2 }
            }
            if persist {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(next).write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                var directory = cacheURL.deletingLastPathComponent()
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try? directory.setResourceValues(values)
            }
            usingFallback = false
            active = compiled; snapshot = next; updatedAt = next.date; ruleCount = count; skippedCount = skipped
            message = nil
            NotificationCenter.default.post(name: ContentBlocking.changed, object: nil)
            await removeObsoleteCompiledLists(keeping: Set(compiled.values.flatMap { $0.map(\.identifier) }))
            return true
        } catch {
            await removeObsoleteCompiledLists(keeping: Set(active.values.flatMap { $0.map(\.identifier) }))
            return false
        }
    }
    private func removeObsoleteCompiledLists(keeping identifiers: Set<String>) async {
        let store = WKContentRuleListStore.default()!
        let available: [String] = await withCheckedContinuation { continuation in
            store.getAvailableContentRuleListIdentifiers { continuation.resume(returning: $0 ?? []) }
        }
        for identifier in available where identifier.hasPrefix("DuoBrowser.Filters.") && !identifiers.contains(identifier) {
            try? await store.removeContentRuleList(forIdentifier: identifier)
        }
    }
    func refreshIfNeeded() async {
        guard automaticUpdates else { return }
        _ = await rules()
        guard updatedAt.map({ Date().timeIntervalSince($0) >= 4 * 86_400 }) ?? true,
              attemptedAt.map({ Date().timeIntervalSince($0) >= 3_600 }) ?? true else { return }
        await update()
    }
    func update() async {
        guard !updating else { return }
        updating = true; attemptedAt = Date(); message = nil
        defer { updating = false }
        _ = await rules()
        do {
            let next = try await Task.detached(priority: .utility) { try await Self.downloadSources() }.value
            guard Self.valid(next), await install(next, persist: true) else { throw FilterListConverter.Failure.invalidList }
            message = "Filters are up to date. Reload a page when you’re ready to apply visual changes."
        } catch {
            message = active.isEmpty ? "Couldn’t update filters. Protection is unavailable; try again later."
                : "Couldn’t update filters. Your existing protection is still active. Try again later."
        }
    }
    nonisolated private static func downloadSources() async throws -> Snapshot {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.urlCache = nil
            configuration.timeoutIntervalForResource = 120
            let session = URLSession(configuration: configuration, delegate: FilterDownloadPolicy(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var sources: [Source] = []
            for definition in Self.definitions {
                var request = URLRequest(url: definition.url)
                request.timeoutInterval = 40
                request.httpShouldHandleCookies = false
                request.cachePolicy = .reloadIgnoringLocalCacheData
                let (bytes, response) = try await session.bytes(for: request)
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      response.url == definition.url, response.expectedContentLength <= 5_000_000 else { throw FilterListConverter.Failure.invalidList }
                var data = Data()
                for try await byte in bytes {
                    guard data.count < 5_000_000 else { throw FilterListConverter.Failure.tooLarge }
                    data.append(byte)
                }
                guard let text = String(data: data, encoding: .utf8) else { throw FilterListConverter.Failure.invalidList }
                sources.append(Source(id: definition.id, text: text))
            }
            return Snapshot(date: Date(), sources: sources)
    }

}

private final class FilterDownloadPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
