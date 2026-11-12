import BrowserKit
import Combine
import UIKit

@MainActor
protocol BrowserTransferTransport {
    func request(scene: UIWindowScene) async throws -> Bool
    func items(token: UUID) -> AsyncThrowingStream<BEBrowserData, Error>
}

@MainActor
private struct SystemBrowserTransfer: BrowserTransferTransport {
    func request(scene: UIWindowScene) async throws -> Bool {
        let options = try await BEBrowserDataImportManager(scene: scene)
            .requestImport(for: BEImportMetadata(supportForImportFromFiles: false))
        return options.importFromFiles
    }
    func items(token: UUID) -> AsyncThrowingStream<BEBrowserData, Error> {
        BEBrowserDataImportManager().importBrowserData(token: token)
    }
}

@MainActor
final class BrowserSetupModel: ObservableObject {
    enum Step: Int, CaseIterable { case welcome, transfer, defaultBrowser, tour }
    enum TransferState: Equatable { case idle, requesting, receiving, review, saved, failed }
    @Published var step: Step { didSet { storage.set(step.rawValue, forKey: "setup.step") } }
    @Published var choices: ImportChoices { didSet { storage.set(try? JSONEncoder().encode(choices), forKey: "setup.choices") } }
    @Published var favoriteFolder = ""
    @Published private(set) var state: TransferState = .idle
    @Published private(set) var message: String?
    @Published private(set) var received = 0
    @Published private(set) var batch: BrowserImportBatch?
    @Published private(set) var folders: [(id: String, title: String)] = []
    @Published var settingsMessage: String?
    private let transport: any BrowserTransferTransport
    private let storage: UserDefaults
    private var task: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var generation = UUID()
    private var tokens = Set<UUID>()
    private var acceptingReturn = true
    let transferEnabled: Bool
    var completed: Bool { storage.bool(forKey: "setup.completed") }
    var busy: Bool { state == .requesting || state == .receiving }

    init(storage: UserDefaults, transferEnabled: Bool = Bundle.main.object(forInfoDictionaryKey: "DuoBrowserDirectTransferEnabled") as? String == "YES", transport: (any BrowserTransferTransport)? = nil) {
        self.storage = storage
        self.transport = transport ?? SystemBrowserTransfer()
        self.transferEnabled = transferEnabled
        step = Step(rawValue: storage.integer(forKey: "setup.step")) ?? .welcome
        choices = storage.data(forKey: "setup.choices").flatMap { try? JSONDecoder().decode(ImportChoices.self, from: $0) } ?? ImportChoices()
        if storage.bool(forKey: "setup.transferPending") {
            step = .transfer
            message = "The previous transfer did not finish. Try again when you’re ready. Nothing was added."
        }
    }

    func reopen() { if completed { step = .welcome }; acceptingReturn = true }
    func finish() {
        cancel()
        storage.set(true, forKey: "setup.completed")
        step = .welcome
    }
    func next() { if let next = Step(rawValue: step.rawValue + 1) { step = next } }
    func back() { if let previous = Step(rawValue: step.rawValue - 1) { step = previous } }

    func cancel() {
        generation = UUID()
        acceptingReturn = false
        task?.cancel(); task = nil
        timeout?.cancel(); timeout = nil
        storage.set(false, forKey: "setup.transferPending")
        batch = nil; folders = []; favoriteFolder = ""; received = 0
        state = .idle; message = nil
    }

    func request(scene: UIWindowScene?) {
        guard transferEnabled, !busy, choices.hasSelection, let scene else { return }
        cancel()
        acceptingReturn = true
        let current = generation
        state = .requesting
        storage.set(true, forKey: "setup.transferPending")
        startTimeout(current)
        task = Task { [weak self] in
            do {
                guard let transport = self?.transport else { return }
                let importFromFiles = try await transport.request(scene: scene)
                guard let self, self.generation == current, !Task.isCancelled else { return }
                if importFromFiles {
                    self.fail("Direct transfer was not available. Nothing was added. You can try again or continue setup.")
                }
                // For direct transfer, iOS returns through NSUserActivity, including after a cold launch.
            } catch {
                guard let self, self.generation == current, !Task.isCancelled else { return }
                self.fail("The transfer did not start or was canceled. Nothing was added. You can try again or continue setup.")
            }
        }
    }

