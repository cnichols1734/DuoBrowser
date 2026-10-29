import WebKit
import Combine

/// Owns bounded, site-independent layout rules in a separate JavaScript world.
@MainActor
final class PageLayoutAdapter {
    static let world = WKContentWorld.world(name: "DuoBrowser.PageLayout")
    private weak var webView: WKWebView?
    private var installedScript: WKUserScript?
    private(set) var enabled = true
    private let source: String
    private var geometry: [String: Any] = [:]
    private var accessibilityObserver: AnyCancellable?

    init(webView: WKWebView) {
        self.webView = webView
        source = Bundle.main.url(forResource: "PageLayout", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        installScript()
        accessibilityObserver = NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification)
            .merge(with: NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification))
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.applyCamera() }
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
        let others = controller.userScripts.filter {
            $0 !== installedScript && !$0.source.hasPrefix("/* DuoBrowser layout */")
        }
        controller.removeAllUserScripts()
        others.forEach(controller.addUserScript)
        let camera = Bundle.main.url(forResource: "CameraAvoidance", withExtension: "js")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let script = WKUserScript(source: "/* DuoBrowser layout */\n" + camera + "\n" + source + "\nglobalThis.__duoPageLayout?.update(\(enabled));",
                                  injectionTime: .atDocumentEnd, forMainFrameOnly: true,
                                  in: Self.world)
        controller.addUserScript(script)
        installedScript = script
    }

    func updateGeometry(width: Double, height: Double, regions: [[String: Double]]) {
        geometry = ["width": width, "height": height, "regions": regions]
        applyCamera()
    }
    private func applyCamera() {
        guard !geometry.isEmpty else { return }
        var value = geometry
        value["enabled"] = enabled
        value["reduceMotion"] = UIAccessibility.isReduceMotionEnabled
        value["voiceOver"] = UIAccessibility.isVoiceOverRunning
        webView?.callAsyncJavaScript("globalThis.__duoCamera?.update(value)", arguments: ["value": value],
                                    in: nil, in: Self.world, completionHandler: nil)
    }
    func applyToCurrentDocument() {
        applyCamera()
        guard let webView else { return }
        webView.callAsyncJavaScript("return globalThis.__duoPageLayout?.update(enabled);",
                                   arguments: ["enabled": enabled], in: nil, in: Self.world) { _ in }
    }
}
