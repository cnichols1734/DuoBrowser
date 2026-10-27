import Combine
import Foundation
import UIKit
import WebKit

@MainActor
final class BrowserModel: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, UIScrollViewDelegate {
    #if DEBUG
    var testNavigationObserver: ((String) -> Void)?
    #endif
    let id: UUID
    let chrome = BrowserChromeState()
    var onChange: (() -> Void)?
    var onOpenWindow: ((WKWebViewConfiguration) -> WKWebView?)?
    var onOpenLink: ((URL) -> Void)?
    var onClose: (() -> Void)?
    var onVisit: ((URL, String) -> Void)?
    var preferenceForURL: ((URL) -> SitePreference)?
    var onPreferenceChange: ((String, SitePreference) -> Void)?
    let isPrivate: Bool
    private let configuration: WKWebViewConfiguration
    private(set) var loadedWebView: WKWebView?
    lazy var presentation = BrowserPresentation(browser: self)
    lazy var downloads = BrowserDownloads(browser: self)
    var pendingScrollY: Double?
    private var restoringURL: URL?
    private var applyingPreferences = false
    var dialogCount = 0
    var popupDates: [Date] = []
    @Published var desktopSite = false {
        didSet { if !applyingPreferences { saveSitePreference(); loadedWebView?.reload() } }
    }
    var transportLabel: String { loadedWebView?.url?.scheme == "http" ? "Not Secure · " : "" }
    var privateLabel: String { isPrivate ? "Private · " : "" }
    var webView: WKWebView {
        if let loadedWebView { return loadedWebView }
        let view = WKWebView(frame: .zero, configuration: configuration)
        loadedWebView = view
        configure(view)
        return view
    }
    @Published private(set) var title = "Start Page"
    @Published private(set) var snapshot: UIImage?
    private var snapshotGeneration = 0
    private var activated = false
    private var suspendedInteractionState: Any?
    private var currentMethod = "GET"
    var hasWindowRelationships = false
    var lastUsed = Date()
    private var pendingURL: URL?
    private var startsWithFixture = false
    private var pageLayout: PageLayoutAdapter!
    @Published var originalPageLayout = false {
        didSet { updatePageLayout(); if !applyingPreferences { saveSitePreference() } }
    }
    @Published var fullWidthLayout = true {
        didSet {
            guard oldValue != fullWidthLayout else { return }
            updatePageLayout()
            if !applyingPreferences { saveSitePreference() }
        }
    }

    private func updatePageLayout() {
        pageLayout?.setEnabled(fullWidthLayout && !originalPageLayout)
    }
    @Published var availableDownloads = 0
    @Published var activeDownloads = 0
    @Published var address = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var errorMessage: String?
    var keepControlsExpanded = false {
        didSet { if keepControlsExpanded { revealControls() } }
    }
    private var scrollChrome = ScrollChromeState()
    private var observations: [NSKeyValueObservation] = []