    @discardableResult
    func receive(_ activity: NSUserActivity, isPrivate: Bool) -> Bool {
        guard !isPrivate, acceptingReturn, transferEnabled,
              activity.activityType == BEBrowserDataImportManager.userActivityType,
              let token = activity.userInfo?[BEBrowserDataImportManager.importTokenUserInfoKey] as? UUID,
              !tokens.contains(token), state != .receiving, state != .review else { return false }
        // Do not evict replay guards during a live session.
        guard tokens.count < 32 else { fail("Restart DuoBrowser before starting another transfer."); return false }
        tokens.insert(token)
        cancel()
        acceptingReturn = true
        let current = generation
        state = .receiving; step = .transfer
        storage.set(true, forKey: "setup.transferPending")
        startTimeout(current)
        task = Task { [weak self] in
            do {
                guard let transport = self?.transport else { return }
                let stream = transport.items(token: token)
                var incoming = BrowserImportBatch()
                for try await item in stream {
                    guard let self, self.generation == current, !Task.isCancelled else { return }
                    try Self.append(item, to: &incoming)
                    self.received = incoming.received
                    if incoming.received.isMultiple(of: 200) { await Task.yield() }
                }
                guard let self, self.generation == current, !Task.isCancelled else { return }
                try self.review(incoming)
            } catch {
                guard let self, self.generation == current, !Task.isCancelled else { return }
                self.fail((error as? BrowserImportError)?.localizedDescription ?? "The transfer was interrupted. Nothing was added. Try again when you’re ready.")
            }
        }
        return true
    }

    static func append(_ item: BEBrowserData, to batch: inout BrowserImportBatch) throws {
        switch item {
        case let item as BEBrowserDataBookmark:
            try batch.addBookmark(ImportBookmark(identifier: item.identifier, parent: item.parentIdentifier,
                title: item.title, address: item.url?.absoluteString, isFolder: item.isFolder))
        case let item as BEBrowserDataHistoryVisit:
            try batch.addPage(address: item.url.absoluteString, title: item.title ?? "", date: item.dateOfLastVisit, isHistory: true)
        case let item as BEBrowserDataReadingListItem:
            try batch.addPage(address: item.url.absoluteString, title: item.title, date: item.dateOfLastVisit ?? Date(timeIntervalSince1970: 0), isHistory: false)
        default: try batch.skipUnsupported()
        }
    }

    private func review(_ incoming: BrowserImportBatch) throws {
        guard incoming.bookmarks.values.filter({ $0.isFolder }).count <= LibraryLimits.folders else { throw BrowserImportError.tooLarge }
        let options = try incoming.folderOptions()
        timeout?.cancel(); timeout = nil
        batch = incoming; folders = options; favoriteFolder = ""
        storage.set(false, forKey: "setup.transferPending")
        state = .review
        message = "Nothing is saved until you tap Add Selected Data."
    }

    func save(into session: BrowserSession) {
        guard state == .review, let batch, choices.hasSelection, !session.privateMode else { return }
        do {
            let plan = try batch.plan(choices: choices, favoriteFolder: favoriteFolder.isEmpty ? nil : favoriteFolder,
                existingBookmarks: session.bookmarks, existingFolders: session.bookmarkFolders,
                existingHistory: session.history, existingReadingList: session.readingList)
            try session.applyImport(plan)
            self.batch = nil; folders = []; favoriteFolder = ""
            state = .saved; message = plan.summary
        } catch { message = error.localizedDescription }
    }

    func openDefaultSettings() {
        guard transferEnabled, let url = URL(string: UIApplication.openDefaultApplicationsSettingsURLString) else { return }
        UIApplication.shared.open(url) { [weak self] opened in
            Task { @MainActor in
                self?.settingsMessage = opened ? "Choose Browser App, then DuoBrowser. Come back here to finish setup." : "Settings could not open. You can choose your default browser later in iOS Settings."
            }
        }
    }

    private func fail(_ text: String) {
        cancel(); state = .failed; message = text
    }
    private func startTimeout(_ current: UUID) {
        timeout = Task { [weak self] in
            try? await Task.sleep(for: .seconds(120))
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.fail("The transfer did not finish in time. Nothing was added. Try again or continue setup.")
        }
    }

    #if DEBUG
    func reviewForTesting(_ batch: BrowserImportBatch) throws { try review(batch) }
    #endif
}
