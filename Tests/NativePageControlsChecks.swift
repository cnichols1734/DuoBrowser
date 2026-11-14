#if DEBUG
import SwiftUI
import UIKit
import WebKit

extension NativeCheckRunner {
    func premiumControlsChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PremiumControls-" + UUID().uuidString)
        let suite = "DuoBrowser.PremiumControls." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let session = BrowserSession(storage: defaults, archiveStore: BrowserArchiveStore(directory: directory), dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let source = session.selected
        try await load(source, "upgrades?controls=1")
        _ = try await js(source, "document.querySelector('#kept').value='Synthetic controls draft'")
        let webView = source.webView
        let generation = source.documentGeneration
        let pageActions: [PageControlsAction] = [.share, .save, .find, .reader, .protection, .websiteSettings, .forward]
        let requests = pageActions.map { PageControlsRequest(action: $0, browser: source) }
        let settings = PageControlsRequest(action: .settings, browser: source)
        let pin = PageControlsRequest(action: .pin, browser: source)
        try check(requests.allSatisfy { $0.matches(source) }, "page controls accept their original tab and document")
        let other = BrowserModel(dataStore: .nonPersistent())
        let privateTab = BrowserModel(isPrivate: true, dataStore: .nonPersistent())
        defer { other.close(); privateTab.close() }
        try check(requests.allSatisfy { !$0.matches(other) } && !settings.matches(other),
                  "queued controls cannot target a replacement normal tab")
        try check(requests.allSatisfy { !$0.matches(privateTab) } && !settings.matches(privateTab),
                  "queued controls cannot cross into a private tab")

        var actionCount = 0
        let controls = UIHostingController(rootView: PageControlsView(session: session, browser: source) { _ in actionCount += 1 })
        host.addChild(controls)
        controls.view.frame = host.view.bounds
        controls.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(controls.view)
        controls.didMove(toParent: host)
        controls.view.layoutIfNeeded()
        await Task.yield()
        try check(source.loadedWebView === webView && source.documentGeneration == generation,
                  "opening page controls retains the live WebKit document")
        try check(try await js(source, "document.querySelector('#kept').value") as? String == "Synthetic controls draft",
                  "opening page controls preserves unsent website input")
        controls.willMove(toParent: nil)
        controls.view.removeFromSuperview()
        controls.removeFromParent()
        try check(actionCount == 0, "viewing and dismissing page controls performs no page action")

        // Navigate to the same origin and URL: a host or address check alone cannot reject this stale action.
        try await load(source, "upgrades?controls=1")
        try check(source.documentGeneration != generation && requests.allSatisfy { !$0.matches(source) },
                  "same-address navigation invalidates every queued document action")
        try check(settings.matches(source) && pin.matches(source),
                  "browser and tab organization actions remain valid after same-tab navigation")
        try check(PageControlsRequest(action: .share, browser: source).matches(source),
                  "newly requested page actions use the replacement document")
    }
}
#endif
