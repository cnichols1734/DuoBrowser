#if DEBUG
import SwiftUI
import WebKit

extension NativeCheckRunner {
    func premiumRecoveryChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PremiumRecovery-" + UUID().uuidString)
        let suite = "DuoBrowser.PremiumRecovery." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let session = BrowserSession(storage: defaults, archiveStore: BrowserArchiveStore(directory: directory), dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let source = session.selected
        try await load(source, "upgrades?recovery=1")
        let webView = source.webView
        _ = try await js(source, "document.querySelector('#kept').value='Synthetic recovery draft'")
        let target = URL(string: "http://127.0.0.1:8765/upgrades?retry=1")!
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet,
                            userInfo: [NSURLErrorFailingURLErrorKey: target])
        source.webView(webView, didFailProvisionalNavigation: nil, withError: error)
        let first = source.loadFailure!
        try check(first.kind == .offline && !source.failureCoversPage, "offline recovery keeps an already committed page visible")
        try check(try await js(source, "document.querySelector('#kept').value") as? String == "Synthetic recovery draft",
                  "presenting recovery preserves the existing unsent form")
        let recovery = UIHostingController(rootView: BrowserRecoveryView(session: session, browser: source, fillsPage: false, editAddress: {}))
        host.addChild(recovery)
        recovery.view.frame = host.view.bounds
        host.view.addSubview(recovery.view)
        recovery.didMove(toParent: host)
        recovery.view.layoutIfNeeded()
        try check(source.loadedWebView === webView && source.loadFailure?.id == first.id, "rendering recovery never replaces the live WebKit view")
        recovery.willMove(toParent: nil)
        recovery.view.removeFromSuperview()
        recovery.removeFromParent()
        try check(try await js(source, "document.querySelector('#kept').value") as? String == "Synthetic recovery draft",
                  "dismissing recovery UI performs no automatic navigation")
        source.errorMessage = nil
        try check(source.loadFailure == nil && !source.retryLoadFailure(first), "dismissed failure actions cannot navigate")
        source.webView(webView, didFailProvisionalNavigation: nil, withError: error)
        let retry = source.loadFailure!
        try check(source.retryLoadFailure(retry), "explicit recovery starts a safe GET to the exact failing URL")
        try await wait { source.restorationURL == target && !source.isLoading && source.loadFailure == nil }
        try check(source.loadedWebView === webView && !source.retryLoadFailure(retry), "recovery retains the view and rejects a duplicate retry")
        source.webView(webView, didFailProvisionalNavigation: nil, withError: error)
        let stale = source.loadFailure!
        source.documentGeneration = UUID()
        try check(!source.retryLoadFailure(stale), "a replacement document invalidates a visible recovery action")
        try check(!source.goBackFromLoadFailure(stale), "a stale recovery Back action cannot navigate a replacement document")
        source.errorMessage = "A different local error"
        try check(source.loadFailure == nil, "unrelated notices cannot retain a stale navigation action")
        source.isRetainedForUndo = true
        source.webView(webView, didFailProvisionalNavigation: nil, withError: error)
        try check(source.loadFailure == nil, "retained closed tabs cannot publish page failure actions")
        source.isRetainedForUndo = false
        let unrelatedView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        source.webView(unrelatedView, didFailProvisionalNavigation: nil, withError: error)
        source.webViewWebContentProcessDidTerminate(unrelatedView)
        try check(source.loadFailure == nil, "callbacks from a replaced web view cannot publish recovery actions")
        let empty = BrowserModel(dataStore: .nonPersistent())
        defer { empty.close() }
        empty.activate()
        empty.webView(empty.webView, didFailProvisionalNavigation: nil, withError: error)
        try check(empty.failureCoversPage && empty.loadFailure?.targetURL == target, "a failed first page gets a full accessible recovery surface")
        source.webViewWebContentProcessDidTerminate(webView)
        try check(source.loadFailure?.kind == .processTerminated && source.failureCoversPage,
                  "simulated process termination offers deliberate recovery without automatic reload")
        let processFailure = source.loadFailure!
        var missingCopy = LibraryEntry(address: processFailure.targetURL!.absoluteString, title: "Missing synthetic offline copy")
        missingCopy.offlineID = UUID()
        session.readingList = [missingCopy]
        var failedCopy = false
        do { _ = try session.openSavedCopyForRecovery(missingCopy, browser: source, failure: processFailure) }
        catch { failedCopy = true }
        try check(failedCopy && source.loadFailure?.id == processFailure.id && source.failureCoversPage,
                  "a missing saved copy retains the full navigation failure and recovery actions")
        try check(source.errorMessage == processFailure.message,
                  "offline file errors cannot replace the navigation recovery message")
        let offline = OfflineArticle(title: "Synthetic recovery copy", address: missingCopy.address,
                                     blocks: [.init(kind: "paragraph", text: "A safe local saved copy", jpeg: nil)])
        try session.savePage(missingCopy, reading: true, offline: offline)
        let validCopy = session.readingList.first { $0.id == missingCopy.id }!
        try check(try session.openSavedCopyForRecovery(validCopy, browser: source, failure: processFailure)
                  && source.readerArticle != nil && source.loadFailure?.id == processFailure.id,
                  "opening a valid saved copy preserves the source page failure")
        source.readerArticle = nil
        try check(source.failureCoversPage && source.errorMessage == processFailure.message && source.loadedWebView === webView,
                  "returning from a saved copy restores recovery for the same unrecovered source page")
        _ = session.newTab(privateTab: true)
        try check(try session.articleForRecovery(missingCopy, browser: source, failure: processFailure) == nil,
                  "a saved-copy action captured before private browsing cannot expose the normal library")
        try await recoveryReadStatusFailureChecks()
    }

    private func recoveryReadStatusFailureChecks() async throws {
        let suite = "DuoBrowser.RecoveryReadStatus." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        var rejectWrites = false
        var rejectedWrites = 0
        let archive = BrowserArchiveStore(directory: directory, writeData: { data, url, options in
            if rejectWrites { rejectedWrites += 1; throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: options)
        })
        let session = BrowserSession(storage: defaults, archiveStore: archive, dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let source = session.selected
        try await load(source, "upgrades?recovery-read-status=1")
        let webView = source.webView
        _ = try await js(source, "window.__recoveryCopyRetryMarker=true")
        let address = source.restorationURL!.absoluteString
        let offline = OfflineArticle(title: "Unread recovery copy", address: address,
                                     blocks: [.init(kind: "paragraph", text: "Synthetic unread offline article", jpeg: nil)])
        try session.savePage(LibraryEntry(address: address, title: offline.title, isRead: false), reading: true, offline: offline)
        let unread = session.readingList.first!
        source.webViewWebContentProcessDidTerminate(webView)
        let failure = source.loadFailure!
        rejectWrites = true
        try check(try session.openSavedCopyForRecovery(unread, browser: source, failure: failure)
                  && source.readerArticle != nil && rejectedWrites > 0,
                  "a valid unread saved copy opens despite an injected read-status archive failure")
        try check(session.readingList.first?.isRead == false && archive.load()?.readingList?.first?.isRead == false,
                  "failed recovery read-status persistence rolls back both the live and durable unread state")
        try check(source.loadFailure?.id == failure.id && source.errorMessage == failure.message,
                  "best-effort read-status failure cannot replace the critical source navigation failure")
        source.readerArticle = nil
        try check(source.failureCoversPage && source.loadFailure?.id == failure.id
                  && source.errorMessage == failure.message && source.loadedWebView === webView,
                  "closing that saved copy retains the original failure and retry surface")
        try check(source.retryLoadFailure(failure),
                  "original recovery retry remains actionable after a failed unread-copy status update")
        try await wait {
            guard !source.isLoading, source.loadFailure == nil else { return false }
            return (try? await self.js(source, "document.readyState==='complete' && location.search==='?recovery-read-status=1' && typeof window.__recoveryCopyRetryMarker==='undefined'")) as? Bool == true
        }
        var ordinarySaveFailed = false
        var read = unread; read.isRead = true
        do { try session.savePage(read, reading: true) } catch { ordinarySaveFailed = true }
        try check(ordinarySaveFailed && source.errorMessage == "Your browsing changes could not be saved on this device."
                  && session.readingList.first?.isRead == false,
                  "ordinary saved-page writes still report persistence errors and roll back read state")
    }
}
#endif