    var siteName: String {
        guard let url = loadedWebView?.url ?? pendingURL, !url.isFileURL, let host = url.host else {
            return startsWithFixture ? "Viewport Lab" : "Start Page"
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    init(id: UUID = UUID(), url: URL? = nil, fixture: Bool = false, isPrivate: Bool = false,
         dataStore: WKWebsiteDataStore = .default(), configuration: WKWebViewConfiguration? = nil) {
        self.id = id
        self.isPrivate = isPrivate
        let config = configuration ?? WKWebViewConfiguration()
        // A new-window configuration belongs to WebKit; preserve its process/opener and content controller.
        if configuration == nil { config.websiteDataStore = dataStore }
        else {
            // Keep each tab's adaptation preferences independent. This app installs no message handlers.
            let controller = WKUserContentController()
            config.userContentController.userScripts.filter { !$0.source.hasPrefix("/* DuoBrowser layout */") }
                .forEach(controller.addUserScript)
            config.userContentController = controller
        }
        config.preferences.isFraudulentWebsiteWarningEnabled = true
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true
        config.upgradeKnownHostsToHTTPS = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = false
        self.configuration = config
        pendingURL = url
        startsWithFixture = fixture && url == nil
        super.init()
        title = siteName
    }

    private func configure(_ webView: WKWebView) {
        pageLayout = PageLayoutAdapter(webView: webView)
        updatePageLayout()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isFindInteractionEnabled = true
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        webView.scrollView.delegate = self
        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(refreshPage), for: .valueChanged)
        webView.scrollView.refreshControl = refresh
        observations = [
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshState() }
            },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshState() }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshState() }
            },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshState() }
            },
            webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                Task { @MainActor in self?.refreshState() }
            }
        ]
        observations.append(webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in self?.refreshState() }
        })
    }

    /// Restored background tabs do not load until selected.
    func activate() {
        guard !activated else { return }
        activated = true
        lastUsed = Date()
        if let state = suspendedInteractionState {
            suspendedInteractionState = nil
            restoringURL = pendingURL
            let view = webView
            view.interactionState = state
            // Restoring the list is not a guarantee that a discarded document is loaded.
            // This path is restricted to static GET pages, so explicitly resume its current item.
            if let item = view.backForwardList.currentItem { view.go(to: item) }
            else if let url = pendingURL { view.load(URLRequest(url: url)) }
            return
        }
        if let url = pendingURL {
            restoringURL = url
            webView.load(URLRequest(url: url))
        } else if startsWithFixture {
            loadFixture()
        } else {
            webView.loadHTMLString("""
            <!doctype html><meta name="viewport" content="width=device-width, initial-scale=1">
            <style>:root{color-scheme:light dark}body{font:17px -apple-system;margin:0;padding:28px;
            background:Canvas;color:CanvasText}main{margin-top:18vh}h1{font-size:32px}p{opacity:.6}</style>
            <main><h1>Start Page</h1><p>Search or enter a website below.</p></main>
            """, baseURL: nil)
        }
    }

    var restorationURL: URL? {
        let url = loadedWebView?.url ?? pendingURL
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        return url
    }

    var isFixture: Bool { startsWithFixture && restorationURL == nil }

    func captureSnapshot() {
        guard !isPrivate, let webView = loadedWebView, webView.window != nil, webView.bounds.width > 0 else { return }
        snapshotGeneration += 1
        let generation = snapshotGeneration
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = 360
        webView.takeSnapshot(with: configuration) { [weak self] image, _ in
            guard let self, self.snapshotGeneration == generation else { return }
            if let image { self.snapshot = image }
        }
    }

    func close() {
        snapshotGeneration += 1
        presentation.cancel()
        downloads.cancelAll()
        loadedWebView?.stopLoading()
        loadedWebView?.navigationDelegate = nil
        loadedWebView?.uiDelegate = nil
        loadedWebView?.scrollView.delegate = nil
        loadedWebView?.removeFromSuperview()
        loadedWebView = nil
        suspendedInteractionState = nil
        clearSnapshot()
        observations.removeAll()
        onChange = nil
        onOpenWindow = nil
        onOpenLink = nil
        onClose = nil
        onVisit = nil
        preferenceForURL = nil
        onPreferenceChange = nil
    }

    private func refreshState() {
        guard let webView = loadedWebView else { return }
        let previousAddress = address
        let previousTitle = title
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        address = restorationURL?.absoluteString ?? ""
        title = webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? siteName
        if previousAddress != address || previousTitle != title { onChange?() }
    }

    func navigate(to input: String) {
        guard let url = WebAddress.resolve(input) else {
            errorMessage = "Enter a valid website address or search."
            return
        }
        errorMessage = nil
        startsWithFixture = false
        webView.load(URLRequest(url: url))
    }

    func loadFixture() {
        startsWithFixture = true
        errorMessage = nil
        if let url = Bundle.main.url(forResource: "ViewportFixture", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        presentation.cancel()
        dialogCount = 0
        errorMessage = nil
        revealControls()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshState()
        pageLayout.applyToCurrentDocument()
        webView.scrollView.refreshControl?.endRefreshing()
        if let url = restorationURL { onVisit?(url, title) }
        if let y = pendingScrollY, restoringURL == webView.url {
            // WebKit's DOM can finish before UIScrollView publishes its new contentSize.
            // Restore through the current document instead of clamping against a stale native height.
            webView.callAsyncJavaScript("window.scrollTo(0, y / (window.visualViewport?.scale || 1));",
                arguments: ["y": y], in: nil, in: PageLayoutAdapter.world, completionHandler: nil)
        }
        pendingScrollY = nil
        restoringURL = nil
    }

    private func report(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loadedWebView?.scrollView.refreshControl?.endRefreshing()
        revealControls()
        let code = (error as NSError).code
        if [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
            NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid,
            NSURLErrorSecureConnectionFailed].contains(code) {
            errorMessage = "A secure connection could not be verified. This page was not opened."
        } else { errorMessage = error.localizedDescription }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        revealControls()
        presentation.cancel()
        loadedWebView?.scrollView.refreshControl?.endRefreshing()
        errorMessage = "This page stopped responding. Reload to recover it; unsent changes may be lost."
    }

    func revealControls() {
        scrollChrome.reveal()
        publishChromeIfChanged()
    }

    private func publishChromeIfChanged() {
        if abs(chrome.progress - scrollChrome.progress) > 0.001 {
            chrome.progress = scrollChrome.progress
        }
    }

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        scrollChrome.beginDragging(at: scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let insets = scrollView.adjustedContentInset
        let maximum = scrollView.contentSize.height + insets.top + insets.bottom - scrollView.bounds.height
        scrollChrome.update(offset: scrollView.contentOffset.y + insets.top,
                            maximumOffset: maximum,
                            userScrolling: scrollView.isDragging || scrollView.isDecelerating,
                            keepExpanded: keepControlsExpanded || scrollView.isZooming || errorMessage != nil)
        publishChromeIfChanged()
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate { scrollChrome.settle(); publishChromeIfChanged() }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        scrollChrome.settle()
        publishChromeIfChanged()
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        revealControls()
    }

    func updateGeometry(width: Double, height: Double, regions: [[String: Double]]) {
        pageLayout?.updateGeometry(width: width, height: height, regions: regions)
    }

    @objc private func refreshPage() { webView.reload() }

    /// Keep WebKit's opaque interaction state in memory only. It may contain form values.
    /// Only static reading documents can be suspended; forms and scripts may carry unsaved state.
    func suspendIfIdle(stillInactive: () -> Bool) async -> Bool {
        guard stillInactive(), let view = loadedWebView, view.window == nil, !view.isLoading,
              currentMethod == "GET", !hasWindowRelationships, !downloads.hasWork,
              let url = restorationURL else { return false }
        let protected = try? await view.evaluateJavaScript("Boolean(document.querySelector('script,form,input,textarea,select,[contenteditable],video,audio,iframe,canvas') || document.activeElement?.isContentEditable)") as? Bool
        guard protected == false, stillInactive(), loadedWebView === view, view.window == nil, !view.isLoading,
              let state = view.interactionState else { return false }
        suspendedInteractionState = state
        pendingURL = url
        pendingScrollY = max(0, view.scrollView.contentOffset.y)
        observations.removeAll()
        presentation.cancel()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        view.scrollView.delegate = nil
        view.stopLoading()
        pageLayout = nil
        loadedWebView = nil
        activated = false
        return true
    }

    func clearSnapshot() { snapshotGeneration += 1; snapshot = nil }

    func adoptWindow() { activated = true; _ = webView }

    private func saveSitePreference() {
        guard let host = restorationURL?.host?.lowercased() else { return }
        onPreferenceChange?(host, SitePreference(originalLayout: originalPageLayout, desktop: desktopSite, fullWidth: fullWidthLayout))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        #if DEBUG
        testNavigationObserver?("ACTION: \(navigationAction.request.url?.absoluteString ?? "nil") path=\(navigationAction.request.url?.path ?? "nil") frame=\(String(describing: navigationAction.targetFrame?.isMainFrame))")
        #endif
        guard let url = navigationAction.request.url else { decisionHandler(.cancel, preferences); return }
        let scheme = url.scheme?.lowercased() ?? ""
        if ["https", "http"].contains(scheme) {
            guard WebAddress.valid(url) != nil else { decisionHandler(.cancel, preferences); return }
            if navigationAction.targetFrame?.isMainFrame != false {
                currentMethod = navigationAction.request.httpMethod ?? "GET"
                let site = preferenceForURL?(url) ?? SitePreference()
                applyingPreferences = true
                originalPageLayout = site.originalLayout
                desktopSite = site.desktop
                fullWidthLayout = site.fullWidth ?? true
                applyingPreferences = false
                preferences.preferredContentMode = desktopSite ? .desktop : .mobile
            }
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow, preferences)
        } else if scheme == "about" && ["about:blank", "about:srcdoc"].contains(
            String(url.absoluteString.split(separator: "#", maxSplits: 1).first ?? "").lowercased()) {
            decisionHandler(.allow, preferences)
        } else if scheme == "data" && (navigationAction.targetFrame?.isMainFrame == false || navigationAction.shouldPerformDownload) {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow, preferences)
        } else if scheme == "file", let resource = Bundle.main.resourceURL,
                  url.standardizedFileURL.path.hasPrefix(resource.path + "/") {
            decisionHandler(.allow, preferences)
        } else if scheme == "blob" {
            decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow, preferences)
        } else {
            decisionHandler(.cancel, preferences)
            if navigationAction.navigationType == .linkActivated,
               ["tel", "mailto", "sms", "maps"].contains(scheme) {
                presentation.openExternal(url)
            } else if navigationAction.navigationType == .linkActivated {
                errorMessage = "This link cannot be opened in the browser."
            }
            // A background frame or automatic app redirect must not replace the page with an error.
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        decisionHandler(navigationResponse.canShowMIMEType ? .allow : .download)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        downloads.add(download)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        downloads.add(download)
    }

}

/// Only the controls observe per-scroll progress; WebKit layout does not rerun every frame.
@MainActor
final class BrowserChromeState: ObservableObject {
    @Published var progress = 0.0
}
