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
    }
}
#endif
