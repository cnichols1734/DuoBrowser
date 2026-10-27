import Combine
import Foundation
import WebKit

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    let webView = WKWebView(frame: .zero)
    @Published var address = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress = 0.0
    @Published var errorMessage: String?
    @Published var fullWidth = true
    @Published var showRegions = false
    private var observations: [NSKeyValueObservation] = []

    override init() {
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
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
        loadFixture()
    }

    private func refreshState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        address = webView.url?.isFileURL == false ? (webView.url?.absoluteString ?? "") : ""
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
        webView.load(URLRequest(url: url))
    }

    func loadFixture() {
        errorMessage = nil
        if let url = Bundle.main.url(forResource: "ViewportFixture", withExtension: "html") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    private func report(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        errorMessage = error.localizedDescription
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        errorMessage = "The page stopped responding. Reload to try again."
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
            webView.load(navigationAction.request)
        } else {
            decisionHandler(.allow)
        }
    }
}
