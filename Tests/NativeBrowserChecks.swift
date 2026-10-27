#if DEBUG
import SwiftUI
import WebKit

/// Debug-only integration harness. Uses synthetic loopback pages and isolated stores, never real browsing data.
struct NativeBrowserChecks: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let host = UIViewController()
        host.view.backgroundColor = .systemBackground
        Task { @MainActor in await NativeCheckRunner(host: host).run() }
        return host
    }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

@MainActor
private final class NativeCheckRunner {
    let host: UIViewController
    var results: [String] = []
    init(host: UIViewController) { self.host = host }
    func check(_ value: Bool, _ label: String) throws {
        if !value { throw NSError(domain: label, code: 1) }
        results.append("PASS: " + label)
    }
    func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        throw NSError(domain: "Timed out waiting for native WebKit", code: 1)
    }
    func mount(_ model: BrowserModel) {
        host.view.subviews.forEach { $0.removeFromSuperview() }
        let view = model.webView
        view.frame = host.view.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(view)
    }
    func js(_ model: BrowserModel, _ script: String) async throws -> Any {
        try await model.webView.evaluateJavaScript(script) ?? NSNull()
    }
    func load(_ model: BrowserModel, _ path: String) async throws {
        mount(model)
        model.navigate(to: "http://127.0.0.1:8765/" + path)
        try await wait {
            guard !model.webView.isLoading, model.webView.url?.path == "/" + path else { return false }
            return (try? await self.js(model, "document.readyState") as? String) == "complete"
        }
    }
    func siteChecks() async {
        let model = BrowserModel(dataStore: .nonPersistent())
        let sites = ["https://www.amazon.com", "https://www.reddit.com", "https://www.google.com", "https://www.wikipedia.org", "https://www.facebook.com", "https://www.instagram.com", "https://www.nytimes.com", "https://www.walmart.com"]
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("LiveSiteChecks.txt")
        defer { model.close() }
        for address in sites {
            do {
                mount(model)
                model.navigate(to: address)
                try await Task.sleep(for: .seconds(2))
                try await wait {
                    guard !model.webView.isLoading else { return false }
                    return (try? await self.js(model, "document.readyState") as? String) == "complete"
                }
                model.webView.obscuredContentInsets = UIEdgeInsets(top: 0, left: 0, bottom: 90, right: 0)
                let regions = host.view.reservedRegions(kind: .occlusion).filter(\.isActive).map { region in
                    let r = self.host.view.convert(region.frame, to: model.webView)
                    return ["x": Double(r.minX), "y": Double(r.minY), "width": Double(r.width), "height": Double(r.height)]
                }
                model.updateGeometry(width: model.webView.bounds.width, height: model.webView.bounds.height, regions: regions)
                try await Task.sleep(for: .seconds(1))
                let metrics = try await js(model, "JSON.stringify({viewport:innerWidth,document:document.documentElement.clientWidth,overflow:document.documentElement.scrollWidth-innerWidth,body:Math.round(document.body.getBoundingClientRect().width)})")
                results.append("\(URL(string: address)!.host!): \(model.errorMessage == nil ? "loaded" : "navigation error: " + (model.errorMessage ?? "")) finalHost=\(model.webView.url?.host ?? "none") bounds=\(model.webView.bounds.size), \(metrics)")
                // Exercise scrolling and ensure adaptation does not prevent native history navigation.
                _ = try await js(model, "window.scrollTo(0,600)")
                try await Task.sleep(for: .milliseconds(350))
                results.append("  scrollY=\(try await js(model, "Math.round(scrollY)")), back=\(model.webView.canGoBack)")
            } catch { results.append("\(URL(string: address)!.host!): check failed (timeout or page script unavailable)") }
            try? results.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        }
    }
    func persistentCookieCheck() async {
        // Dedicated test profile cannot change the user's default browser cookies.
        let store = WKWebsiteDataStore(forIdentifier: UUID(uuidString: "D84C5855-2222-4333-8444-1FCFF8366740")!)
        let model = BrowserModel(dataStore: store)
        do {
            try await load(model, "persistent")
            if ProcessInfo.processInfo.arguments.contains("--persistent-cookie-write") {
                _ = try await js(model, "document.cookie='duo_persistence=synthetic;max-age=86400;path=/';localStorage.setItem('duo_persistence','synthetic')")
                try await Task.sleep(for: .seconds(2))
                try check(store.isPersistent, "test cookie profile is persistent")
            } else {
                try check((try await js(model, "document.cookie") as? String)?.contains("duo_persistence=synthetic") == true, "persistent cookie survives app termination and relaunch")
                try check(try await js(model, "localStorage.getItem('duo_persistence')") as? String == "synthetic", "persistent localStorage survives app termination and relaunch")
                await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            }
        } catch { results.append("FAIL: \(error)") }
        model.close()
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PersistentCookieChecks.txt")
        try? results.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }
    func run() async {
        if ProcessInfo.processInfo.arguments.contains("--site-checks") {
            await siteChecks()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--persistent-cookie-write") || ProcessInfo.processInfo.arguments.contains("--persistent-cookie-read") {
            await persistentCookieCheck()
            return
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NativeChecks-" + UUID().uuidString)
        let store = BrowserArchiveStore(directory: directory)
        let defaults = UserDefaults(suiteName: "DuoBrowser.NativeChecks")!
        let session = BrowserSession(storage: defaults, archiveStore: store, dataStore: .nonPersistent())
        defer { session.tabs.forEach { $0.close() }; try? FileManager.default.removeItem(at: directory) }
        do {
            let normal = session.selected
            try await load(normal, "normal")
            results.append("STEP: normal fixture loaded")
            _ = try await js(normal, "document.cookie='profile=normal;path=/'; localStorage.setItem('profile','normal');document.querySelector('#kept').value='unsent synthetic value'")
            normal.testNavigationObserver = { [weak self] in self?.results.append($0) }
            _ = try await js(normal, "(()=>{let f=document.createElement('iframe');f.id='srcdoc-test';f.srcdoc='<p>embedded fixture</p>';document.body.append(f)})()")
            results.append("STEP: srcdoc created")
            do {
                try await wait { (try? await self.js(normal, "document.querySelector('#srcdoc-test').contentDocument?.body?.textContent") as? String) == "embedded fixture" }
            } catch {
                results.append("FRAME: \(try await js(normal, "JSON.stringify({src:document.querySelector('#srcdoc-test').srcdoc,html:document.querySelector('#srcdoc-test').contentDocument?.documentElement?.outerHTML})"))")
                throw error
            }
            normal.testNavigationObserver = nil
            try check(true, "embedded srcdoc frame loads without a false page error")
            _ = try await js(normal, "document.querySelector('#srcdoc-test').remove()")
            session.switchMode(true)
            let firstPrivate = session.selected
            try await load(firstPrivate, "private-marker")
            try check(try await js(firstPrivate, "document.cookie") as? String == "", "private cookie isolation")
            try check(try await js(firstPrivate, "localStorage.getItem('profile')") is NSNull, "private localStorage isolation")
            _ = try await js(firstPrivate, "document.cookie='profile=private;path=/';localStorage.setItem('profile','private')")
            let secondPrivate = session.newTab()
            try await load(secondPrivate, "private-second")
            try check((try await js(secondPrivate, "document.cookie") as? String)?.contains("profile=private") == true, "private tabs share only their ephemeral session")
            session.saveNow()
            let archive = try String(contentsOf: directory.appendingPathComponent("session.json"), encoding: .utf8)
            try check(!archive.contains("private-marker") && !archive.contains("private-second"), "private destinations absent from persistent archive and history")
            try check(!secondPrivate.webView.configuration.websiteDataStore.isPersistent, "private WebKit store is nonpersistent")
            session.switchMode(false)
            mount(normal)
            try check(try await js(normal, "document.querySelector('#kept').value") as? String == "unsent synthetic value", "live tab switch preserves form value")
            try check((try await js(normal, "document.cookie") as? String)?.contains("profile=normal") == true, "normal cookies survive private browsing")
            session.closePrivateTabs()
            session.switchMode(true)
            let freshPrivate = session.selected
            try await load(freshPrivate, "private-fresh")
            try check(try await js(freshPrivate, "document.cookie") as? String == "", "new private session clears previous cookies")
            try check(try await js(freshPrivate, "localStorage.getItem('profile')") is NSNull, "new private session clears previous localStorage")
            session.switchMode(false); mount(normal)
            normal.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true // Synthetic window event only.
            _ = try await js(normal, "document.querySelector('#post').submit()")
            try await wait { session.selectedID != normal.id }
            let child = session.selected
            mount(child)
            try await wait { !child.webView.isLoading && child.webView.title == "POST child" }
            try check((try await js(child, "document.querySelector('#received').textContent") as? String) == "value=synthetic-post", "target blank preserves POST body")
            try check(try await js(normal, "window.postReceived===true") as? Bool == true, "child retains window.opener")
            _ = try await js(child, "window.close()")
            try await wait { !session.tabs.contains { $0.id == child.id } }
            try check(true, "window.close removes child tab")
            session.select(normal.id); mount(normal)
            var completions = 0
            normal.presentation.ask(origin: "Synthetic origin", message: "Cancel check", kind: "confirm") { _ in completions += 1 }
            normal.presentation.cancel(); normal.presentation.cancel()
            try check(completions == 1, "dialog cancellation completes exactly once")
            normal.webView.obscuredContentInsets = UIEdgeInsets(top: 0, left: 0, bottom: 80, right: 0)
            try await wait {
                let bottom = try? await self.js(normal, "document.querySelector('footer').getBoundingClientRect().bottom") as? Double
                return bottom != nil && bottom! <= normal.webView.bounds.height - 79
            }
            try check(true, "WebKit keeps fixed footer above obscured browser controls")
            let memoryTab = BrowserModel(dataStore: .nonPersistent())
            try await load(memoryTab, "memory")
            _ = try await js(memoryTab, "document.querySelector('#kept').value='unsent synthetic value';window.scrollTo(0,400)")
            mount(normal)
            let protected = await memoryTab.suspendIfIdle { true }
            try check(!protected && memoryTab.loadedWebView != nil, "tab with unsent form is protected from reclamation")
            try check(try await js(memoryTab, "document.querySelector('#kept').value") as? String == "unsent synthetic value", "protected form retains its unsent value")
            try await load(memoryTab, "reading")
            _ = try await js(memoryTab, "window.scrollTo(0,400)")
            try await wait { memoryTab.webView.scrollView.contentOffset.y >= 399 }
            mount(normal)
            let suspended = await memoryTab.suspendIfIdle { true }
            try check(suspended && memoryTab.loadedWebView == nil, "inactive static reading tab releases its WKWebView")
            memoryTab.activate()
            mount(memoryTab)
            try await wait { !memoryTab.webView.isLoading && memoryTab.webView.title == "Reading fixture" }
            results.append("STEP: reading document resumed")
            try await wait { (try? await self.js(memoryTab, "scrollY") as? Double ?? 0) ?? 0 >= 399 }
            try check(true, "static reading tab restores scroll after reclamation")
            memoryTab.close()
            mount(normal)
            let tls = BrowserModel(dataStore: .nonPersistent())
            mount(tls)
            tls.navigate(to: "https://127.0.0.1:8443/")
            try await wait { tls.errorMessage != nil }
            try check(tls.errorMessage?.contains("secure connection could not be verified") == true, "untrusted TLS certificate fails closed without a bypass")
            tls.close()
            mount(normal)
            normal.webViewWebContentProcessDidTerminate(normal.webView)
            try check(normal.errorMessage?.contains("unsent changes") == true, "process termination offers explicit recovery without auto reload")
            try check(BrowserDownloads.safeFilename("../../secret.txt") == "secret.txt", "download path traversal removed")
            try check(BrowserDownloads.safeFilename(".hidden") == "Download", "hidden download name sanitized")
            session.saveNow()
            let restored = BrowserSession(storage: defaults, archiveStore: store, dataStore: .nonPersistent())
            try check(restored.tabs.allSatisfy { !$0.isPrivate }, "cold restore excludes private tabs")
            try check(restored.tabs.filter { $0.loadedWebView != nil }.count == 1, "restored background web views are lazy")
            restored.tabs.forEach { $0.close() }
        } catch { results.append("FAIL: \(error)") }
        let destination = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("NativeBrowserChecks.txt")
        try? results.joined(separator: "\n").write(to: destination, atomically: true, encoding: .utf8)
        host.view.subviews.forEach { $0.removeFromSuperview() }
        let text = UITextView(frame: host.view.bounds)
        text.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        text.text = results.joined(separator: "\n")
        text.isEditable = false
        host.view.addSubview(text)
    }
}
#endif
