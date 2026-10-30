import SwiftUI
import WebKit
import Combine

struct ReaderArticle: Identifiable {
    let id = UUID()
    let title: String
    let source: URL
    let blocks: [Block]
    struct Block: Identifiable {
        let id = UUID()
        let kind: String
        let text: String
        var imageURL: URL?
        var width = 0
        var height = 0
        var heading: Bool { kind == "heading" }
    }
    static func parse(_ value: Any?, source: URL) -> ReaderArticle? {
        guard WebAddress.valid(source) != nil, let object = value as? [String: Any],
              let title = object["title"] as? String, title.count <= 512,
              let entries = object["blocks"] as? [[String: Any]], (2...300).contains(entries.count) else { return nil }
        var blocks: [Block] = []
        var count = 0
        var images = 0
        for entry in entries {
            guard let kind = entry["kind"] as? String else { return nil }
            if kind == "image" {
                guard let address = entry["url"] as? String, let url = WebAddress.valid(URL(string: address)),
                      let alt = entry["alt"] as? String, alt.count <= 1024,
                      let width = entry["width"] as? Int, (48...20000).contains(width),
                      let height = entry["height"] as? Int, (32...20000).contains(height), images < 40 else { return nil }
                blocks.append(Block(kind: kind, text: alt, imageURL: url, width: width, height: height))
                images += 1
            } else {
                guard ["heading", "paragraph", "caption"].contains(kind),
                      let text = entry["text"] as? String, !text.isEmpty, text.count <= 8000 else { return nil }
                count += text.count
                guard count <= 108000 else { return nil }
                blocks.append(Block(kind: kind, text: text))
            }
        }
        guard blocks.filter({ $0.kind != "image" }).count >= 2 else { return nil }
        if let heading = blocks.firstIndex(where: { $0.heading && $0.text == title }) { blocks.remove(at: heading) }
        return ReaderArticle(title: title, source: source, blocks: blocks)
    }

