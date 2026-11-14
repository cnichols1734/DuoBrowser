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
        try await protectionPresentationScopeChecks(session: session, browser: source)
    }

    private func protectionPresentationScopeChecks(session: BrowserSession, browser: BrowserModel) async throws {
        let sourceHost = browser.restorationURL?.host
        var originalScope: WebsiteSettingsScope?
        var renderedScope: WebsiteSettingsScope?
        var renderedCurrent = false
        var toggle: Binding<Bool>?
        var renderedReplacement = false
        func screen(replacement: Bool) -> BrowserProtectionView {
            var screen = BrowserProtectionView(session: session, browser: browser)
            screen.scopeDidChange = { scope, isCurrent, binding in
                if originalScope == nil { originalScope = scope }
                renderedScope = scope
                renderedCurrent = isCurrent
                toggle = binding
                if replacement { renderedReplacement = true }
            }
            return screen
        }
        let protection = UIHostingController(rootView: screen(replacement: false))
        host.addChild(protection)
        protection.view.frame = host.view.bounds
        host.view.addSubview(protection.view)
        protection.didMove(toParent: host)
        defer {
            protection.willMove(toParent: nil)
            protection.view.removeFromSuperview()
            protection.removeFromParent()
        }
        try await wait { originalScope != nil && toggle != nil }
        let scopeID = originalScope!.id
        try check(originalScope?.host == sourceHost && renderedCurrent,
                  "protection presentation captures the original website in rendered SwiftUI state")
        toggle?.wrappedValue = false
        try check(!browser.blockAds && session.blockingExceptions(isPrivate: false).contains(sourceHost!),
                  "rendered protection toggle updates its original website")
        toggle?.wrappedValue = true

        // Keep the protection UI mounted while WebKit navigates to a distinct real fixture origin.
        // Calling load() here would remove the UI from its window and miss the presentation-lifetime bug.
        let destination = URL(string: "http://localhost:8765/upgrades?protection-scope=1")!
        browser.navigate(to: destination.absoluteString)
        try await wait {
            guard browser.restorationURL == destination, !browser.isLoading else { return false }
            return (try? await self.js(browser, "document.readyState==='complete' && location.hostname==='localhost'")) as? Bool == true
        }
        try await wait { !renderedCurrent }

        // A SwiftUI sheet builder can initialize a new value without creating a new presentation identity.
        // The old plain stored scope recaptured localhost here and made the stale controls current again.
        protection.rootView = screen(replacement: true)
        protection.view.setNeedsLayout()
        protection.view.layoutIfNeeded()
        try await wait { renderedReplacement }
        try check(renderedScope?.id == scopeID && renderedScope?.host == sourceHost && !renderedCurrent,
                  "rebuilding protection sheet content after navigation retains its original website scope")
        let value = browser.blockAds
        toggle?.wrappedValue = !value
        try check(browser.blockAds == value && !session.blockingExceptions(isPrivate: false).contains("localhost"),
                  "stale rendered protection toggle cannot retarget the newly navigated website")
    }
}
#endif
