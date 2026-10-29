import UIKit
import WebKit

@MainActor
final class BrowserPresentation {
    private weak var browser: BrowserModel?
    private var pendingCancel: (() -> Void)?
    private weak var controller: UIViewController?
    init(browser: BrowserModel) { self.browser = browser }

    var presenter: UIViewController? {
        guard let root = browser?.loadedWebView?.window?.rootViewController else { return nil }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        return top.isBeingDismissed ? nil : top
    }

    func cancel() {
        let completion = pendingCancel
        let presented = controller
        pendingCancel = nil
        controller = nil
        presented?.dismiss(animated: false)
        completion?()
    }

    func ask(origin: String, message: String, kind: String, defaultText: String? = nil,
             completion: @escaping @MainActor (String?) -> Void) {
        guard pendingCancel == nil, let presenter, !(presenter is UIAlertController) else { completion(nil); return }
        let alert = UIAlertController(title: origin, message: String(message.prefix(2048)), preferredStyle: .alert)
        var completed = false
        let finish: (String?) -> Void = { [weak self] value in
            guard !completed else { return }
            completed = true
            self?.pendingCancel = nil
            self?.controller = nil
            completion(value)
        }
        pendingCancel = { finish(nil) }
        controller = alert
        if kind == "prompt" { alert.addTextField { $0.text = String((defaultText ?? "").prefix(2048)) } }
        if kind != "alert" { alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in finish(nil) }) }
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
            finish(kind == "prompt" ? alert?.textFields?.first?.text ?? "" : "OK")
        })
        presenter.present(alert, animated: true)
    }

    func openExternal(_ url: URL) {
        ask(origin: "Open another app?", message: String(url.absoluteString.prefix(512)), kind: "confirm") { [weak self] result in
            guard result != nil else { return }
            UIApplication.shared.open(url, options: [:]) { [weak self] opened in
                if !opened { self?.browser?.errorMessage = "No installed app could open this link." }
            }
        }
    }

    func share(_ url: URL) {
        guard let presenter, pendingCancel == nil else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = browser?.loadedWebView
        activity.popoverPresentationController?.sourceRect = CGRect(x: 20, y: 20, width: 1, height: 1)
        presenter.present(activity, animated: true)
    }
}

extension BrowserModel: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard navigationAction.targetFrame == nil else { return nil }
        popupDates.removeAll { Date().timeIntervalSince($0) > 10 }
        guard popupDates.count < 3 else { errorMessage = "Additional pop-up windows were blocked."; return nil }
        popupDates.append(Date())
        // WebKit loads the original request, including POST body and window.opener, in this returned view.
        guard let onOpenWindow else {
            errorMessage = "Keep this preview as a tab to open this window."
            return nil
        }
        return onOpenWindow(configuration)
    }

    func webViewDidClose(_ webView: WKWebView) { onClose?() }

    private func dialog(_ message: String, frame: WKFrameInfo, kind: String,
                        defaultText: String? = nil, completion: @escaping @MainActor (String?) -> Void) {
        guard dialogCount < 3 else { errorMessage = "Repeated page dialogs were blocked. Reload to allow them again."; completion(nil); return }
        dialogCount += 1
        let origin = frame.securityOrigin
        let label = origin.host.isEmpty ? "This page" : "\(origin.protocol)://\(origin.host)\(origin.port == 0 ? "" : ":\(origin.port)")"
        presentation.ask(origin: label, message: message, kind: kind, defaultText: defaultText, completion: completion)
    }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor () -> Void) {
        dialog(message, frame: frame, kind: "alert") { _ in completionHandler() }
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        dialog(message, frame: frame, kind: "confirm") { completionHandler($0 != nil) }
    }
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        dialog(prompt, frame: frame, kind: "prompt", defaultText: defaultText, completion: completionHandler)
    }
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(origin.protocol == "https" ? .prompt : .deny)
    }
    func webView(_ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(origin.protocol == "https" ? .prompt : .deny)
    }
    func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                 completionHandler: @escaping @MainActor (UIContextMenuConfiguration?) -> Void) {
        guard let url = WebAddress.valid(elementInfo.linkURL) else { completionHandler(nil); return }
        completionHandler(UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Open", image: UIImage(systemName: "arrow.up.right")) { [weak self] _ in self?.navigate(to: url.absoluteString) },
                UIAction(title: "Peek", image: UIImage(systemName: "rectangle.on.rectangle"), attributes: self?.onPeek == nil ? .hidden : []) { [weak self] _ in self?.onPeek?(url) },
                UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in self?.onOpenLink?(url) },
                UIAction(title: "Copy Link", image: UIImage(systemName: "doc.on.doc")) { _ in UIPasteboard.general.url = url },
                UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in self?.presentation.share(url) }
            ])
        })
    }
}
