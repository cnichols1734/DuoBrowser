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
    private static let converterVersion = 3
    private static let compiledPrefix = "DuoBrowser.Filters.v3."
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
    private var baselineLoading: Task<Void, Never>?
    #if DEBUG
    private var testPreparationStarted: ContinuousClock.Instant?
    private var testPreparationStages: [String] = []
    var testHoldInitialPreparation = false
    var testDownloadSources: (@MainActor () async throws -> Snapshot)?
    static func startupTestCatalog() -> FilterCatalog {
        let catalog = FilterCatalog(); catalog.testHoldInitialPreparation = true; return catalog
    }
    #endif
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
        if loading == nil {
            #if DEBUG
            testPreparationStarted = .now
            testPreparationStages = []
            #endif
            preparing = true
            loading = Task { await self.loadInitial() }
        }
        if active.isEmpty {
            if baselineLoading == nil { baselineLoading = Task { await self.prepareBaseline() } }
            // First navigation waits only for the small bundled baseline. Maintained conversion
            // continues independently, then updates existing pages without reloading them.
            await baselineLoading?.value
        }
        return active[hideCookieNotices ? "withCookies" : "standard"] ?? []
    }
    private func prepareBaseline() async {
        guard let url = Bundle.main.url(forResource: "BlockingRules", withExtension: "json"),
              let json = try? String(contentsOf: url, encoding: .utf8) else { return }
        let store = WKContentRuleListStore.default()!
        let identifier = "DuoBrowser.Fallback.v1"
        let cached = try? await store.contentRuleList(forIdentifier: identifier)
        let rule: WKContentRuleList?
        if let cached { rule = cached }
        else { rule = try? await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) }
        guard active.isEmpty, let rule else { return }
        active = ["standard": [rule], "withCookies": [rule]]
        usingFallback = true
        message = preparing ? "Basic protection is active while full protection is prepared." : "Basic fallback is active. Update filters to restore full protection."
        NotificationCenter.default.post(name: ContentBlocking.changed, object: nil)
    }
    private func loadInitial() async {
        #if DEBUG
        while testHoldInitialPreparation {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .milliseconds(25))
        }
        #endif
        notePreparation("reading cached source snapshot")
        if let size = try? cacheURL.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16_000_000,
           let data = try? Data(contentsOf: cacheURL), let saved = try? JSONDecoder().decode(Snapshot.self, from: data),
           Self.valid(saved), await install(saved) { return }
        notePreparation("reading bundled sources")
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
        await baselineLoading?.value
        if active.isEmpty { await prepareBaseline() }
        preparing = false
        notePreparation("maintained preparation failed; retained baseline")
        message = active.isEmpty ? "Protection couldn’t start. Try updating filters."
            : "Basic fallback is active. Update filters to restore full protection."
        NotificationCenter.default.post(name: ContentBlocking.changed, object: nil)
    }
    private struct BundleDate: Decodable { let date: Date }
    nonisolated static func valid(_ snapshot: Snapshot) -> Bool {
        Set(snapshot.sources.map(\.id)) == Set(definitions.map(\.id)) && snapshot.sources.count == definitions.count &&
        snapshot.sources.allSatisfy { $0.text.utf8.count <= 5_000_000 && $0.text.hasPrefix("[Adblock Plus") } &&
        snapshot.date.timeIntervalSince1970.isFinite && snapshot.date <= Date().addingTimeInterval(86_400)
    }
    #if DEBUG
    func preparationDiagnosticsForTesting() -> String {
        "preparing=\(preparing), fallback=\(usingFallback), count=\(ruleCount), message=\(message ?? "none"), elapsed=\(preparationElapsedForTesting()), stages=[\(testPreparationStages.joined(separator: "; "))]"
    }
    private func preparationElapsedForTesting() -> String {
        guard let started = testPreparationStarted else { return "not started" }
        let elapsed = started.duration(to: .now).components
        return String(format: "%.1fs", Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
    }
    func awaitMaintainedForTesting() async -> Bool {
        _ = await rules()
        let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(300))
        while preparing, clock.now < deadline, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !preparing && !usingFallback && !active.isEmpty
    }
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
    private func notePreparation(_ stage: String) {
        #if DEBUG
        if testPreparationStages.count == 64 { testPreparationStages.removeFirst() }
        testPreparationStages.append(preparationElapsedForTesting() + " " + stage)
        #endif
    }
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
        notePreparation("hashing public source set")
        let sourceSHA = await Task.detached(priority: .utility) { Self.sourceFingerprint(next.sources) }.value
        do {
            notePreparation("checking compiled manifest")
            var compiled = await readCompiled(sourceSHA: sourceSHA)
            if compiled != nil { notePreparation("reusing complete compiled manifest") }
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
                    notePreparation("converting " + mode)
                    let sources = next.sources.filter { mode == "withCookies" || $0.id != "cookies" }
                    let converted = try await Task.detached(priority: .utility) {
                        let result = try FilterListConverter.convert(sources.map(\.text).joined(separator: "\n"), combined: true)
                        return (try result.chunks(), result.count, result.skipped)
                    }.value
                    guard !converted.0.isEmpty, converted.0.count <= 20 else { throw FilterListConverter.Failure.tooLarge }
                    var lists: [WKContentRuleList] = []
                    for (index, data) in converted.0.enumerated() {
                        notePreparation("resolving \(mode) chunk \(index + 1)/\(converted.0.count)")
                        let identifier = Self.compiledPrefix + Self.digest(data)
                        let store = WKContentRuleListStore.default()!
                        if let cached = try? await store.contentRuleList(forIdentifier: identifier) { lists.append(cached) }
                        else {
                            notePreparation("compiling \(mode) chunk \(index + 1)/\(converted.0.count)")
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
            usingFallback = false; preparing = false
            notePreparation("activating maintained rules")
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
            let failure = error as NSError
            notePreparation("installation rejected: \(failure.domain) code \(failure.code)")
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
    func refreshIfNeeded(isAllowed: @MainActor () -> Bool) async {
        guard automaticUpdates, isAllowed() else { return }
        _ = await rules()
        await loading?.value
        guard automaticUpdates, isAllowed(), updatedAt.map({ Date().timeIntervalSince($0) >= 4 * 86_400 }) ?? true,
              attemptedAt.map({ Date().timeIntervalSince($0) >= 3_600 }) ?? true else { return }
        await update(isAllowed: { self.automaticUpdates && isAllowed() })
    }
    func update(isAllowed: @MainActor () -> Bool = { true }) async {
        guard !updating, isAllowed() else { return }
        updating = true; message = nil
        defer { updating = false }
        _ = await rules()
        await loading?.value
        // Preparation can outlive the normal foreground session that requested an automatic refresh.
        guard isAllowed() else { return }
        attemptedAt = Date()
        do {
            let next: Snapshot
            #if DEBUG
            if let testDownloadSources { next = try await testDownloadSources() }
            else { next = try await Task.detached(priority: .utility) { try await Self.downloadSources() }.value }
            #else
            next = try await Task.detached(priority: .utility) { try await Self.downloadSources() }.value
            #endif
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
