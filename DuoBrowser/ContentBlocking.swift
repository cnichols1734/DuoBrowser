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
    @Published private(set) var preparing = false
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
    // Bump when converter semantics or chunking changes; cached IDs alone do not identify source semantics.
    private static let converterVersion = 2
    private static let compiledPrefix = "DuoBrowser.Filters.v2."
    private static let manifestByteLimit = 64_000
    private struct CompiledManifest: Codable {
        struct Variant: Codable {
            var identifiers: [String]
            var count: Int
            var skipped: Int
        }
        var converterVersion: Int
        var sourceSHA: String
        var date: Date
        var variants: [String: Variant]
    }
    private struct CompiledSnapshot {
        var lists: [String: [WKContentRuleList]]
        var manifest: CompiledManifest
    }
    private var manifestURL: URL { cacheURL.deletingLastPathComponent().appendingPathComponent("compiled.json") }
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
        preparing = true
        defer { preparing = false }
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
        snapshot.date.timeIntervalSince1970.isFinite && snapshot.date <= Date().addingTimeInterval(86_400)
    }
    #if DEBUG
    func rejectInvalidUpdateForTesting() async -> Bool {
        let before = active.values.flatMap { $0.map(\.identifier) }.sorted()
        let invalid = Snapshot(date: Date(), sources: Self.definitions.map { Source(id: $0.id, text: "<html>Unavailable</html>") })
        let installed = await install(invalid, persist: true)
        return !installed && before == active.values.flatMap { $0.map(\.identifier) }.sorted()
    }
    func compiledCacheChecksForTesting() async -> [(String, Bool)] {
        guard let snapshot, let data = try? Data(contentsOf: manifestURL) else {
            return [("compiled filter manifest is available after installation", false)]
        }
        let fingerprint = Self.sourceFingerprint(snapshot.sources)
        guard let manifest = Self.decodeManifest(data, sourceSHA: fingerprint) else {
            return [("compiled filter manifest validates against installed sources", false)]
        }
        let before = active.values.flatMap { $0.map(\.identifier) }.sorted()
        let restored = await resolveCompiled(manifest, sourceSHA: fingerprint)
        var checks = [("compiled filter fast path restores both complete variants",
                       restored?.lists.values.flatMap { $0.map(\.identifier) }.sorted() == before)]
        var changedSources = snapshot.sources
        changedSources[0] = Source(id: changedSources[0].id, text: changedSources[0].text + "\n! Changed fixture")
        checks.append(("changed source content invalidates compiled filter metadata",
                       !Self.valid(manifest, sourceSHA: Self.sourceFingerprint(changedSources))))
        var changedVersion = manifest
        changedVersion.converterVersion += 1
        checks.append(("converter version change invalidates compiled filter metadata", !Self.valid(changedVersion, sourceSHA: fingerprint)))
        checks.append(("malformed and oversized compiled filter metadata is rejected",
                       Self.decodeManifest(Data("{".utf8), sourceSHA: fingerprint) == nil &&
                       Self.decodeManifest(data + Data(repeating: 32, count: Self.manifestByteLimit), sourceSHA: fingerprint) == nil))
        var missingMode = manifest
        missingMode.variants.removeValue(forKey: "standard")
        checks.append(("compiled filter metadata requires both complete modes", !Self.valid(missingMode, sourceSHA: fingerprint)))
        var missingRule = manifest
        missingRule.variants["withCookies"]!.identifiers[0] = Self.compiledPrefix + String(repeating: "0", count: 64)
        let rejected = await resolveCompiled(missingRule, sourceSHA: fingerprint) == nil
        checks.append(("missing compiled rule rejects the whole cache without replacing active protection",
                       rejected && before == active.values.flatMap { $0.map(\.identifier) }.sorted()))
        return checks
    }
    #endif
    nonisolated private static func sourceFingerprint(_ sources: [Source]) -> String {
        // Preserve order because conversion runs over concatenated source text. No browsing data is involved.
        digest(Data(sources.map { $0.id + ":" + digest(Data($0.text.utf8)) }.joined(separator: "\n").utf8))
    }
    private static func valid(_ manifest: CompiledManifest, sourceSHA: String) -> Bool {
        guard manifest.converterVersion == converterVersion, manifest.sourceSHA == sourceSHA,
              manifest.date.timeIntervalSince1970.isFinite, manifest.date <= Date().addingTimeInterval(86_400),
              Set(manifest.variants.keys) == Set(["standard", "withCookies"]) else { return false }
        return manifest.variants.values.allSatisfy { variant in
            (1...20).contains(variant.identifiers.count) && Set(variant.identifiers).count == variant.identifiers.count &&
            (1...900_000).contains(variant.count) && (0...450_000).contains(variant.skipped) &&
            variant.identifiers.allSatisfy { identifier in
                guard identifier.hasPrefix(compiledPrefix) else { return false }
                let suffix = identifier.dropFirst(compiledPrefix.count)
                return suffix.utf8.count == 64 && suffix.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            }
        }
    }
    private static func decodeManifest(_ data: Data, sourceSHA: String) -> CompiledManifest? {
        guard data.count <= manifestByteLimit,
              let manifest = try? JSONDecoder().decode(CompiledManifest.self, from: data), valid(manifest, sourceSHA: sourceSHA) else { return nil }
        return manifest
    }
    private func resolveCompiled(_ manifest: CompiledManifest, sourceSHA: String) async -> CompiledSnapshot? {
        guard Self.valid(manifest, sourceSHA: sourceSHA) else { return nil }
        let store = WKContentRuleListStore.default()!
        var compiled: [String: [WKContentRuleList]] = [:]
        // Do not partially activate one mode when another mode's cache has been evicted.
        for mode in ["standard", "withCookies"] {
            var lists: [WKContentRuleList] = []
            for identifier in manifest.variants[mode]!.identifiers {
                guard let list = try? await store.contentRuleList(forIdentifier: identifier), list.identifier == identifier else { return nil }
                lists.append(list)
            }
            compiled[mode] = lists
        }
        return CompiledSnapshot(lists: compiled, manifest: manifest)
    }
    private func readCompiled(sourceSHA: String) async -> CompiledSnapshot? {
        guard let size = try? manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= Self.manifestByteLimit,
              let data = try? Data(contentsOf: manifestURL), let manifest = Self.decodeManifest(data, sourceSHA: sourceSHA) else { return nil }
        return await resolveCompiled(manifest, sourceSHA: sourceSHA)
    }
    private func writeCompiled(_ manifest: CompiledManifest) {
        // This is a disposable acceleration cache, never the update's commit boundary.
        do {
            let data = try JSONEncoder().encode(manifest)
            guard data.count <= Self.manifestByteLimit else { return }
            try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: manifestURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var directory = manifestURL.deletingLastPathComponent()
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
        } catch { /* Keep the already compiled protection even if this optional cache cannot save. */ }
    }
    private func install(_ next: Snapshot, persist: Bool = false) async -> Bool {
        guard Self.valid(next) else { return false }
        let sourceSHA = await Task.detached(priority: .utility) { Self.sourceFingerprint(next.sources) }.value
        do {
            var compiled = await readCompiled(sourceSHA: sourceSHA)
            if compiled == nil {
                var listsByMode: [String: [WKContentRuleList]] = [:]
                var variants: [String: CompiledManifest.Variant] = [:]
                try await Task.detached(priority: .utility) {
                    for source in next.sources {
                        let result = try FilterListConverter.convert(source.text)
                        let minimum = source.id == "easylist" ? 5_000 : source.id == "easyprivacy" ? 1_000 : 100
                        guard result.count >= minimum else { throw FilterListConverter.Failure.invalidList }
                    }
                }.value
                // Convert all enabled text together so exceptions apply across sources and chunks.
                // Cookie exemptions remain restricted to the opt-in variant.
                for mode in ["standard", "withCookies"] {
                    let sources = next.sources.filter { mode == "withCookies" || $0.id != "cookies" }
                    let converted = try await Task.detached(priority: .utility) {
                        let result = try FilterListConverter.convert(sources.map(\.text).joined(separator: "\n"), combined: true)
                        return (try result.chunks(), result.count, result.skipped)
                    }.value
                    guard !converted.0.isEmpty, converted.0.count <= 20 else { throw FilterListConverter.Failure.tooLarge }
                    var lists: [WKContentRuleList] = []
                    for data in converted.0 {
                        let identifier = Self.compiledPrefix + Self.digest(data)
                        let store = WKContentRuleListStore.default()!
                        if let cached = try? await store.contentRuleList(forIdentifier: identifier) { lists.append(cached) }
                        else {
                            guard let list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: String(decoding: data, as: UTF8.self)) else {
                                throw FilterListConverter.Failure.invalidList
                            }
                            lists.append(list)
                        }
                    }
                    listsByMode[mode] = lists
                    variants[mode] = .init(identifiers: lists.map(\.identifier), count: converted.1, skipped: converted.2)
                }
                compiled = CompiledSnapshot(lists: listsByMode, manifest: CompiledManifest(converterVersion: Self.converterVersion,
                    sourceSHA: sourceSHA, date: next.date, variants: variants))
            }
            guard var compiled else { throw FilterListConverter.Failure.invalidList }
            if persist {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try JSONEncoder().encode(next).write(to: cacheURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                var directory = cacheURL.deletingLastPathComponent()
                var values = URLResourceValues(); values.isExcludedFromBackup = true
                try? directory.setResourceValues(values)
            }
            usingFallback = false
            active = compiled.lists; snapshot = next; updatedAt = next.date
            ruleCount = compiled.manifest.variants["withCookies"]!.count
            skippedCount = compiled.manifest.variants["withCookies"]!.skipped
            message = nil
            compiled.manifest.date = next.date
            writeCompiled(compiled.manifest)
            NotificationCenter.default.post(name: ContentBlocking.changed, object: nil)
            await removeObsoleteCompiledLists(keeping: Set(compiled.lists.values.flatMap { $0.map(\.identifier) }))
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
