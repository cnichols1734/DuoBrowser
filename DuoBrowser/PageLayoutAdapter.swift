import WebKit

/// Owns bounded, site-independent layout rules in a separate JavaScript world.
@MainActor
final class PageLayoutAdapter {
    static let world = WKContentWorld.world(name: "DuoBrowser.PageLayout")
    private weak var webView: WKWebView?
    private var installedScript: WKUserScript?
    private(set) var enabled = true
    private let source: String

    init(webView: WKWebView) {
        self.webView = webView
        source = Bundle.main.url(forResource: "PageLayout", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        installScript()
    }

    func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        installScript()
        applyToCurrentDocument()
    }

    private func installScript() {
        guard let controller = webView?.configuration.userContentController, !source.isEmpty else { return }
        // Preserve any other future user scripts when replacing our document-end configuration.
        let others = controller.userScripts.filter { $0 !== installedScript }
        controller.removeAllUserScripts()
        others.forEach(controller.addUserScript)
        let script = WKUserScript(source: source + "\nglobalThis.__duoPageLayout?.update(\(enabled));",
                                  injectionTime: .atDocumentEnd, forMainFrameOnly: true,
                                  in: Self.world)
        controller.addUserScript(script)
        installedScript = script
    }

    func applyToCurrentDocument() {
        guard let webView else { return }
        webView.callAsyncJavaScript("return globalThis.__duoPageLayout?.update(enabled);",
                                   arguments: ["enabled": enabled], in: nil, in: Self.world) { _ in }
    }
}