    /// Only escaped text and validated HTTP(S) image attributes enter this fixed app-owned template.
    var readerHTML: String {
        let content = blocks.map { block -> String in
            if let url = block.imageURL {
                return "<img src=\"\(Self.escape(url.absoluteString))\" alt=\"\(Self.escape(block.text))\" width=\"\(block.width)\" height=\"\(block.height)\" loading=\"lazy\" decoding=\"async\" referrerpolicy=\"no-referrer\">"
            }
            let tag = block.heading ? "h2" : "p"
            return "<\(tag)\(block.kind == "caption" ? " class=\"caption\"" : "")>\(Self.escape(block.text))</\(tag)>"
        }.joined(separator: "\n")
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: http:; style-src 'unsafe-inline'; script-src 'none'; connect-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'">
        <meta name="referrer" content="no-referrer"><title>\(Self.escape(title))</title>
        <style>
        :root{color-scheme:light dark;--reader-size:19px;--reader-spacing:7px;--reader-paper:#fff;--reader-ink:#171717}
        @media(prefers-color-scheme:dark){:root{--reader-paper:#171717;--reader-ink:#eee}}
        :root[data-theme="Light"]{color-scheme:light;--reader-paper:#fff;--reader-ink:#171717}
        :root[data-theme="Dark"]{color-scheme:dark;--reader-paper:#171717;--reader-ink:#eee}
        :root[data-theme="Sepia"]{color-scheme:light;--reader-paper:#f5edd9;--reader-ink:#302b24}
        html{background:var(--reader-paper);color:var(--reader-ink);-webkit-text-size-adjust:100%}
        body{margin:0;padding:24px;font-family:ui-serif,Georgia,serif;font-size:var(--reader-size);line-height:calc(1.35em + var(--reader-spacing));overflow-wrap:anywhere}
        main,article{width:auto;max-width:none;margin:0;padding:0}
        .source{font:14px -apple-system,sans-serif;opacity:.65;margin:0 0 20px}
        h1{font-family:-apple-system,sans-serif;font-size:1.7em;line-height:1.15;margin:0 0 28px;letter-spacing:-.025em}
        h2{font-size:1.2em;line-height:1.3;margin:28px 0 16px}
        p{margin:0 0 22px}img{display:block;width:100%;max-width:100%;height:auto;margin:24px 0 12px;border-radius:8px;background:rgba(128,128,128,.08)}
        .caption{font:0.8em/1.45 -apple-system,sans-serif;opacity:.7;margin:0 0 28px}
        </style></head><body><main><p class="source">\(Self.escape(source.host ?? "Article"))</p>
        <article><h1>\(Self.escape(title))</h1>\(content)</article></main></body></html>
        """
    }
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
extension BrowserModel {
    func cancelReader() {
        readerRequest = UUID()
        readerLoading = false
        readerArticle = nil
    }
    func finishReaderExtraction(_ value: Any?, request: UUID, generation: UUID, view: WKWebView, source: URL) {
        guard readerRequest == request else { return }
        readerLoading = false
        guard documentGeneration == generation, loadedWebView === view, view.url == source else { return }
        guard let article = ReaderArticle.parse(value, source: source) else {
            errorMessage = "Reader is unavailable for this page. The original page is unchanged."
            return
        }
        readerArticle = article
    }
    func openReader() {
        guard !readerLoading, !isLoading, let view = loadedWebView, let source = restorationURL,
              let scriptURL = Bundle.main.url(forResource: "Reader", withExtension: "js"),
              let script = try? String(contentsOf: scriptURL, encoding: .utf8) else { return }
        let request = UUID()
        readerRequest = request
        let generation = documentGeneration
        readerLoading = true
        Task { @MainActor [weak self, weak view] in
            guard let view else { return }
            let value = try? await view.evaluateJavaScript(script, in: nil, contentWorld: .world(name: "DuoBrowser.Reader"))
            self?.finishReaderExtraction(value, request: request, generation: generation, view: view, source: source)
        }
    }
}

/// Shares only the source's WebKit profile. Reader never joins the saved tab/history session.
@MainActor
final class ReaderRenderer: ObservableObject {
    let browser: BrowserModel
    let article: ReaderArticle
    @Published private(set) var isLoading = false
    private var loaded = false
    private var size = 19.0
    private var spacing = 7.0
    private var theme = "System"
    private var loadingObserver: AnyCancellable?

    init(article: ReaderArticle, sourceBrowser: BrowserModel) {
        self.article = article
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = sourceBrowser.webView.configuration.websiteDataStore
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        browser = BrowserModel(isPrivate: sourceBrowser.isPrivate, configuration: configuration)
        let blocking = sourceBrowser.blockAds
        browser.preferenceForURL = { _ in SitePreference(originalLayout: false, desktop: false, fullWidth: true, blockAds: blocking) }
        browser.blockAds = blocking
        browser.webView.allowsBackForwardNavigationGestures = false
        browser.webView.scrollView.refreshControl = nil
        loadingObserver = browser.$isLoading.sink { [weak self] loading in
            self?.isLoading = loading
            if !loading { self?.applySettings() }
        }
    }
    func load() {
        guard !loaded else { return }
        loaded = true
        isLoading = true
        browser.webView.loadHTMLString(article.readerHTML, baseURL: article.source)
    }
    func update(size: Double, spacing: Double, theme: String) {
        self.size = min(96, max(15, size))
        self.spacing = min(24, max(3, spacing))
        self.theme = ["System", "Light", "Sepia", "Dark"].contains(theme) ? theme : "System"
        applySettings()
    }
    private func applySettings() {
        guard loaded, let view = browser.loadedWebView else { return }
        // Fixed code with typed, bounded preferences; never interpolate article content into executable code.
        view.callAsyncJavaScript("document.documentElement.style.setProperty('--reader-size', size + 'px'); document.documentElement.style.setProperty('--reader-spacing', spacing + 'px'); document.documentElement.dataset.theme = theme;",
                                 arguments: ["size": size, "spacing": spacing, "theme": theme], in: nil,
                                 in: .world(name: "DuoBrowser.ReaderStyle"), completionHandler: nil)
    }
    func close() { loadingObserver = nil; browser.close() }
}

struct ReaderView: View {
    let article: ReaderArticle
    @StateObject private var renderer: ReaderRenderer
    @Environment(\.dismiss) private var dismiss
    @State private var size = 19.0
    @State private var spacing = 7.0
    @State private var theme = "System"
    @AppStorage("browser.showSystemStatus") private var showSystemStatus = false
    @ScaledMetric(relativeTo: .body) private var scale = 1.0

    init(article: ReaderArticle, sourceBrowser: BrowserModel) {
        self.article = article
        _renderer = StateObject(wrappedValue: ReaderRenderer(article: article, sourceBrowser: sourceBrowser))
    }
    var body: some View {
        NavigationStack {
            BrowserSurface(browser: renderer.browser, fullWidth: true, showRegions: false, reservesBrowserControls: false)
                .ignoresSafeArea(.container, edges: .horizontal)
                .overlay(alignment: .top) {
                    if renderer.isLoading {
                        ProgressView().accessibilityLabel("Loading Reader")
                            .padding(12).background(.regularMaterial, in: Capsule()).padding(.top, 12)
                    }
                }
                .navigationTitle("Reader").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 12) {
                        Button("Done") { dismiss() }
                        Menu {
                            ControlGroup {
                                Button("Smaller Text", systemImage: "textformat.size.smaller") { size = max(15, size - 2) }
                                Button("Larger Text", systemImage: "textformat.size.larger") { size = min(31, size + 2) }
                            }
                            Picker("Appearance", selection: $theme) {
                                ForEach(["System", "Light", "Sepia", "Dark"], id: \.self) { Text($0) }
                            }
                            Picker("Line Spacing", selection: $spacing) {
                                Text("Compact").tag(3.0); Text("Comfortable").tag(7.0); Text("Relaxed").tag(12.0)
                            }
                        } label: { Label("Reading Settings", systemImage: "textformat.size") }
                        }
                    }
                }
        }
        .ignoresSafeArea(.container, edges: .horizontal)
        .statusBarHidden(!showSystemStatus)
        .preferredColorScheme(theme == "Dark" ? .dark : theme == "Light" || theme == "Sepia" ? .light : nil)
        .onAppear { renderer.load(); applySettings() }
        .onChange(of: size) { _, _ in applySettings() }
        .onChange(of: spacing) { _, _ in applySettings() }
        .onChange(of: theme) { _, _ in applySettings() }
        .onChange(of: scale) { _, _ in applySettings() }
        .onDisappear { renderer.close() }
    }
    private func applySettings() { renderer.update(size: size * scale, spacing: spacing, theme: theme) }
}
