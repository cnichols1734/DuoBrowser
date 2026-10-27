import Combine
import Foundation
import UIKit
import WebKit

@MainActor
final class BrowserModel: NSObject, ObservableObject, Identifiable, WKNavigationDelegate, UIScrollViewDelegate {
    let id: UUID
    let chrome = BrowserChromeState()
    var onChange: (() -> Void)?
    var onOpenTab: ((URLRequest) -> Void)?
    @Published private(set) var title = "Start Page"
    @Published private(set) var snapshot: UIImage?
    private var snapshotGeneration = 0
    private var activated = false
    private var pendingURL: URL?
    private var startsWithFixture = false
    let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        // Let sites keep muted feed previews and playsinline videos inside the page.
        configuration.allowsInlineMediaPlayback = true
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    private var youtubeLayout: YouTubeLayoutAdapter!
    @Published var originalYouTubeLayout = false {
        didSet { updateYouTubeLayout() }
    }
    var fullWidthLayout = true {
        didSet { updateYouTubeLayout() }
    }

    private func updateYouTubeLayout() {
        youtubeLayout?.setEnabled(fullWidthLayout && !originalYouTubeLayout)
    }
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
        guard let url = webView.url ?? pendingURL, !url.isFileURL, let host = url.host else {
            return startsWithFixture ? "Viewport Lab" : "Start Page"
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    init(id: UUID = UUID(), url: URL? = nil, fixture: Bool = true) {
        self.id = id
        pendingURL = url
        startsWithFixture = fixture && url == nil
        super.init()
        title = siteName
        youtubeLayout = YouTubeLayoutAdapter(webView: webView)
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        webView.scrollView.delegate = self
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
        if let url = pendingURL {
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
        let url = webView.url ?? pendingURL
        guard let url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        return url
    }

    var isFixture: Bool { startsWithFixture && restorationURL == nil }

    func captureSnapshot() {
        guard webView.window != nil, webView.bounds.width > 0 else { return }
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
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.scrollView.delegate = nil
        observations.removeAll()
        onChange = nil
        onOpenTab = nil
    }

    private func refreshState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        address = restorationURL?.absoluteString ?? ""
        title = webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? siteName
        onChange?()
    }

    func navigate(to input: String) {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let url: URL?
        if let components = URLComponents(string: value), let scheme = components.scheme {
            guard ["https", "http"].contains(scheme.lowercased()),
                  let host = components.host, !host.isEmpty,
                  components.user == nil, components.password == nil else {
                errorMessage = "Enter an http or https website address."
                return
            }
            url = components.url
        } else if !value.contains(where: \.isWhitespace), value.contains(".") {
            url = URL(string: "https://" + value)
        } else {
            var components = URLComponents(string: "https://duckduckgo.com/")!
            components.queryItems = [URLQueryItem(name: "q", value: value)]
            url = components.url
        }
        guard let url else { errorMessage = "This address could not be opened."; return }
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
        youtubeLayout.applyToCurrentDocument()
    }

    private func report(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        revealControls()
        errorMessage = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        revealControls()
        errorMessage = "The page stopped responding. Reload to try again."
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

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url,
              ["https", "http", "file", "about"].contains(url.scheme?.lowercased() ?? "") else {
            errorMessage = "This starter supports web links only."
            decisionHandler(.cancel)
            return
        }
        if navigationAction.targetFrame == nil {
            decisionHandler(.cancel)
            onOpenTab?(navigationAction.request)
        } else {
            decisionHandler(.allow)
        }
    }
}

/// Only the controls observe per-scroll progress; WebKit layout does not rerun every frame.
@MainActor
final class BrowserChromeState: ObservableObject {
    @Published var progress = 0.0
}
