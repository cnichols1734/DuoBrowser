#if DEBUG
import SwiftUI
import WebKit
import Darwin
import BrowserKit

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
final class NativeCheckRunner {
    let host: UIViewController
    var results: [String] = []
    private var passedChecks = 0
    init(host: UIViewController) {
        self.host = host
        writeProgress(last: "Harness started.")
    }
    private func writeProgress(last label: String) {
        // Only this Debug synthetic harness writes progress; never capture a live page or browsing state.
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NativeCheckProgress.txt")
        let text = "\(passedChecks) checks passed\nLast: \(label.prefix(512))\n"
        try? text.write(to: file, atomically: true, encoding: .utf8)
    }
    func check(_ value: Bool, _ label: String) throws {
        if !value { throw NSError(domain: label, code: 1) }
        results.append("PASS: " + label)
        passedChecks += 1
        if passedChecks == 1 || passedChecks.isMultiple(of: 5) { writeProgress(last: label) }
    }
    func tabStackChecks() async throws {
        let models = (0..<6).map { _ in BrowserModel(dataStore: .nonPersistent()) }
        let controller = TabStackController()
        var visible = models
        var dismissals: [UUID: () -> Void] = [:]
        var closedIDs: [UUID] = []
        var reduced = false
        func update() {
            controller.update(tabs: visible, selectedID: models[3].id, reduceMotion: reduced, close: { id in
                closedIDs.append(id)
                visible.removeAll { $0.id == id }
                update()
            }) { tab, dismiss in
                dismissals[tab.id] = dismiss
                return AnyView(VStack {
                    Text("Synthetic tab preview")
                    Button("Close", action: dismiss)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.blue.opacity(0.2)))
            }
        }
        host.addChild(controller)
        controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 520)
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        defer {
            controller.update(tabs: [], selectedID: models[3].id, reduceMotion: true, close: { _ in }) { _, _ in AnyView(EmptyView()) }
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            models.forEach { $0.close() }
        }
        update()
        controller.view.layoutIfNeeded()
        try await wait { controller.collectionView.numberOfItems(inSection: 0) == 6 }
        let layout = controller.stackLayout, collection = controller.collectionView
        let first = layout.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))!.frame
        let second = layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!.frame
        try check(first.minY == second.minY && second.maxX > 370, "grid uses both columns across the display")
        try check(!first.intersects(second), "neighboring tab hit targets do not overlap")
        let source = controller.zoomSource(for: models[3].id, centered: true)
        try check(source != nil && abs(source!.bounds.height - layout.cardWidth / 0.72) < 1,
                  "zoom source is exactly the page preview, excluding its title")
        try await wait { dismissals[models[3].id] != nil }
        let departing = collection.cellForItem(at: IndexPath(item: 3, section: 0)) as! TabStackCell
        departing.motionView.transform = CGAffineTransform(translationX: -90, y: 0)
        collection.setNeedsLayout()
        collection.layoutIfNeeded()
        try check(departing.motionView.transform.tx == -90, "layout preserves the dragged card offset")
        dismissals[models[3].id]?()
        var previousX: CGFloat = -90
        for _ in 0..<8 {
            try await Task.sleep(for: .milliseconds(20))
            guard visible.contains(where: { $0.id == models[3].id }), departing.representedID == models[3].id else { break }
            collection.setNeedsLayout()
            collection.layoutIfNeeded()
            if let presentation = departing.motionView.layer.presentation() {
                let x = presentation.affineTransform().tx
                try check(x <= previousX + 1, "committed dismissal travels leftward through layout passes (\(previousX) to \(x))")
                previousX = x
            }
        }
        try await wait { collection.numberOfItems(inSection: 0) == 5 }
        try check(!visible.contains { $0.id == models[3].id }, "animated close removes intended tab once")
        try check(visible[3].id == models[4].id, "next tab fills the removed grid position")
        reduced = true
        update()
        collection.layoutIfNeeded()
        let back = layout.layoutAttributesForItem(at: IndexPath(item: 1, section: 0))!
        try check(back.transform == .identity, "Reduce Motion keeps cards untransformed")
        controller.view.frame.size = CGSize(width: 700, height: 520)
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
        try check(controller.zoomSource(for: visible[2].id, centered: true) != nil,
                  "resizing preserves the selected preview as a zoom target")
        reduced = false
        update()
        let departingID = visible[2].id
        try await wait { dismissals[departingID] != nil }
        dismissals[departingID]?()
        controller.update(tabs: [], selectedID: models[3].id, reduceMotion: false, close: { id in
            closedIDs.append(id)
            visible.removeAll { $0.id == id }
        }) { _, _ in AnyView(EmptyView()) }
        controller.finishPendingDismissals()
        try await wait { closedIDs.contains(departingID) }
        try await Task.sleep(for: .milliseconds(350))
        try check(closedIDs.filter { $0 == departingID }.count == 1,
                  "filtering and teardown complete a committed close exactly once")
    }
    func wideTabLayoutChecks() throws {
        let models = (0..<40).map { _ in BrowserModel(dataStore: .nonPersistent()) }
        let controller = TabStackController()
        host.addChild(controller)
        controller.view.frame = CGRect(x: 0, y: 0, width: 678, height: 300)
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        defer {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            models.forEach { $0.close() }
        }
        for reduced in [false, true] {
            controller.update(tabs: models, selectedID: models[20].id, reduceMotion: reduced, close: { _ in }) { _, _ in
                AnyView(Color.white)
            }
            controller.view.layoutIfNeeded()
            let collection = controller.collectionView, layout = controller.stackLayout
            _ = controller.zoomSource(for: models[20].id, centered: true)
            collection.layoutIfNeeded()
            let expected = Set(models.indices.compactMap { index -> Int? in
                let attributes = layout.layoutAttributesForItem(at: IndexPath(item: index, section: 0))!
                return attributes.frame.intersects(collection.bounds) ? index : nil
            })
            let actual = Set((layout.layoutAttributesForElements(in: collection.bounds) ?? []).map { $0.indexPath.item })
            try check(actual == expected && actual.contains(20), "wide grid includes all visible cards, reduced motion \(reduced)")
        }
    }

    func tabZoomChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TabZoom-" + UUID().uuidString)
        let session = BrowserSession(storage: UserDefaults(suiteName: "TabZoom-" + UUID().uuidString)!,
            archiveStore: BrowserArchiveStore(directory: directory), dataStore: .nonPersistent())
        let controller = BrowserZoomController(session: session)
        host.addChild(controller)
        controller.view.frame = host.view.bounds
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
        defer {
            controller.willMove(toParent: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParent()
            session.tabs.forEach { $0.close() }
            try? FileManager.default.removeItem(at: directory)
        }
        try await wait { controller.presentedViewController != nil && controller.presentedViewController?.isBeingPresented == false }
        let original = session.selected
        let webView = original.webView
        try check(true, "zoom shell initially presents the live browser")
        session.showTabs()
        try await wait { controller.presentedViewController == nil }
        try check(original.webView === webView, "zooming out preserves the live web view")
        let next = session.newTab()
        try await wait { controller.presentedViewController != nil && controller.presentedViewController?.isBeingPresented == false }
        try check(session.selectedID == next.id, "new tab can zoom into the browser")
        session.showTabs()
        try await wait { controller.presentedViewController == nil }
        session.select(original.id)
        try await wait { controller.presentedViewController != nil && controller.presentedViewController?.isBeingPresented == false }
        try check(session.selected.webView === webView, "selecting another card preserves its existing web view")
        controller.update(reduceMotion: true)
        session.showTabs()
        try await wait { controller.presentedViewController == nil }
        try check(true, "Reduce Motion returns to overview without a slide transition")
    }

    func wait(timeout: Double = 10, _ condition: () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while clock.now < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        // Task.sleep can resume late on a busy simulator. Observe the condition once
        // more after waking instead of reporting stale state from before that sleep.
        if await condition() { return }
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
        var lastReadyState = "not evaluated"
        var lastScriptError = "none"
        let clock = ContinuousClock()
        let started = clock.now
        do {
            // A fresh hosted simulator may need to launch WebKit's network/render processes.
            // Loading has its own bound; interaction checks retain their shorter deadline.
            try await wait(timeout: 60) {
                guard !model.webView.isLoading, model.webView.url?.path == "/" + path.components(separatedBy: "?")[0] else { return false }
                do {
                    lastReadyState = try await self.js(model, "document.readyState") as? String ?? "not a string"
                    lastScriptError = "none"
                    return lastReadyState == "complete"
                } catch {
                    lastScriptError = String(describing: error)
                    return false
                }
            }
        } catch {
            results.append("LOAD: expected=\(path) actual=\(model.webView.url?.path ?? "nil") loading=\(model.webView.isLoading) title=\(model.webView.title ?? "nil") error=\(model.errorMessage ?? "none") readyState=\(lastReadyState) scriptError=\(lastScriptError) elapsed=\(started.duration(to: clock.now))")
            throw error
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
                try await wait {
                    let cookies = await withCheckedContinuation { continuation in
                        store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
                    }
                    return cookies.contains { $0.name == "duo_persistence" && $0.value == "synthetic" &&
                        !$0.isSessionOnly && ($0.expiresDate ?? .distantPast) > Date() }
                }
                try check((try await js(model, "document.cookie") as? String)?.contains("duo_persistence=synthetic") == true,
                          "persistent cookie write is visible to WebKit and the document")
                try check(store.isPersistent, "test cookie profile is persistent")
                // Retain the existing settling interval after confirming the write.
                try await Task.sleep(for: .seconds(2))
            } else {
                let cookies = await withCheckedContinuation { continuation in
                    store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
                }
                let retained = cookies.first { $0.name == "duo_persistence" }
                let storageRetained = try await js(model, "localStorage.getItem('duo_persistence')") as? String == "synthetic"
                results.append("PERSISTENCE: nativeCookie=\(retained != nil) persistent=\(retained?.isSessionOnly == false) localStorage=\(storageRetained)")
                try check((try await js(model, "document.cookie") as? String)?.contains("duo_persistence=synthetic") == true, "persistent cookie survives app termination and relaunch")
                try check(try await js(model, "localStorage.getItem('duo_persistence')") as? String == "synthetic", "persistent localStorage survives app termination and relaunch")
                await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
            }
        } catch { results.append("FAIL: \(error)") }
        model.close()
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("PersistentCookieChecks.txt")
        try? results.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }
    func memoryChecks() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MemoryChecks-" + UUID().uuidString)
        let session = BrowserSession(storage: UserDefaults(suiteName: "DuoBrowser.MemoryChecks")!,
            archiveStore: BrowserArchiveStore(directory: directory), dataStore: .nonPersistent())
        func footprint() -> UInt64 {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            return status == KERN_SUCCESS ? info.phys_footprint : 0
        }
        func record(_ stage: String) {
            let images = session.tabs.compactMap { $0.snapshot?.cgImage }
            let bytes = images.reduce(0) { $0 + $1.bytesPerRow * $1.height }
            results.append("METRIC: \(stage) tabs=\(session.tabs.count) loaded=\(session.tabs.filter { $0.loadedWebView != nil }.count) previews=\(images.count) previewBytes=\(bytes) appFootprint=\(footprint())")
        }
        defer { session.tabs.forEach { $0.close() }; try? FileManager.default.removeItem(at: directory) }
        do {
            record("start")
            for index in 0..<20 {
                let tab = index == 0 ? session.selected : session.newTab()
                try await load(tab, index < 16 ? "reading?tab=\(index)" : "memory?tab=\(index)")
                if index >= 16 { _ = try await js(tab, "document.querySelector('#kept').value='keep unsent'") }
                tab.captureSnapshot()
                try await wait { tab.snapshot != nil }
                // Exercise the production preview policy via the overview entry point.
                session.showTabs(); session.showingTabs = false
                try await Task.sleep(for: .milliseconds(150))
            }
            try await Task.sleep(for: .seconds(2))
            record("twenty-tabs")
            try check(session.tabs.reduce(0) { $0 + $1.snapshotByteCount } <= 8 * 1024 * 1024, "preview cache stays within eight MiB")
            try check(session.tabs.compactMap { $0.snapshot?.cgImage }.allSatisfy { max($0.width, $0.height) <= 640 }, "preview rasters stay within 640 pixels")
            let protectedTabs = Array(session.tabs.suffix(4))
            try check(protectedTabs.allSatisfy { $0.loadedWebView != nil }, "interactive pages remain loaded before pressure")
            NotificationCenter.default.post(name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
            try await Task.sleep(for: .seconds(3))
            record("memory-warning")
            try check(session.tabs.allSatisfy { $0.snapshot == nil }, "memory warning discards every preview")
            try check(session.tabs.prefix(16).allSatisfy { $0.loadedWebView == nil }, "memory warning reclaims eligible reading tabs")
            for tab in protectedTabs {
                try check(try await js(tab, "document.querySelector('#kept').value") as? String == "keep unsent", "memory warning preserves an unsent form")
            }
            let first = session.tabs[0]
            session.select(first.id); mount(first)
            try await wait { !first.webView.isLoading && first.webView.title == "Reading fixture" }
            try check(true, "reclaimed reading tab reloads when selected")
            for tab in Array(session.tabs.dropFirst()) { session.close(tab.id) }
            try await Task.sleep(for: .seconds(2))
            record("closed-nineteen")
            let manyStore = BrowserArchiveStore(directory: directory.appendingPathComponent("many"))
            let records = (0..<200).map { TabRecord(id: UUID(), address: "http://127.0.0.1:8765/reading?tab=\($0)", fixture: false) }
            try manyStore.write(BrowserArchive(session: TabArchive(tabs: records, selectedID: records[0].id)))
            let many = BrowserSession(storage: UserDefaults(suiteName: "DuoBrowser.MemoryChecks.Lazy")!, archiveStore: manyStore, dataStore: .nonPersistent())
            try check(many.tabs.count == 200 && many.tabs.filter { $0.loadedWebView != nil }.count == 1, "two hundred restored tabs create one WKWebView")
            many.showingTabs = true; many.showingLibrary = true
            let fullSelection = many.selectedID
            try check(!many.openExternalURL(URL(string: "https://example.com/incoming")!) && many.tabs.count == 200 && many.selectedID == fullSelection,
                      "incoming link at capacity preserves all tabs and current selection")
            try check(many.selected.errorMessage?.contains("200 tab limit") == true && !many.showingTabs && !many.showingLibrary,
                      "incoming link at capacity reveals a visible close-a-tab explanation")
            many.tabs.forEach { $0.close() }
        } catch { results.append("FAIL: \(error)") }
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MemoryChecks.txt")
        try? results.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
        host.view.subviews.forEach { $0.removeFromSuperview() }
        let text = UITextView(frame: host.view.bounds)
        text.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        text.text = results.joined(separator: "\n"); text.isEditable = false
        host.view.addSubview(text)
    }
    func settlingChecks() async {
        let model = BrowserModel(dataStore: .nonPersistent())
        defer { model.close() }
        func camera(_ regions: [[String: Double]], enabled: Bool = true, reduceMotion: Bool = false, voiceOver: Bool = false) async throws {
            let _: Any = try await model.webView.callAsyncJavaScript("globalThis.__duoCamera.update(value); return true", arguments: ["value": [
                "enabled": enabled, "width": model.webView.bounds.width, "height": model.webView.bounds.height,
                "regions": regions, "reduceMotion": reduceMotion, "voiceOver": voiceOver
            ]], in: nil, in: PageLayoutAdapter.world)
        }
        func measure(_ property: String, _ id: String = "reading") async throws -> Double {
            try await js(model, "document.getElementById('\(id)').getBoundingClientRect().\(property)") as? Double ?? -9999
        }
        func pause() async throws { try await Task.sleep(for: .milliseconds(950)) }
        do {
            try await load(model, "settling")
            let original = try await measure("width")
            let gap = (try await measure("top", "following")) - (try await measure("bottom"))
            let lineScript = "(()=>{const r=document.createRange();r.selectNodeContents(document.getElementById('reading'));return JSON.stringify([...r.getClientRects()].map(q=>[q.width,q.height]))})()"
            let lines = try await js(model, lineScript) as? String
            let compact = [["x": Double(model.webView.bounds.width)-80, "y": 20.0, "width": 80.0, "height": 120.0]]
            // Capture the real production animation in its isolated world. A busy hosted
            // simulator can skip an entire wall-clock rAF window, so sample its actual
            // WebKit-rendered interpolation at deterministic timeline positions instead.
            _ = try await model.webView.evaluateJavaScript("""
                (() => {
                    const original = Element.prototype.animate;
                    globalThis.__duoNativeMotion = null;
                    Element.prototype.animate = function(...args) {
                        const animation = original.apply(this, args);
                        if (this.id === 'reading') {
                            Element.prototype.animate = original;
                            globalThis.__duoNativeMotion = animation;
                            animation.pause();
                        }
                        return animation;
                    };
                })()
                """, in: nil, contentWorld: PageLayoutAdapter.world)
            try await camera(compact)
            try await wait {
                (try? await model.webView.evaluateJavaScript("Boolean(globalThis.__duoNativeMotion)", in: nil,
                    contentWorld: PageLayoutAdapter.world)) as? Bool == true
            }
            let interpolates = try await model.webView.evaluateJavaScript("""
                (() => {
                    const animation = globalThis.__duoNativeMotion;
                    const duration = animation.effect.getTiming().duration;
                    if (duration !== 420) return false;
                    const samples = [0, .25, .5, .75, 1].map(fraction => {
                        animation.currentTime = duration * fraction;
                        const r = document.getElementById('reading').getBoundingClientRect();
                        return {x:r.x, y:r.y};
                    });
                    animation.finish();
                    delete globalThis.__duoNativeMotion;
                    return samples.some(r=>r.x>17&&r.x<88) && samples.every(r=>Math.abs(r.y-24)<1);
                })()
                """, in: nil, contentWorld: PageLayoutAdapter.world) as? Bool
            try check((try await measure("right")) <= model.webView.bounds.width-87, "WebKit paragraph fits beside synthetic island")
            try check(interpolates == true, "WebKit animation interpolates horizontally without pushing text down")
            try check(try await js(model, "getComputedStyle(document.getElementById('reading')).fontSize") as? String == "18px", "WebKit fitting preserves font size")
            try check(abs((try await measure("top", "following"))-(try await measure("bottom"))-gap) < 1, "WebKit following paragraph preserves its natural gap")
            try check(try await js(model, "scrollY") as? Double == 0, "WebKit settling preserves initial scroll offset")
            try check(try await js(model, "typeof globalThis.__duoCamera") as? String == "undefined", "camera controller is isolated from the page world")
            try await camera([], enabled: false)
            try check(abs((try await measure("width"))-original)<1, "Original Layout restores native paragraph width")
            _ = try await js(model, "dispatchEvent(new Event('pointerdown'))")
            try await camera(compact)
            try await pause()
            try check(try await js(model, lineScript) as? String == lines, "WebKit keeps line wrapping stable during held touch")
            _ = try await js(model, "dispatchEvent(new Event('pointerup'))")
            try await pause()
            try check((try await measure("right")) <= model.webView.bounds.width-87, "WebKit fits sideways after touch release")
            let expanded = [["x": Double(model.webView.bounds.width)-100, "y": 20.0, "width": 100.0, "height": 180.0]]
            try await camera(expanded); try await pause()
            try check((try await measure("right")) <= model.webView.bounds.width-107, "WebKit follows wider synthetic island geometry sideways")
            let status = [["x": Double(model.webView.bounds.width)-80, "y": 160.0, "width": 80.0, "height": 80.0]]
            try await camera(compact + status); try await pause()
            try check(abs((try await measure("top"))-24)<1, "WebKit stacked status regions never push the paragraph down")
            try await camera([["x": 8, "y": 20, "width": Double(model.webView.bounds.width)-16, "height": 150]])
            try await pause()
            try check(abs((try await measure("width"))-original)<1, "WebKit full-width island falls back instead of moving text down")
            try await camera([]); try await pause()
            try check(abs((try await measure("width"))-original)<1, "WebKit restores width after occlusion removal")
            try await camera(compact, reduceMotion: true); try await pause()
            try check(try await js(model, "document.getElementById('reading').getAnimations().length") as? Int == 0, "native Reduce Motion disables settling animation")
            try await camera([], enabled: false)
            try await camera(compact, voiceOver: true); try await pause()
            try check(abs((try await measure("width"))-original)<1, "VoiceOver preserves native reading layout")
            try await camera([], enabled: false)
            try await camera(compact); try await pause()
            _ = try await js(model, "dispatchEvent(new Event('pointerdown'));scrollTo(0,document.getElementById('following').getBoundingClientRect().top+scrollY-8)")
            let readingTop = try await measure("top", "following")
            _ = try await js(model, "window.anchorSamples=[];window.anchorUntil=performance.now()+900;requestAnimationFrame(function sample(){const r=document.getElementById('following').getBoundingClientRect();anchorSamples.push({x:r.x,y:r.y});if(performance.now()<anchorUntil)requestAnimationFrame(sample)});dispatchEvent(new Event('pointerup'))")
            try await pause()
            let settledTop = try await measure("top", "following")
            try check(readingTop > 0 && abs(settledTop-readingTop)<1, "WebKit keeps visible text below the top when offscreen fitting is removed")
            try check(try await js(model, "anchorSamples.every(r=>Math.abs(r.y-\(readingTop))<1)") as? Bool == true, "WebKit sideways settling never lifts the anchored paragraph")
            try check(try await js(model, "anchorSamples.some(r=>r.x>17)&&document.getElementById('following').getAnimations().length===0") as? Bool == true, "WebKit anchor correction does not interrupt its sideways animation")
            try await camera([], enabled: false)
            _ = try await js(model, "scrollTo(0,0);document.getElementById('reading').innerHTML='Earlier words fill the lines above the visible reading position. '.repeat(4)+'<br><span id=keptWord>Keep</span> these words visible while the paragraph changes width.'")
            try await camera(compact); try await pause()
            _ = try await js(model, "dispatchEvent(new Event('pointerdown'));scrollTo(0,document.getElementById('keptWord').getBoundingClientRect().top+scrollY)")
            let wordTop = try await measure("top", "keptWord")
            for regions in [[], compact] {
                _ = try await js(model, "window.wordSamples=[];window.wordUntil=performance.now()+900;requestAnimationFrame(function sample(){wordSamples.push(document.getElementById('keptWord').getBoundingClientRect().top);if(performance.now()<wordUntil)requestAnimationFrame(sample)});dispatchEvent(new Event('pointerup'))")
                try await camera(regions); try await pause()
                try check(try await js(model, "wordSamples.every(y=>Math.abs(y-\(wordTop))<1)") as? Bool == true,
                    regions.isEmpty ? "WebKit anchors partly visible words during restoration" : "WebKit anchors partly visible words during sideways refitting")
            }
            try await camera([], enabled: false)
            _ = try await js(model, "document.getElementById('draft').value='unsent native draft';document.getElementById('draft').focus()")
            try await camera(compact); try await pause()
            try check(try await js(model, "document.getElementById('draft').value") as? String == "unsent native draft", "native fitting preserves the form draft")
            try check(try await js(model, "localStorage.length===0 && sessionStorage.length===0") as? Bool == true, "native fitting persists no page content")
            try await load(model, "nested-news")
            let newsWidth = try await measure("width")
            let newsTop = try await measure("top")
            let signTop = try await measure("top", "signin")
            let rail = [["x": Double(model.webView.bounds.width)-84, "y": 0.0, "width": 84.0, "height": 250.0]]
            try await camera(rail); try await pause()
            let fittedSignTop = try await measure("top", "signin")
            let fittedNewsTop = try await measure("top")
            try check((try await measure("right", "signin")) <= model.webView.bounds.width-91 &&
                abs(fittedSignTop-signTop)<1, "WebKit compacts a sticky header row horizontally")
            try check((try await measure("right")) <= model.webView.bounds.width-91 &&
                abs(fittedNewsTop-newsTop)<1, "WebKit fits a deeply nested article inside grid shells")
            _ = try await js(model, "document.getElementById('signin').click()")
            try check(try await js(model, "location.hash") as? String == "#signin-result", "WebKit adapted header link remains functional")
            _ = try await js(model, "document.getElementById('article-link').click()")
            try check(try await js(model, "location.hash") as? String == "#link-result", "WebKit adapted article link remains functional")
            _ = try await js(model, "dispatchEvent(new Event('pointerdown'));scrollTo(0,document.getElementById('following').getBoundingClientRect().top+scrollY-90);dispatchEvent(new Event('pointerup'))")
            let newsReadingTop = try await measure("top", "following")
            try await pause()
            let newsReadingRight = try await measure("right", "following")
            try check(abs((try await measure("top", "following"))-newsReadingTop)<1 &&
                newsReadingRight <= model.webView.bounds.width-91, "WebKit retains reading position while nested paragraphs settle")
            try await camera([]); try await pause()
            try check(try await js(model, "![...document.querySelector('.toolbar').attributes].some(a=>a.name.startsWith('data-duo-camera-'))") as? Bool == true, "WebKit releases header sizing when the island disappears")
            try await camera([], enabled: false)
            try check(abs((try await measure("width"))-newsWidth)<1, "Original Layout restores nested article width")
            _ = try await js(model, "scrollTo(0,document.getElementById('reading').getBoundingClientRect().bottom+scrollY-45)")
            let chromeReadingTop = try await measure("top", "following")
            try await camera(rail); try await pause()
            let chromeReadingRight = try await measure("right", "following")
            try check(abs((try await measure("top", "following"))-chromeReadingTop)<1 && chromeReadingRight <= model.webView.bounds.width-91,
                "WebKit skips text hidden by sticky chrome without rolling back visible text")

            for (label, style) in [("horizontal overflow shell", "document.body.style.overflowX='hidden'"),
                                   ("column flex article", "document.querySelector('main').style.cssText='display:flex;flex-direction:column;padding-bottom:900px'")] {
                try await camera([], enabled: false)
                try await load(model, "settling")
                _ = try await js(model, style)
                let originalWidth = try await measure("width")
                let originalTop = try await measure("top")
                try await camera(rail); try await pause()
                let fittedRight = try await measure("right")
                let fittedTop = try await measure("top")
                try check(fittedRight <= model.webView.bounds.width-91 && abs(fittedTop-originalTop)<1,
                          "WebKit fits body text in a \(label) without vertical movement")
                try await camera([], enabled: false)
                try check(abs((try await measure("width"))-originalWidth)<1,
                          "Original Layout restores text in a \(label)")
            }


        } catch { results.append("FAIL: \(error)") }
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("CameraSettlingChecks.txt")
        try? results.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }
    func asyncJS(_ model: BrowserModel, _ script: String) async throws -> Any {
        try await model.webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: .page)
    }
    func maintainedFilterChecks(_ browser: BrowserModel) async throws {
        try check(await FilterCatalog.shared.awaitMaintainedForTesting(), "maintained protection becomes ready within the bounded preparation window")
        try check(!FilterCatalog.shared.usingFallback && FilterCatalog.shared.ruleCount > 10_000,
                  "bundled maintained sources compile on the deployed iOS runtime without fallback")
        try check(await FilterCatalog.shared.rejectInvalidUpdateForTesting(), "invalid filter update preserves working compilation")
        for (name, passed) in await FilterCatalog.shared.compiledCacheChecksForTesting() { try check(passed, name) }
        try await initialProtectionChecks()
        let source = """
        [Adblock Plus 2.0]
        ||localhost^$third-party,xmlhttprequest
        @@||localhost:8765/probe?allow$xmlhttprequest
        ||127.0.0.1:8765/frame-ad^$subdocument
        ||127.0.0.1:8765/other-only^$other
        ##.synthetic-ad
        example.com#@#.synthetic-ad
        """
        let converted = try FilterListConverter.convert(source)
        ContentBlocking.useTestRuleChunks(try converted.chunks(limit: 2).map { String(decoding: $0, as: UTF8.self) })
        try await load(browser, "upgrades")
        try check(try await asyncJS(browser, "return await fetch('http://localhost:8765/probe?blocked').then(()=>false).catch(()=>true)") as? Bool == true,
                  "maintained converter blocks matching network request in WebKit")
        try check(try await asyncJS(browser, "return await fetch('http://localhost:8765/probe?allow').then(()=>true).catch(()=>false)") as? Bool == true,
                  "maintained converter preserves network exceptions")
        _ = try await js(browser, "var ad=document.createElement('div'); ad.className='synthetic-ad'; ad.textContent='Synthetic advertisement'; document.body.append(ad)")
        try check(try await js(browser, "getComputedStyle(document.querySelector('.synthetic-ad')).display") as? String == "none",
                  "maintained cosmetic filter hides an ad element")
        _ = try await js(browser, "document.querySelector('#kept').value='Keep this site draft'")
        browser.blockAds = false
        try await wait { browser.blockingStatus == "Off for this site" }
        try check(try await js(browser, "document.querySelector('#kept').value") as? String == "Keep this site draft",
                  "site protection switch preserves live draft without reload")
        try check(try await asyncJS(browser, "return await fetch('http://localhost:8765/probe?after-off').then(()=>true).catch(()=>false)") as? Bool == true,
                  "site protection switch removes prior compiled rules")
        browser.blockAds = true
        try await wait { browser.blockingStatus == "Protection on" }
        // The frame rule must not prevent direct top-level navigation to the same URL.
        try await load(browser, "frame-ad?direct")
        try check(try await js(browser, "document.querySelector('#kept') != null") as? Bool == true,
                  "subdocument filter preserves direct top-level navigation")
        try await load(browser, "upgrades")
        let frameAllowed = try await asyncJS(browser, "return await new Promise(resolve => { let f=document.createElement('iframe'); f.onload=()=>resolve(!!f.contentDocument?.querySelector('#kept')); setTimeout(()=>resolve(false),5000); f.src='/frame-control?fresh'; document.body.append(f); })") as? Bool
        try check(frameAllowed == true, "unmatched child document loads normally")
        // Blocked iframe navigations need not emit load/error. Bound the observation and
        // verify server-side non-delivery, rather than waiting forever for an absent event.
        let frameBlocked = try await asyncJS(browser, "const token=crypto.randomUUID(); let f=document.createElement('iframe'); f.src='/frame-ad?token='+token; document.body.append(f); await new Promise(resolve=>setTimeout(resolve,500)); const count=await fetch('/frame-count?token='+token).then(r=>r.text()); return count==='0' && !f.contentDocument?.querySelector('#kept');") as? Bool
        try check(frameBlocked == true, "subdocument filter blocks matching iframe before it reaches the fixture server")
        // Use first-party fetch so the broad third-party probe rule does not apply.
        try check(try await asyncJS(browser, "return await fetch('/other-only?fresh').then(()=>true).catch(()=>false)") as? Bool == true,
                  "other resource filter does not widen to fetch")
        ContentBlocking.useTestRules(nil)
        try await staleBlockingChecks(browser)
    }

    func initialProtectionChecks() async throws {
        let catalog = FilterCatalog.startupTestCatalog()
        var refreshAllowed = true, networkAttempts = 0
        catalog.testDownloadSources = { networkAttempts += 1; throw CocoaError(.fileReadUnknown) }
        let pendingRefresh = Task { await catalog.update(isAllowed: { refreshAllowed }) }
        let browser = BrowserModel(dataStore: .nonPersistent())
        browser.testBlockingRules = { await catalog.rules() }
        defer { catalog.testHoldInitialPreparation = false; browser.close() }
        try await load(browser, "upgrades")
        try await wait { catalog.updating }
        try check(catalog.preparing && catalog.usingFallback && browser.webView.url?.path == "/upgrades",
                  "first navigation proceeds under bundled protection while maintained preparation is held")
        _ = try await js(browser, "document.querySelector('#kept').value='Keep initial draft'")
        let page = browser.webView.url
        refreshAllowed = false
        catalog.testHoldInitialPreparation = false
        try check(await catalog.awaitMaintainedForTesting(), "background preparation promotes baseline to maintained protection")
        await pendingRefresh.value
        try check(networkAttempts == 0 && !catalog.updating, "refresh permission is rechecked after preparation before any source network request")
        _ = try await asyncJS(browser, "return await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))")
        let draft = try await js(browser, "document.querySelector('#kept').value") as? String
        try check(browser.webView.url == page && draft == "Keep initial draft", "automatic maintained promotion preserves the current page and draft")
    }

    func staleBlockingChecks(_ browser: BrowserModel) async throws {
        let store = WKContentRuleListStore.default()!
        let old = try await store.compileContentRuleList(forIdentifier: "DuoBrowser.Synthetic.StaleOld",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"/stale-old"},"action":{"type":"block"}}]"#)!
        let current = try await store.compileContentRuleList(forIdentifier: "DuoBrowser.Synthetic.StaleCurrent",
            encodedContentRuleList: #"[{"trigger":{"url-filter":"/stale-current"},"action":{"type":"block"}}]"#)!
        var delayed: CheckedContinuation<[WKContentRuleList], Never>?
        var calls = 0
        browser.testBlockingRules = {
            calls += 1
            if calls == 1 { return await withCheckedContinuation { delayed = $0 } }
            return [current]
        }
        defer { delayed?.resume(returning: []); browser.testBlockingRules = nil; browser.setAdBlockingEnabled(true) }
        browser.setAdBlockingEnabled(true)
        try await wait { delayed != nil }
        browser.setAdBlockingEnabled(true)
        try await wait {
            (try? await self.asyncJS(browser, "return await fetch('/stale-current').then(()=>false).catch(()=>true)")) as? Bool == true
        }
        delayed?.resume(returning: [old]); delayed = nil
        _ = try await asyncJS(browser, "return await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))")
        try check(try await asyncJS(browser, "return await fetch('/stale-current').then(()=>false).catch(()=>true) && await fetch('/stale-old').then(()=>true).catch(()=>false)") as? Bool == true,
                  "late older filter completion cannot replace the newest protection")
        calls = 0
        browser.setAdBlockingEnabled(true)
        try await wait { delayed != nil }
        browser.setAdBlockingEnabled(false)
        delayed?.resume(returning: [old]); delayed = nil
        _ = try await asyncJS(browser, "return await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)))")
        let disabledAllows = try await asyncJS(browser, "return await fetch('/stale-old').then(()=>true).catch(()=>false)") as? Bool
        try check(browser.blockingStatus == "Off in Settings" && disabledAllows == true,
                  "late filter completion cannot reenable protection after explicit disable")
    }

    func readerBlockingChecks(_ session: BrowserSession) async throws {
        let originalPreference = session.adBlockingEnabled
        let selectedID = session.selectedID
        defer {
            session.adBlockingEnabled = originalPreference
            session.select(selectedID)
            mount(session.selected)
        }
        // Exercise Reader's production loadHTMLString path with real image requests. Unique
        // URLs prevent a previous unblocked response from satisfying a later blocked load.
        for isPrivate in [false, true] {
            for enabled in [false, true] {
                session.adBlockingEnabled = enabled
                let source = session.newTab(privateTab: isPrivate)
                defer { session.close(source.id) }
                try await load(source, "reader-blocking-source")
                let token = UUID().uuidString
                let thirdParty = URL(string: "http://localhost:8765/reader-photo-one.png?reader=\(token)")!
                let firstParty = URL(string: "http://127.0.0.1:8765/reader-photo-two.png?reader=\(token)")!
                let article = ReaderArticle(title: "Reader blocking fixture",
                    source: URL(string: "http://127.0.0.1:8765/reader-blocking-source")!,
                    blocks: [
                        .init(kind: "image", text: "Third-party probe", imageURL: thirdParty, width: 320, height: 180),
                        .init(kind: "image", text: "First-party control", imageURL: firstParty, width: 320, height: 180)
                    ])
                let reader = ReaderRenderer(article: article, sourceBrowser: source)
                defer { reader.close() }
                mount(reader.browser)
                reader.load()
                try await wait(timeout: 30) {
                    (try? await self.js(reader.browser, "document.readyState === 'complete' && document.images.length === 2 && Array.from(document.images).every(image => image.complete)")) as? Bool == true
                }
                let mode = isPrivate ? "private" : "normal"
                let widths = try await js(reader.browser, "Array.from(document.images, image => image.naturalWidth)") as? [Int]
                try check(widths == (enabled ? [0, 320] : [320, 320]),
                          "\(mode) Reader \(enabled ? "blocks" : "allows") third-party image while preserving first-party image with global switch \(enabled ? "on" : "off")")
                try check(reader.browser.isPrivate == isPrivate &&
                          reader.browser.webView.configuration.websiteDataStore === source.webView.configuration.websiteDataStore,
                          "\(mode) Reader image requests retain the source WebKit profile")
            }
        }
    }
    func readerRenderingChecks(_ source: BrowserModel) async throws {
        try await load(source, "reader-article")
        _ = try await js(source, "document.querySelector('#kept').value='Reader preserved draft'")
        source.openReader()
        try await wait { source.readerArticle != nil }
        guard let article = source.readerArticle else { throw NSError(domain: "Missing Reader article", code: 1) }
        try check(article.blocks.map(\.kind) == ["paragraph", "image", "caption", "paragraph", "image", "caption", "paragraph"], "Reader preserves photo and caption order between paragraphs")
        let invalidImage: [String: Any] = ["title": "Unsafe image", "blocks": [
            ["kind": "paragraph", "text": "Visible text"],
            ["kind": "image", "url": "javascript:alert(1)", "alt": "", "width": 320, "height": 180]]]
        try check(ReaderArticle.parse(invalidImage, source: article.source) == nil, "Reader native validation rejects executable image addresses")
        let escaped = ReaderArticle(title: "<script>unsafe</script>", source: article.source,
                                    blocks: [.init(kind: "paragraph", text: "<img src=x onerror=alert(1)>")])
        try check(escaped.readerHTML.contains("&lt;script&gt;") && !escaped.readerHTML.contains("<script>") &&
                  !escaped.readerHTML.contains("<img src=x"), "Reader escapes untrusted title and body markup")
        let reader = ReaderRenderer(article: article, sourceBrowser: source)
        defer { reader.close(); source.cancelReader() }
        mount(reader.browser)
        reader.load()
        try await wait(timeout: 60) {
            (try? await self.js(reader.browser, "document.readyState==='complete' && document.querySelectorAll('article img').length===2")) as? Bool == true
        }
        try check(reader.browser.webView.configuration.websiteDataStore === source.webView.configuration.websiteDataStore,
                  "Reader images use the original WebKit profile")
        try check(!reader.browser.webView.configuration.defaultWebpagePreferences.allowsContentJavaScript,
                  "Reader disables page JavaScript")
        try check(try await js(reader.browser, "(()=>{let s=document.createElement('script');s.textContent='window.readerInjected=true';document.body.appendChild(s);return window.readerInjected!==true})()") as? Bool == true,
                  "Reader blocks injected page-script execution")
        _ = try await js(reader.browser, "document.querySelectorAll('img').forEach(n=>n.loading='eager')")
        try await wait { (try? await self.js(reader.browser, "[...document.images].every(n=>n.complete&&n.naturalWidth===320)")) as? Bool == true }
        try check(true, "Reader displays both synthetic article photographs")
        try check(try await js(reader.browser, "document.querySelector('article').getBoundingClientRect().width >= innerWidth-49") as? Bool == true,
                  "Reader uses full available width without a permanent camera rail")
        let cameraReady = try await reader.browser.webView.evaluateJavaScript("!!globalThis.__duoCamera", in: nil, contentWorld: PageLayoutAdapter.world)
        try check(cameraReady as? Bool == true, "Reader installs the camera fitting engine in its isolated world")
        let paragraphTop = (try await js(reader.browser, "document.querySelector('article p:not(.caption)').getBoundingClientRect().top") as? Double) ?? 0
        let readerWidth = reader.browser.webView.bounds.width
        let readerHeight = reader.browser.webView.bounds.height
        let cameraValue: [String: Any] = ["enabled": true, "width": readerWidth, "height": readerHeight, "reduceMotion": true,
                                         "regions": [["x": readerWidth-84, "y": paragraphTop, "width": 84.0, "height": 100.0]]]
        _ = try await reader.browser.webView.callAsyncJavaScript("globalThis.__duoCamera.update(value)", arguments: ["value": cameraValue], in: nil, contentWorld: PageLayoutAdapter.world)
        try await wait { (try? await self.js(reader.browser, "document.querySelector('article p:not(.caption)').getBoundingClientRect().right <= innerWidth-91")) as? Bool == true }
        try check(true, "Reader text fits beside the camera after settling")
        var clearCamera = cameraValue
        clearCamera["regions"] = [[String: Double]]()
        _ = try await reader.browser.webView.callAsyncJavaScript("globalThis.__duoCamera.update(value)", arguments: ["value": clearCamera], in: nil, contentWorld: PageLayoutAdapter.world)
        try await wait { (try? await self.js(reader.browser, "document.querySelector('article p:not(.caption)').getBoundingClientRect().width >= innerWidth-49")) as? Bool == true }
        try check(true, "Reader restores full paragraph width when the camera no longer overlaps")
        let beforeURL = reader.browser.webView.url
        reader.update(size: 23, spacing: 9, theme: "Sepia")
        try await wait { (try? await self.js(reader.browser, "getComputedStyle(document.querySelector('article p')).fontSize==='23px' && document.documentElement.dataset.theme==='Sepia'")) as? Bool == true }
        try check(reader.browser.webView.url == beforeURL, "Reader typography settings update without reloading")
        reader.close()
        try check(reader.browser.loadedWebView == nil, "Closing Reader releases its temporary web view")
        mount(source)
        try check(try await js(source, "document.querySelector('#kept').value") as? String == "Reader preserved draft", "Photo Reader leaves the original form untouched")
        let privateSource = BrowserModel(isPrivate: true, dataStore: .nonPersistent())
        let privateReader = ReaderRenderer(article: article, sourceBrowser: privateSource)
        try check(privateReader.browser.isPrivate && !privateReader.browser.webView.configuration.websiteDataStore.isPersistent &&
                  privateReader.browser.webView.configuration.websiteDataStore === privateSource.webView.configuration.websiteDataStore,
                  "Private Reader preserves the ephemeral source profile")
        privateReader.close(); privateSource.close()
    }
    func tabRecoveryChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TabRecovery-" + UUID().uuidString)
        let store = BrowserArchiveStore(directory: directory)
        let defaults = UserDefaults(suiteName: "DuoBrowser.TabRecoveryChecks")!
        let session = BrowserSession(storage: defaults, archiveStore: store, dataStore: .nonPersistent())
        defer { session.tabs.forEach { $0.close() }; try? FileManager.default.removeItem(at: directory) }
        let first = session.selected
        try await load(first, "upgrades")
        _ = try await js(first, "document.title = 'Recovery first'")
        let middle = session.newTab()
        try await load(middle, "upgrades")
        let last = session.newTab()
        try await load(last, "upgrades")
        session.select(middle.id)
        _ = try await js(middle, "document.title = 'Recovery middle'")
        try await wait { middle.title == "Recovery middle" }
        _ = try await js(middle, "window.scrollTo(0,150); document.querySelector('#kept').value='Undo draft'")
        session.close(middle.id)
        try check(session.selectedID == last.id, "closing selected middle tab selects its next visible neighbor")
        try check(middle.isRetainedForUndo && middle.presentation.presenter == nil, "retained Undo page has no native presenter")
        try check(try await js(middle, "confirm('Closed synthetic tab')") as? Bool == false, "retained Undo page cannot present a JavaScript dialog")
        _ = try await js(middle, "location.href='/form'")
        try await Task.sleep(for: .milliseconds(150))
        try check(middle.webView.url?.path == "/upgrades", "retained Undo page cannot navigate while closed")
        let record = session.recentlyClosed[0]
        try check(record.title == "Recovery middle" && record.address.contains("upgrades"), "closed tab keeps title and address")
        try check(record.scrollY != nil, "closed tab captures reading position")
        try check(store.load()?.recentlyClosed?.first?.id == record.id, "normal closed tab is durably saved")
        try check(session.closedTabNotice == record.id, "normal close offers immediate Undo")
        try check(session.reopenClosedTab(record.id), "Undo reopens a normal tab")
        try check(!session.reopenClosedTab(record.id), "stale Undo cannot reopen a second copy")
        try check(session.recentlyClosed.isEmpty && session.closedTabNotice == nil, "reopening consumes recovery entry and notice")
        let reopened = session.selected
        try check(reopened === middle, "immediate Undo restores the original live model")
        try check(try await js(reopened, "document.querySelector('#kept').value") as? String == "Undo draft",
                  "immediate Undo preserves unsent form input")
        session.switchAdjacentTab(-1)
        try check(session.selectedID == first.id, "quick switch selects previous visible tab")
        session.select(first.id)
        session.switchAdjacentTab(-1)
        try check(session.selectedID == first.id, "quick switch stops at workspace edge")
        session.close(last.id)
        let normalRecords = session.recentlyClosed.map(\.id)
        let privateTab = session.newTab(privateTab: true)
        try await load(privateTab, "upgrades")
        try check(!session.reopenClosedTab(normalRecords[0]), "normal recovery is unavailable while browsing privately")
        session.close(privateTab.id)
        try check(session.recentlyClosed.map(\.id) == normalRecords, "closing private tab never enters recovery")
        try check(store.load()?.recentlyClosed?.map(\.id) == normalRecords, "archive never acquires private closure")
        let backup = directory.appendingPathComponent("session.backup.json")
        try? FileManager.default.removeItem(at: backup)
        try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: false)
        try check(!session.clearRecentlyClosed() && session.recentlyClosed.map(\.id) == normalRecords, "failed recovery clear reports failure and retains retry rows")
        try FileManager.default.removeItem(at: backup)
        try check(session.clearRecentlyClosed(), "recovery clear can retry after storage failure")
        try check(store.load()?.recentlyClosed?.isEmpty == true, "clear removes persisted recovery")
        session.createWorkspace("Recovery workspace")
        let workspace = session.workspaceID
        let workspaceTab = session.selected
        try await load(workspaceTab, "upgrades")
        session.togglePin(workspaceTab)
        session.close(workspaceTab.id)
        session.releaseClosedTab()
        let workspaceRecord = session.recentlyClosed[0]
        try check(session.reopenClosedTab(workspaceRecord.id) && session.workspaceID == workspace && session.selected.isPinned,
                  "reopening restores workspace and pin")
        session.close(session.selectedID)
        let deletedWorkspaceRecord = session.recentlyClosed[0]
        session.removeWorkspace(workspace)
        try check(session.reopenClosedTab(deletedWorkspaceRecord.id) && session.workspaceID == Workspace.defaultID,
                  "reopening from deleted workspace falls back to Personal")
        session.select(reopened.id)
        reopened.hasRequestedWebsitePermission = true
        session.close(reopened.id)
        try check(reopened.loadedWebView == nil, "pages with a prior website permission request never retain live Undo")
        session.deleteHistory()
        try check(session.recentlyClosed.isEmpty && store.load()?.recentlyClosed?.isEmpty == true,
                  "clearing history also removes closed-page recovery")
    }

    func upgradeChecks() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UpgradeChecks-" + UUID().uuidString)
        let store = BrowserArchiveStore(directory: directory)
        let defaults = UserDefaults(suiteName: "DuoBrowser.UpgradeChecks")!
        defaults.removeObject(forKey: "browser.adBlockingEnabled")
        let session = BrowserSession(storage: defaults, archiveStore: store, dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            try await tabRecoveryChecks()
            try await savedPagesChecks(session)
            let normal = session.selected
            try await load(normal, "upgrades")
            _ = try await js(normal, "document.querySelector('#kept').value='Synthetic draft';window.scrollTo(0,250)")
            let originalView = normal.webView
            let originalScroll = (try await js(normal, "Math.min(250, Math.max(0, document.documentElement.scrollHeight-innerHeight))") as? Double) ?? 0
            try await wait {
                let actual = (try? await self.js(normal, "window.scrollY")) as? Double
                return actual.map { abs($0-originalScroll) < 2 } == true && abs(originalView.scrollView.contentOffset.y-originalScroll) < 2
            }
            normal.openReader()
            try await wait { normal.readerArticle != nil || normal.errorMessage != nil }
            try check(normal.readerArticle?.blocks.count == 3, "Reader extracts article blocks without repeating the title")
            try check(normal.readerArticle?.blocks.contains { $0.text.contains("FORM SECRET") } == false, "Reader excludes form content")
            normal.cancelReader()
            try check(try await js(normal, "document.querySelector('#kept').value") as? String == "Synthetic draft", "Reader preserves original input")
            try check(abs(originalView.scrollView.contentOffset.y - originalScroll) < 2, "Reader preserves original scroll position")
            let pendingSource = normal.restorationURL!
            normal.readerRequest = UUID()
            normal.readerLoading = true
            _ = try await js(normal, "history.replaceState(null,'','#reader-stale')")
            normal.finishReaderExtraction(nil, request: normal.readerRequest, generation: normal.documentGeneration, view: normal.webView, source: pendingSource)
            try check(!normal.readerLoading && normal.readerArticle == nil, "same-document URL change clears stale Reader loading")
            _ = try await js(normal, "history.replaceState(null,'',location.pathname)")
            normal.openReader()
            normal.cancelReader()
            try await Task.sleep(for: .milliseconds(250))
            try check(normal.readerArticle == nil && !normal.readerLoading, "cancelled Reader extraction cannot reopen")
            normal.openReader()
            try await load(normal, "next")
            try await Task.sleep(for: .milliseconds(250))
            try check(normal.readerArticle == nil, "navigation invalidates stale Reader work")
            normal.openReader()
            try await wait { !normal.readerLoading }
            try check(normal.readerArticle == nil && normal.errorMessage != nil, "unsupported page keeps original with Reader explanation")
            try await readerRenderingChecks(normal)
            try await load(normal, "upgrades")
            try await wait { normal.title == "A quieter way to browse" }
            session.togglePin(normal)
            session.createWorkspace("Research")
            let researchID = session.workspaceID
            try check(session.visibleTabs.count == 1 && session.selected.id != normal.id, "new workspace has an independent tab")
            let initialResearch = session.selected
            let sibling = session.newTab()
            session.select(initialResearch.id)
            session.close(initialResearch.id)
            try check(session.selected.id == sibling.id && session.workspaceID == researchID, "closing selected tab prefers its surviving workspace")
            let research = sibling
            try await load(research, "upgrades")
            session.move(normal, to: researchID)
            try check(session.visibleTabs.first?.id == normal.id, "pinned tab sorts before other workspace tabs")
            session.select(research.id)
            research.presentation.makeLinkPreview(URL(string: "http://127.0.0.1:8765/preview")!)?.loadViewIfNeeded()
            guard let peek = research.presentation.previewModelForTesting else { throw NSError(domain: "missing preview", code: 1) }
            mount(peek)
            try await wait {
                guard peek.loadedWebView?.url?.path == "/preview", !peek.webView.isLoading else { return false }
                return (try? await self.js(peek, "!!document.querySelector('#kept')")) as? Bool == true
            }
            _ = try await js(peek, "document.querySelector('#kept').value='Preview draft'")
            let previewView = peek.webView
            session.saveNow()
            try check(store.load()?.session.tabs.contains { $0.address?.contains("/preview") == true } == false, "unkept Peek is absent from archive")
            try check(!session.history.contains { $0.address.contains("/preview") }, "unkept Peek is absent from history")
            try check(research.presentation.promoteLinkPreview(), "native preview promotion succeeds")
            try check(session.selected.webView === previewView, "keeping Peek promotes the same web view")
            try check(try await js(session.selected, "document.querySelector('#kept').value") as? String == "Preview draft", "Peek promotion preserves form state")
            try check(session.selected.workspaceID == researchID, "Peek promotion keeps source workspace")
            let privateTab = session.newTab(privateTab: true)
            try await load(privateTab, "private-upgrade")
            research.presentation.makeLinkPreview(URL(string: "http://127.0.0.1:8765/discarded-preview")!)?.loadViewIfNeeded()
            let discarded = research.presentation.previewModelForTesting
            research.presentation.endLinkPreview()
            try check(research.presentation.previewModelForTesting == nil && discarded?.loadedWebView == nil, "native context preview dismissal tears down its web view")
            session.togglePin(privateTab)
            let privateResults = session.searchResults("", isPrivate: true)
            try check(privateResults.filter { $0.kind == .tab }.allSatisfy { $0.tabID == privateTab.id }, "private unified search excludes normal workspace tabs")
            try check(!privateResults.contains { $0.kind == .history }, "private unified search excludes normal history")
            try check(!session.searchResults("", isPrivate: false).contains { $0.tabID == privateTab.id }, "normal unified search excludes private tabs")
            privateTab.blockAds = false
            session.saveNow()
            let saved = store.load()!
            try check(!saved.session.tabs.contains { $0.id == privateTab.id }, "private pinned tabs never persist")
            try check(saved.sites["127.0.0.1"]?.blockAds != false, "private blocking exception never persists")
            privateTab.presentation.makeLinkPreview(URL(string: "http://127.0.0.1:8765/private-peek")!)?.loadViewIfNeeded()
            let privatePreview = privateTab.presentation.previewModelForTesting
            try check(privatePreview?.isPrivate == true, "private Peek stays in private profile")
            session.closePrivateTabs()
            try check(privateTab.presentation.previewModelForTesting == nil && privatePreview?.loadedWebView == nil, "closing private session destroys its Peek")
            let restored = BrowserSession(storage: UserDefaults(suiteName: "DuoBrowser.UpgradeChecks")!, archiveStore: store, dataStore: .nonPersistent())
            try check(restored.searchResults("quieter", isPrivate: false).contains { $0.kind == .tab && $0.address.hasSuffix("/upgrades") }, "search finds lazily restored tabs by locally saved title")
            try check(restored.workspaces.contains { $0.id == researchID }, "workspace survives cold restoration")
            try check(restored.tabs.first { $0.id == normal.id }?.isPinned == true, "pinned state survives cold restoration")
            try check(restored.tabs.allSatisfy { !$0.isPrivate }, "restoration excludes all private upgrade state")
            restored.tabs.forEach { $0.close() }
            session.removeWorkspace(researchID)
            try check(session.tabs.allSatisfy { $0.workspaceID == Workspace.defaultID }, "workspace removal keeps and relocates tabs")
            mount(normal)
            try await load(normal, "upgrades")
            try check(["Preparing full protection", "Protection on"].contains(normal.blockingStatus), "bundled initial protection attaches before navigation")
            try await maintainedFilterChecks(normal)
            // Substitute only the ad host with a loopback host; all rule flags and production installation remain identical.
            let rulesURL = Bundle.main.url(forResource: "BlockingRules", withExtension: "json")!
            let json = try String(contentsOf: rulesURL, encoding: .utf8)
            let fixtureRules = json.replacingOccurrences(of: "doubleclick\\\\.net", with: "localhost")
            ContentBlocking.useTestRules(fixtureRules)
            try await readerBlockingChecks(session)
            try await load(normal, "upgrades")
            let blocked = try await asyncJS(normal, "return await fetch('http://localhost:8765/probe').then(()=>false).catch(()=>true)") as? Bool
            try check(blocked == true, "native blocker prevents third-party synthetic request")
            normal.blockAds = false
            try await wait { normal.blockingStatus == "Off for this site" && !normal.isLoading }
            try check(try await asyncJS(normal, "return await fetch('http://localhost:8765/probe').then(()=>true).catch(()=>false)") as? Bool == true, "site exception allows synthetic request after reload")
            normal.blockAds = true
            try await wait { normal.blockingStatus == "Protection on" && !normal.isLoading }
            try check(try await asyncJS(normal, "return await fetch('http://localhost:8765/probe').then(()=>false).catch(()=>true)") as? Bool == true, "reenabling protection blocks again")
            _ = try await js(normal, "document.querySelector('#kept').value='Keep blocker draft'")
            session.adBlockingEnabled = false
            try await wait { normal.blockingStatus == "Off in Settings" }
            try check(try await asyncJS(normal, "return await fetch('http://localhost:8765/probe?global-off').then(()=>true).catch(()=>false)") as? Bool == true, "global switch disables blocking without reload")
            try check(try await js(normal, "document.querySelector('#kept').value") as? String == "Keep blocker draft", "global switch preserves form draft")
            try check(defaults.object(forKey: "browser.adBlockingEnabled") as? Bool == false, "global blocking preference persists")
            try check(normal.blockAds, "global switch preserves per-site preference")
            normal.openReader()
            try await wait { normal.readerArticle != nil || normal.errorMessage != nil }
            if let article = normal.readerArticle {
                let reader = ReaderRenderer(article: article, sourceBrowser: normal)
                try check(!reader.browser.adBlockingEnabled, "Reader inherits global blocking preference")
                reader.browser.close()
            } else { try check(false, "Reader must open for global blocking check") }
            normal.cancelReader()
            let globallyOffTab = session.newTab(privateTab: true)
            try await load(globallyOffTab, "global-off-private")
            try check(globallyOffTab.blockingStatus == "Off in Settings", "new private tab honors global switch")
            session.adBlockingEnabled = true
            try await wait { normal.blockingStatus == "Protection on" && globallyOffTab.blockingStatus == "Protection on" }
            try check(try await asyncJS(normal, "return await fetch('http://localhost:8765/probe?global-on').then(()=>false).catch(()=>true)") as? Bool == true, "global reenabling restores actual blocking in existing tabs")
            session.close(globallyOffTab.id)
            session.select(normal.id)
            mount(normal)
            normal.navigate(to: "http://localhost:8765/upgrades")
            try await wait {
                guard normal.webView.url?.host == "localhost", !normal.webView.isLoading else { return false }
                return (try? await self.js(normal, "location.hostname === 'localhost' && document.readyState === 'complete'")) as? Bool == true
            }
            try check(try await asyncJS(normal, "return await fetch('http://localhost:8765/probe').then(()=>true).catch(()=>false)") as? Bool == true, "blocking preserves first-party resources and main document")
            // Isolate navigation-policy state from popup blocking: only the synthetic probe path is blocked.
            let popupRules = #"[{"trigger":{"url-filter":"^http://localhost:8765/probe","load-type":["third-party"]},"action":{"type":"block"}}]"#
            ContentBlocking.useTestRules(popupRules)
            // A target=_blank exception belongs to the child; opener protection must remain installed.
            normal.blockAds = false
            try await wait { normal.blockingStatus == "Off for this site" && !normal.webView.isLoading }
            results.append("STEP: saved localhost blocking exception")
            let opener = session.newTab()
            try await load(opener, "upgrades")
            results.append("STEP: protected opener loaded")
            opener.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
            let beforeChild = session.tabs.count
            _ = try await js(opener, "window.open('http://localhost:8765/upgrades','_blank');true")
            try await wait { session.tabs.count > beforeChild }
            results.append("STEP: excepted popup created")
            let popup = session.selected
            mount(popup)
            try await wait { popup.webView.url?.host == "localhost" && !popup.webView.isLoading }
            try check(popup.webView.configuration.userContentController.userScripts.filter {
                $0.source.hasPrefix("/* DuoBrowser Reddit tap */")
            }.count == 1, "popup inherits exactly one Reddit tap authorization script")
            try check(opener.blockAds && opener.blockingStatus == "Protection on" && !popup.blockAds, "new-window exception leaves opener protection enabled")
            try check(try await asyncJS(opener, "return await fetch('http://localhost:8765/probe').then(()=>false).catch(()=>true)") as? Bool == true, "opener rules remain effective after opening an excepted child")
            session.restoreBlocking(host: "localhost", isPrivate: false)
            try check(!session.blockingExceptions(isPrivate: false).contains("localhost"), "restoring protection removes the saved site exception")
            session.close(popup.id)
            session.close(opener.id)
            let count = session.tabs.count
            let closing = session.newTab(url: URL(string: "http://127.0.0.1:8765/closing")!)
            session.close(closing.id)
            try await Task.sleep(for: .milliseconds(300))
            try check(session.tabs.count == count && closing.loadedWebView == nil, "closing during navigation cannot revive a tab")
            ContentBlocking.useTestRules(nil)
            try check(ReaderArticle.parse(["title": "Bad", "blocks": [["kind": "script", "text": "bad"], ["kind": "paragraph", "text": "ok"]]], source: URL(string: "https://example.com")!) == nil, "Reader rejects malformed extracted blocks")
        } catch { results.append("FAIL: \(error)") }
        let destination = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("UpgradeChecks.txt")
        try? results.joined(separator: "\n").write(to: destination, atomically: true, encoding: .utf8)
    }

    /// Manual UI fixture: isolated synthetic tabs, never the simulator's normal browsing session.
    func overviewDemo() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("OverviewDemo-" + UUID().uuidString)
        let session = BrowserSession(storage: UserDefaults(suiteName: "OverviewDemo-" + UUID().uuidString)!,
            archiveStore: BrowserArchiveStore(directory: directory), dataStore: .nonPersistent())
        let pages = [("Field Notes", "#355c55"), ("Weekend Plans", "#52688c"),
                     ("Reading List", "#885b42"), ("Studio Journal", "#665b78"), ("Garden Guide", "#507145")]
        for (index, page) in pages.enumerated() {
            let model = index == 0 ? session.selected : session.newTab()
            mount(model)
            model.webView.loadHTMLString("""
                <html><head><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
                <title>\(page.0)</title><style>body{margin:0;background:#f4f1e8;color:#252a29;font:18px -apple-system}
                header{padding:60px 28px 36px;background:\(page.1);color:white}main{padding:24px 28px;line-height:1.6}
                h1{font-size:42px;line-height:1.1}input{font:inherit;max-width:90%}</style></head>
                <body><header><p>DUOBROWSER / LOCAL FIXTURE</p><h1>\(page.0)</h1></header><main>
                <h2>A little room to explore.</h2><p>A synthetic page for checking tabs, gestures and smooth transitions.</p>
                <p>Keep your place as you move between pages and open the display.</p><input value="Unsent test note">
                <p style="height:700px">Scroll, return, and continue reading.</p></main></body></html>
                """, baseURL: URL(string: "https://fixture.example/\(index)"))
            try? await wait { !model.webView.isLoading && model.title == page.0 }
            model.captureSnapshot()
            try? await wait { model.snapshot != nil }
        }
        session.select(session.visibleTabs[0].id)
        if ProcessInfo.processInfo.arguments.contains("--recovery-preview") {
            session.close(session.selectedID)
            host.present(UIHostingController(rootView: RecentlyClosedView(session: session)), animated: false)
            return
        }
        let controller = BrowserZoomController(session: session)
        host.addChild(controller)
        controller.view.frame = host.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(controller.view)
        controller.didMove(toParent: host)
    }

    func betaReadinessChecks() throws {
        let card = CGRect(x: 0, y: 0, width: 220, height: 300)
        let rightCamera = CGRect(x: 160, y: 0, width: 60, height: 80)
        try check(TabCardGeometry.closeOrigin(in: card, regions: [], rightToLeft: false) == CGPoint(x: 172, y: 0), "LTR close starts in physical right corner")
        try check(TabCardGeometry.closeOrigin(in: card, regions: [], rightToLeft: true) == .zero, "RTL close starts in physical left corner")
        try check(TabCardGeometry.closeOrigin(in: card, regions: [rightCamera], rightToLeft: false) == .zero, "LTR close relocates into verified clear corner")
        try check(TabCardGeometry.closeOrigin(in: card, regions: [rightCamera], rightToLeft: true) == .zero, "RTL close stays clear of physical right camera")
        let island = CGRect(x: 0, y: 0, width: 220, height: 90)
        let position = TabCardGeometry.closeOrigin(in: card, regions: [island], rightToLeft: false)
        try check(position?.y == 94 && !CGRect(origin: position!, size: CGSize(width: 48, height: 48)).intersects(island), "full-width occlusion moves close below both blocked corners")
        try check(TabCardGeometry.closeOrigin(in: card, regions: [card], rightToLeft: false) == nil, "fully occluded preview suppresses unsafe close target")
        let insets = OverviewRegionView.clearInsets(in: CGRect(x: 0, y: 0, width: 466, height: 678),
                                                   regions: [CGRect(x: 390, y: 30, width: 76, height: 70)])
        try check(insets.right >= 84, "search and accessible-list controls clear side camera using runtime geometry")
        let top = OverviewRegionView.clearInsets(in: card, regions: [island])
        try check(top.top >= 98, "full-width occlusion reserves header/list top clearance")
        let screen = CGRect(x: 0, y: 0, width: 466, height: 678)
        let floatingTop = OverviewRegionView.clearInsets(in: screen, regions: [CGRect(x: 0, y: 30, width: 466, height: 90)])
        try check(floatingTop.top == 128 && floatingTop.left == 0 && floatingTop.right == 0,
                  "inset full-width island reserves top space without collapsing horizontal content")
        let floatingSide = OverviewRegionView.clearInsets(in: screen, regions: [CGRect(x: 30, y: 0, width: 90, height: 678)])
        try check(floatingSide.left == 128 && floatingSide.top == 0 && floatingSide.bottom == 0,
                  "inset full-height island reserves side space without collapsing vertical content")
        let wide = CGRect(x: 0, y: 0, width: 1000, height: 700)
        try check(OverviewRegionView.footerLift(in: wide, height: 104, bottomInset: 34,
                  regions: [CGRect(x: 18, y: 580, width: 70, height: 30)]) == 94,
                  "measured two-row footer clears outer occlusion on wide display")
        try check(OverviewRegionView.footerLift(in: wide, height: 104, bottomInset: 34,
                  regions: [CGRect(x: 400, y: 540, width: 60, height: 40)]) == 134,
                  "accessible footer upper mode row uses actual height and bottom inset")
        try check(OverviewRegionView.footerLift(in: wide, height: 48, bottomInset: 34,
                  regions: [CGRect(x: 400, y: 540, width: 60, height: 40)]) == 0,
                  "single-row footer stays in place when clear")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("WallpaperChecks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.png")
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1800, height: 1000), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1800, height: 1000))
        }
        try image.pngData()!.write(to: source)
        let imported = try WallpaperImport(file: source)
        let resized = UIImage(data: imported.jpeg)!
        try check(max(resized.size.width, resized.size.height) == 1600, "file-representation wallpaper is downsampled before transfer")
        let saved = directory.appendingPathComponent("saved.jpg")
        let store = BrowserWallpaperStore(file: saved)
        let old = store.beginImport()
        store.remove()
        try store.save(imported, token: old)
        try check(store.image == nil && !FileManager.default.fileExists(atPath: saved.path), "remove invalidates an in-flight wallpaper import")
        let prior = store.beginImport(), current = store.beginImport()
        try store.save(imported, token: prior)
        try check(store.image == nil, "superseded wallpaper import cannot overwrite selection")
        try store.save(imported, token: current)
        try check(store.image != nil && FileManager.default.fileExists(atPath: saved.path), "current wallpaper import commits locally")
        store.remove()
        try check(store.image == nil && !FileManager.default.fileExists(atPath: saved.path), "wallpaper removal clears memory and disk")
        let huge = directory.appendingPathComponent("huge.raw")
        FileManager.default.createFile(atPath: huge.path, contents: nil)
        let handle = try FileHandle(forWritingTo: huge); try handle.truncate(atOffset: 41 * 1024 * 1024); try handle.close()
        var rejected = false
        do { _ = try WallpaperImport(file: huge) } catch { rejected = true }
        try check(rejected, "oversized wallpaper file is rejected before image allocation")
    }

    func websiteIconChecks() async throws {
        let icon = WebsiteIconLoader.url(for: "https://example.com:8443/private/page?token=secret#section")
        try check(icon?.absoluteString == "https://example.com:8443/favicon.ico", "icon request strips browsing paths, queries and fragments")
        try check(WebsiteIconLoader.url(for: "https://user:secret@example.com") == nil, "icon request rejects embedded credentials")
        try check(WebsiteIconLoader.redirectAllowed(URL(string: "https://cdn.example.com/icon.png")), "icons allow secure CDN redirects")
        try check(!WebsiteIconLoader.redirectAllowed(URL(string: "http://cdn.example.com/icon.png")), "icons reject insecure redirects")
        try check(WebsiteIconLoader.decode(Data("not an image".utf8)) == nil, "invalid favicon produces safe fallback")
        try check(WebsiteIconLoader.decode(Data(repeating: 0, count: WebsiteIconLoader.maximumBytes + 1)) == nil, "oversized favicon is rejected")
        let html = """
        <link rel='icon' href='/small.ico' sizes='16x16'>
        <link href='//cdn.example.com/touch.png?a=1&amp;b=2' sizes='192x192' rel='apple-touch-icon'>
        <link rel='icon' sizes='512x512' href='http://downgrade.example/icon.png'>
        <link rel='icon' sizes='512x512' href='https://user:secret@example.com/icon.png'>
        <link rel='icon' sizes='512x512' href='data:image/png;base64,invalid'>
        <link rel='icon' sizes='512x512' type='image/svg+xml' href='/icon.svg'>
        """
        let candidates = WebsiteIconLoader.candidates(in: html, base: URL(string: "https://example.com/")!)
        try check(candidates.count == 2, "icon discovery rejects credentials, downgrades, data URLs and unsupported vectors")
        try check(candidates.first?.absoluteString == "https://cdn.example.com/touch.png?a=1&b=2", "Retina touch icon ranks above tiny favicon and decodes HTML ampersands")
        try check(candidates.last?.absoluteString == "https://example.com/small.ico", "relative icon resolves at origin")
        let redirected = WebsiteIconLoader.candidates(in: "<link rel='apple-touch-icon' href='assets/touch.png'>",
                                                      base: URL(string: "https://www.example.com/en/")!)
        try check(redirected.first?.absoluteString == "https://www.example.com/en/assets/touch.png",
                  "relative Retina icon preserves redirected document host and directory")
        let cookie = HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "IconIsolation", .value: "synthetic"])!
        HTTPCookieStorage.shared.setCookie(cookie)
        defer { HTTPCookieStorage.shared.deleteCookie(cookie) }
        let store = WebsiteIconStore()
        let loaded = await store.image(for: "http://127.0.0.1:8765/ignored?secret=not-sent")
        try check(loaded?.cgImage?.width == 144 && loaded?.cgImage?.height == 144, "Retina touch icon wins over 16-pixel favicon without shared cookies or credentials")
        try check(loaded.map { max($0.size.width, $0.size.height) <= 144 } == true, "favicon decode has bounded pixel dimensions")
        let cached = await store.image(for: "http://127.0.0.1:8765/other-page")
        try check(cached === loaded, "same-origin shortcuts reuse the in-memory icon")
        store.clear()
        let fresh = await store.image(for: "http://127.0.0.1:8765/other-page")
        try check(fresh != nil && fresh !== loaded, "clearing icons discards cached images")
        store.clear()
    }

    func addressCompletionChecks() throws {
        var query = ""
        var submitted = ""
        let address = AddressField(text: Binding(get: { query }, set: { query = $0 }),
                                   submit: { submitted = $0 }, cancel: {})
        let coordinator = address.makeCoordinator()
        let field = UITextField(frame: CGRect(x: 0, y: 0, width: 320, height: 52))
        field.delegate = coordinator
        field.addTarget(coordinator, action: #selector(AddressField.Coordinator.changed(_:)), for: .editingChanged)
        host.view.addSubview(field)
        defer { field.resignFirstResponder(); field.removeFromSuperview() }
        field.becomeFirstResponder()
        field.insertText("g")
        try check(query == "g" && field.text == "www.google.com", "single letter completes domain while predictions retain keyword")
        try check(field.selectedTextRange.map { field.text(in: $0) } == "oogle.com", "only remaining domain suffix is selected")
        coordinator.synchronize(field, text: query)
        try check(field.text == "www.google.com", "SwiftUI updates preserve inline completion")
        field.insertText("o")
        try check(query == "go" && field.text == "www.google.com", "typing replaces completion and extends keyword")
        field.deleteBackward()
        try check(query == "go" && field.text == "go", "backspace removes completion without immediately restoring it (query=\(query), field=\(field.text ?? ""))")
        field.insertText(" garden")
        try check(query == "go garden" && field.text == query, "multiword input remains a keyword search")
        _ = coordinator.textFieldShouldReturn(field)
        try check(submitted == "go garden", "keyword return submits actual query")
        query = ""
        coordinator.synchronize(field, text: query)
        field.insertText("g")
        _ = coordinator.textFieldShouldReturn(field)
        try check(submitted == "www.google.com", "return accepts inline website completion")
    }

    func setupChecks() async throws {
        let suite = "DuoBrowser.SetupTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = BrowserArchiveStore(directory: directory)
        let session = BrowserSession(storage: defaults, archiveStore: store, dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let transport = SetupFixtureTransport()
        let model = BrowserSetupModel(storage: defaults, transferEnabled: true, transport: transport)
        try check(!model.completed && model.step == .welcome, "new install begins with welcome")
        model.next(); model.choices.history = false
        let restored = BrowserSetupModel(storage: defaults)
        try check(restored.step == .transfer && !restored.choices.history, "interrupted setup restores step and category choices")
        let invalid = NSUserActivity(activityType: BEBrowserDataImportManager.userActivityType)
        try check(!model.receive(invalid, isPrivate: false), "missing transfer token rejected")
        let token = UUID()
        let activity = NSUserActivity(activityType: BEBrowserDataImportManager.userActivityType)
        activity.userInfo = [BEBrowserDataImportManager.importTokenUserInfoKey: token]
        try check(!model.receive(activity, isPrivate: true), "private session rejects incoming transfer")
        let disabled = BrowserSetupModel(storage: defaults, transferEnabled: false)
        try check(!disabled.receive(activity, isPrivate: false), "unentitled build rejects incoming transfer")
        try check(model.receive(activity, isPrivate: false), "valid system activity starts direct import")
        try await wait { transport.continuation != nil }
        transport.continuation?.yield(BEBrowserDataBookmark(isFolder: false, title: "Synthetic bookmark", identifier: "bookmark", url: URL(string: "https://example.com/import"), parentIdentifier: nil))
        transport.continuation?.yield(BEBrowserDataReadingListItem(title: "Read", url: URL(string: "https://example.com/read")!, dateOfLastVisit: nil))
        transport.continuation?.finish()
        try await wait { model.state == .review }
        try check(session.bookmarks.isEmpty && store.load()?.bookmarks.isEmpty != false, "received data does not save before review")
        try check(model.batch?.readingList.count == 1, "undated Reading List item is retained")
        try check(!model.receive(activity, isPrivate: false), "replayed token cannot replace review")
        model.save(into: session)
        try check(model.state == .saved && session.bookmarks.count == 1 && session.readingList.count == 1, "confirmed selection commits supported data")
        try check(store.load()?.readingList?.count == 1, "confirmed transfer survives archive reload")
        #if !targetEnvironment(simulator)
        // The simulator omits NSFileProtectionKey; verify the class on a device.
        guard session.saveNow() else { throw BrowserImportError.saveFailed }
        for name in ["session.json", "session.backup.json"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(name).path)
            try check(attributes[.protectionKey] as? String == FileProtectionType.completeUntilFirstUserAuthentication.rawValue,
                "atomic archive write applies protection to \(name): \(String(describing: attributes[.protectionKey]))")
        }
        #endif
        model.save(into: session)
        try check(session.bookmarks.count == 1, "double save cannot duplicate data")
        model.finish()
        try check(BrowserSetupModel(storage: defaults).completed, "completed setup stays completed after relaunch")
        model.reopen()
        try check(model.step == .welcome, "setup can reopen from Page options")
        activity.userInfo = [BEBrowserDataImportManager.importTokenUserInfoKey: UUID()]
        transport.continuation = nil
        try check(model.receive(activity, isPrivate: false), "new token begins a new transfer")
        try await wait { transport.continuation != nil }
        let stale = transport.continuation
        model.cancel()
        stale?.yield(BEBrowserDataBookmark(isFolder: false, title: "Late", identifier: "late", url: URL(string: "https://example.com/late"), parentIdentifier: nil))
        stale?.finish()
        try await Task.sleep(for: .milliseconds(100))
        try check(model.state == .idle && model.batch == nil && session.bookmarks.count == 1, "canceled stream cannot repopulate review or save late items")
        try check(!model.receive(activity, isPrivate: false), "late return after cancel rejected")
        model.reopen()
        activity.userInfo = [BEBrowserDataImportManager.importTokenUserInfoKey: UUID()]
        transport.continuation = nil
        try check(model.receive(activity, isPrivate: false), "a new import can retry after cancellation")
        try await wait { transport.continuation != nil }
        transport.continuation?.yield(BEBrowserDataBookmark(isFolder: false, title: "Partial", identifier: "partial", url: URL(string: "https://example.com/partial"), parentIdentifier: nil))
        transport.continuation?.finish(throwing: CocoaError(.fileReadUnknown))
        try await wait { model.state == .failed }
        try check(model.batch == nil && session.bookmarks.count == 1, "failed streams discard partial data")
        model.reopen()
        if let scene = host.view.window?.windowScene {
            model.request(scene: scene)
            try await wait { transport.requestContinuation != nil }
            model.cancel()
            transport.requestContinuation?.resume(returning: true)
            transport.requestContinuation = nil
            try await Task.sleep(for: .milliseconds(100))
            try check(model.state == .idle && model.message == nil, "stale request completion cannot overwrite cancellation")
            model.request(scene: scene)
            try await wait { transport.requestContinuation != nil }
            transport.requestContinuation?.resume(returning: true)
            transport.requestContinuation = nil
            try await wait { model.state == .failed }
            try check(model.batch == nil, "unexpected files response fails without opening a file picker")
        } else { throw NSError(domain: "setup harness needs window scene", code: 1) }
        var incoming = BrowserImportBatch()
        try incoming.addPage(address: "https://example.com/history", title: "History", date: Date(), isHistory: true)
        try model.reviewForTesting(incoming)
        model.choices = ImportChoices(bookmarks: false, favorites: false, history: true, readingList: false)
        // Make the destination unwritable without changing permissions on any real browsing files.
        let blocked = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: blocked)
        let failing = BrowserSession(storage: defaults, archiveStore: BrowserArchiveStore(directory: blocked), dataStore: .nonPersistent())
        defer { failing.tabs.forEach { $0.close() } }
        model.save(into: failing)
        try check(model.state == .review && failing.history.isEmpty, "failed durable save preserves review and rolls back library")
        try check(model.message == BrowserImportError.saveFailed.localizedDescription, "failed durable save supplies recovery instructions during review")
        model.cancel()
        try check(model.batch == nil && model.folders.isEmpty, "discard clears all staged browsing data")
    }

    func setupPreview() throws {
        let defaults = UserDefaults(suiteName: "DuoBrowser.SetupPreview")!
        let session = BrowserSession(storage: defaults,
            archiveStore: BrowserArchiveStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("SetupPreview-" + UUID().uuidString)),
            dataStore: .nonPersistent())
        let model = BrowserSetupModel(storage: defaults, transferEnabled: true, transport: SetupFixtureTransport())
        model.choices = ImportChoices()
        var batch = BrowserImportBatch()
        try batch.addBookmark(.init(identifier: "favorites", parent: nil, title: "Favorites", address: nil, isFolder: true))
        try batch.addBookmark(.init(identifier: "book", parent: "favorites", title: "Synthetic Favorite", address: "https://example.com/favorite", isFolder: false))
        try batch.addBookmark(.init(identifier: "folder", parent: nil, title: "Research", address: nil, isFolder: true))
        try batch.addBookmark(.init(identifier: "ordinary", parent: "folder", title: "Synthetic Bookmark", address: "https://example.com/bookmark", isFolder: false))
        try batch.addPage(address: "https://example.com/history", title: "Synthetic Visit", date: Date(timeIntervalSince1970: 1234), isHistory: true)
        try batch.addPage(address: "https://example.com/read", title: "Synthetic Reading List", date: Date(timeIntervalSince1970: 1234), isHistory: false)
        try model.reviewForTesting(batch)
        model.step = .transfer
        let preview = UIHostingController(rootView: BrowserSetup(session: session, model: model))
        host.present(preview, animated: false)
    }

    func redditChecks() async throws {
        let name = "DuoBrowser.RedditChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let routing = RedditLinkRouting(storage: defaults)
        let url = URL(string: "https://www.reddit.com/r/swift/comments/abc123/title/def456/?context=3")!
        var opened: [URL] = []
        var outcome: Bool?
        var choice: RedditLinkPreference? = .apollo
        var prompts = 0
        var current = true
        routing.canOpen = { _ in true }
        routing.open = { target, completion in opened.append(target); completion(true) }
        let choose: ([RedditLinkPreference], String, @escaping (RedditLinkPreference?) -> Void) -> Void = { choices, _, finish in
            prompts += 1
            precondition(choices == [.apollo, .browser])
            finish(choice)
        }
        func route(privateTab: Bool = false) {
            outcome = nil
            routing.route(url, isPrivate: privateTab, isCurrent: { current }, choose: choose) { outcome = $0 }
        }
        try check(routing.preference == .chooseOnce, "fresh install asks once")
        route()
        try check(prompts == 1 && outcome == true && opened.count == 1, "first choice opens Apollo and cancels web request")
        try check(RedditLinkRouting(storage: defaults).preference == .apollo, "chosen app survives relaunch")
        route()
        try check(prompts == 1 && opened.count == 2, "remembered app skips subsequent prompt")
        route(privateTab: true)
        try check(prompts == 2 && opened.count == 3, "private tab still asks before handoff")
        routing.preference = .chooseOnce
        choice = .browser
        route(privateTab: true)
        try check(outcome == false && routing.preference == .chooseOnce, "private browser choice does not persist")
        route()
        try check(outcome == false && routing.preference == .browser, "browser choice is remembered")
        let promptCount = prompts
        route()
        try check(prompts == promptCount && outcome == false, "browser preference never launches app")
        routing.preference = .askEveryTime
        choice = .apollo
        route(); route()
        try check(prompts == promptCount + 2 && routing.preference == .askEveryTime, "ask every time stays enabled")
        choice = nil
        route()
        try check(outcome == true, "cancel keeps original page")
        routing.canOpen = { _ in false }
        route()
        try check(outcome == false, "missing app falls back to original request")
        routing.canOpen = { _ in true }
        routing.preference = .apollo
        routing.open = { _, finish in finish(false) }
        route()
        try check(outcome == false, "system launch failure falls back to original request")
        var finishOpen: (@MainActor @Sendable (Bool) -> Void)?
        routing.open = { _, finish in finishOpen = finish }
        route()
        current = false
        finishOpen?(false)
        try check(outcome == true, "late launch failure cannot navigate a stale tab")
        current = true
        routing.preference = .chooseOnce
        var finishChoice: ((RedditLinkPreference?) -> Void)?
        routing.route(url, isPrivate: false, isCurrent: { current }, choose: { _, _, finish in finishChoice = finish }) { outcome = $0 }
        current = false
        finishChoice?(.apollo)
        try check(outcome == true && routing.preference == .chooseOnce, "stale choice neither opens nor saves")
        try check(defaults.dictionaryRepresentation().values.allSatisfy { !(String(describing: $0).contains("abc123")) }, "preferences never store destination URLs")

        let model = BrowserModel(dataStore: .nonPersistent())
        defer { model.close() }
        model.redditLinks = routing
        // The native route test isolates gesture authorization; the trusted listener is tested separately below and in Playwright.
        model.testRedditTapAuthorization = { _ in true }
        routing.preference = .apollo
        routing.open = { target, finish in opened.append(target); finish(true) }
        try await load(model, "reddit-routing")
        let page = model.webView.url
        let initialCount = opened.count
        _ = try await js(model, "document.querySelector('#kept').value='Keep this draft'; window.scrollTo(0,200); true")
        try await wait { abs(((try? await self.js(model, "window.scrollY")) as? Double ?? 0) - 200) < 2 }
        let position = try await js(model, "window.scrollY") as? Double
        // Wait for WebKit's compositor to commit the synthetic scroll before simulating
        // another interaction. Large cosmetic stylesheets can otherwise expose a DOM/native race.
        _ = try await asyncJS(model, "return await new Promise(resolve => requestAnimationFrame(()=>requestAnimationFrame(()=>resolve(window.scrollY))))")
        try await wait { abs(model.webView.scrollView.contentOffset.y - (position ?? 0)) < 2 }
        _ = try await js(model, "var a=document.createElement('a');a.href='https://www.google.com/url?q=https%3A%2F%2Fwww.reddit.com%2Fr%2Fswift%2Fcomments%2Fabc123%2Ftitle%2Fdef456%2F%3Fcontext%3D3';document.body.append(a);a.click();true")
        try await wait { opened.count == initialCount + 1 }
        try check(opened.last == RedditLinks.apolloURL(url), "real WebKit link action unwraps Google and opens exact comment")
        try check(model.webView.url == page, "successful handoff preserves source URL")
        try check(try await js(model, "document.querySelector('#kept').value") as? String == "Keep this draft", "handoff preserves form draft")
        let afterHandoff = try await js(model, "window.scrollY") as? Double
        if abs((afterHandoff ?? -1000) - (position ?? 1000)) >= 2 {
            let layout = try await js(model, "JSON.stringify({height:document.documentElement.scrollHeight,viewport:innerHeight,main:getComputedStyle(document.querySelector('main')).display,focus:document.activeElement?.tagName})")
            results.append("LAYOUT: synthetic handoff \(layout)")
        }
        try check(abs((afterHandoff ?? -1000) - (position ?? 1000)) < 2,
                  "handoff preserves scroll position (\(position ?? -1) → \(afterHandoff ?? -1))")
        _ = try await js(model, "a.target='_blank';a.click();true")
        try await wait { opened.count == initialCount + 2 }
        try check(model.webView.url == page, "new-window handoff leaves source intact without popup")
        routing.preference = .chooseOnce
        _ = try await js(model, "a.target='';a.click();true")
        try await wait { self.host.presentedViewController is UIAlertController }
        let alert = host.presentedViewController as! UIAlertController
        try check(alert.actions.map(\.title) == ["Apollo Reborn", "DuoBrowser", "Cancel"], "native chooser presents installed app, browser and cancel")
        model.presentation.cancel()
        try await wait { self.host.presentedViewController == nil }
        try check(model.webView.url == page && routing.preference == .chooseOnce, "dismissing chooser leaves page and preference unchanged")
        let schemes = Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String]
        try check(schemes == ["apollo"], "production bundle declares only the verified app query scheme")
        _ = try await js(model, "a.addEventListener('click',e=>e.preventDefault());a.click();true")
        let trusted = try await model.webView.callAsyncJavaScript("return globalThis.__duoRedditTap.consume(url);",
            arguments: ["url": "https://www.google.com/url?q=https%3A%2F%2Fwww.reddit.com%2Fr%2Fswift%2Fcomments%2Fabc123%2Ftitle%2Fdef456%2F%3Fcontext%3D3"],
            in: nil, contentWorld: BrowserModel.redditTapWorld)
        try check(trusted as? Bool == false, "programmatic click cannot mint trusted authorization (\(String(describing: trusted)))")
        try check(try await js(model, "typeof globalThis.__duoRedditTap") as? String == "undefined", "page world cannot access isolated click authorization")
        var consumedLinks: [URL] = []
        model.testRedditTapAuthorization = { destination in
            consumedLinks.append(destination)
            return true
        }
        routing.preference = .apollo
        let openedBeforeIneligibleLinks = opened.count
        _ = try await js(model, "var frame=document.createElement('iframe');frame.name='routingFixture';frame.id='routingFixture';document.body.append(frame);true")
        try await wait {
            (try? await self.js(model, "document.querySelector('#routingFixture').contentDocument.readyState === 'complete'")) as? Bool == true
        }
        _ = try await js(model, "var frameLink=document.createElement('a');frameLink.href='http://127.0.0.1:8765/reddit-frame-target';frameLink.target='routingFixture';document.body.append(frameLink);frameLink.click();true")
        try await wait {
            (try? await self.js(model, "document.querySelector('#routingFixture').contentWindow.location.pathname === '/reddit-frame-target' && document.querySelector('#routingFixture').contentDocument.readyState === 'complete'")) as? Bool == true
        }
        try check(consumedLinks.map(\.path) == ["/reddit-frame-target"], "iframe-targeted link consumes authorization before eligibility checks")
        try check(model.webView.url == page && opened.count == openedBeforeIneligibleLinks,
                  "ineligible iframe link loads its original frame without app launch or main-page navigation")
        _ = try await js(model, "var localLink=document.createElement('a');localLink.href='http://127.0.0.1:8765/reddit-main-target';document.body.append(localLink);localLink.click();true")
        try await wait { model.webView.url?.path == "/reddit-main-target" && !model.webView.isLoading }
        try check(consumedLinks.map(\.path) == ["/reddit-frame-target", "/reddit-main-target"],
                  "non-Reddit main-frame link also consumes authorization")
        let navigatedPath = try await js(model, "location.pathname") as? String
        try check(opened.count == openedBeforeIneligibleLinks && navigatedPath == "/reddit-main-target",
                  "non-Reddit link preserves original web navigation without app launch")
    }

    func downloadsChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DownloadChecks-" + UUID().uuidString)
        let defaults = UserDefaults(suiteName: "DuoBrowser.DownloadChecks")!
        defaults.removePersistentDomain(forName: "DuoBrowser.DownloadChecks")
        let profile = WKWebsiteDataStore.nonPersistent()
        let session = BrowserSession(storage: defaults, archiveStore: BrowserArchiveStore(directory: directory), dataStore: profile)
        let manager = session.normalDownloads
        defer {
            manager.cancelAll(); session.closePrivateTabs(); session.tabs.forEach { $0.close() }
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: "DuoBrowser.DownloadChecks")
        }
        let tab = session.selected
        try await load(tab, "")
        let cookie = HTTPCookie(properties: [.domain: "127.0.0.1", .path: "/", .name: "duo-download", .value: "synthetic"])!
        await profile.httpCookieStore.setCookie(cookie)
        _ = try await js(tab, "document.querySelector('#kept').value='Preserved download draft'")
        _ = try await js(tab, "document.querySelector('a[download]').click()")
        try await wait(timeout: 30) { manager.completedCount == 1 }
        let first = manager.items[0]
        try check(first.name == "browser-fixture.txt", "real navigation download receives the server filename")
        try check(first.file != nil && first.received > 0, "WebKit download persists with its byte size")
        try check(host.presentedViewController == nil, "completion does not interrupt browsing with an exporter")
        let originalFile = first.file!
        let restored = BrowserDownloads(isPrivate: false, dataStore: profile, directory: manager.store.directory)
        try check(restored.items.count == 1 && restored.items[0].file == originalFile, "normal completed download restores from disk")
        try check(try String(contentsOf: originalFile, encoding: .utf8) == "Synthetic browser download.\n", "restored file retains its contents")
        let exporter = UIDocumentPickerViewController(forExporting: [originalFile], asCopy: true)
        host.present(exporter, animated: false)
        try await wait { host.presentedViewController === exporter && !exporter.isBeingPresented }
        exporter.dismiss(animated: false)
        try await wait { host.presentedViewController == nil }
        try check(FileManager.default.fileExists(atPath: originalFile.path) && first.file == originalFile, "dismissing Files export keeps the downloaded file")
        let draft = try await js(tab, "document.querySelector('#kept').value") as? String
        try check(draft == "Preserved download draft" && tab.webView.url?.path == "/", "download and export dismissal preserve the source page and draft")

        let directTab = session.newTab()
        mount(directTab)
        directTab.navigate(to: "http://127.0.0.1:8765/download")
        try await wait(timeout: 30) { manager.completedCount == 2 }
        let attachment = manager.items[0]
        let noDownloadError = tab.errorMessage == nil && directTab.errorMessage == nil
        directTab.webView(directTab.webView, didFailProvisionalNavigation: nil,
            withError: NSError(domain: "WebKitErrorDomain", code: 102))
        try check(noDownloadError && directTab.errorMessage != nil, "download conversion suppresses only its expected policy interruption, not unrelated failures")
        directTab.errorMessage = nil
        try check(attachment.name == "browser-fixture.txt", "direct attachment navigation downloads even when WebKit can display its MIME type")
        try await load(directTab, "download-inline")
        try check(manager.items.count == 2 && directTab.webView.url?.path == "/download-inline", "inline disposition remains a webpage without creating a download")
        manager.remove(attachment); session.close(directTab.id); session.releaseClosedTab(); mount(tab)

        let secondTab = session.newTab()
        try await load(secondTab, "")
        _ = try await js(secondTab, "const a=document.createElement('a');a.href='/download-slow';a.download='';document.body.append(a);a.click()")
        try await wait { manager.items.count == 2 && manager.items[0].isDownloading }
        let second = manager.items[0]
        try await wait { second.received > 0 && second.expected > second.received }
        try check(second.received > 0, "native WebKit progress exposes actual transferred bytes")
        session.close(secondTab.id)
        mount(session.selected)
        try check(manager.activeCount == 1, "closing originating normal tab leaves the session transfer active")
        do { try await wait(timeout: 30) { !second.isDownloading } }
        catch {
            results.append("TRANSFER: received=\(second.received), expected=\(second.expected), state=\(second.state.rawValue), fileBytes=\((try? second.file?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1)")
            throw error
        }
        try check(second.state == .completed, "closed-tab download completed: \(second.state.rawValue), \(second.message ?? "no error")")
        try check(try String(contentsOf: second.file!, encoding: .utf8).hasPrefix("Authenticated synthetic"), "transfer retains its original WebKit cookie profile")

        let retryTab = session.selected
        func start(_ path: String) async {
            let request = URLRequest(url: URL(string: "http://127.0.0.1:8765/" + path)!)
            await withCheckedContinuation { continuation in
                retryTab.webView.startDownload(using: request) { download in
                    manager.add(download, owner: retryTab.id, browser: retryTab); continuation.resume()
                }
            }
        }
        await start("download-slow?cancel=1")
        try await wait { manager.items[0].received > 0 || !manager.items[0].isDownloading }
        let canceled = manager.items[0]
        try check(canceled.isDownloading, "first cancel fixture remains active: \(canceled.state.rawValue), \(canceled.message ?? "no error")")
        await start("download-slow?cancel=2")
        try await wait { manager.activeCount == 2 || !canceled.isDownloading || !manager.items[0].isDownloading }
        let independent = manager.items[0]
        try check(manager.activeCount == 2, "two independent transfers overlap: \(manager.activeCount), \(independent.message ?? "no error")")
        manager.cancel(canceled)
        try check(!canceled.isDownloading && canceled.state == .canceled && canceled.canRetry, "individual cancel retains a safe GET retry")
        try check(manager.activeCount == 1 && independent.isDownloading, "cancel affects only its own transfer")
        manager.retry(canceled)
        try await wait(timeout: 30) { canceled.state == .completed && independent.state == .completed }
        try check(try String(contentsOf: canceled.file!, encoding: .utf8).hasPrefix("Authenticated synthetic"), "GET retry uses the same WebKit cookie profile")
        try check(canceled.id != independent.id && canceled.file != independent.file, "identical filenames remain separate downloads")

        await start("download-retry?case=" + UUID().uuidString)
        let failed = manager.items[0]
        try await wait(timeout: 30) { failed.state == .failed && !failed.isDownloading }
        try check(failed.canRetry, "network failure offers a bounded WebKit retry")
        manager.retry(failed)
        try await wait(timeout: 30) { failed.state == .completed && !failed.isDownloading }
        try check(failed.file != nil, "retry completes after a synthetic interrupted response")

        await start("download-chunked")
        let unknownLength = manager.items[0]
        try await wait { unknownLength.received > 0 && unknownLength.isDownloading }
        try check(unknownLength.expected == 0, "unknown-length transfer still reports actual bytes without inventing a percentage")
        try await wait(timeout: 30) { unknownLength.state == .completed }

        await start("download-too-large")
        let oversized = manager.items[0]
        try await wait { oversized.state == .failed && !oversized.isDownloading }
        try check(oversized.file == nil && oversized.message?.contains("1 GB") == true,
                  "oversized response is rejected before allocating a destination")

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            retryTab.webView.startDownload(using: URLRequest(url: URL(string: "https://127.0.0.1:8443/download")!)) { download in
                manager.add(download, owner: retryTab.id, browser: retryTab); continuation.resume()
            }
        }
        let untrusted = manager.items[0]
        try await wait(timeout: 30) { untrusted.state == .failed && !untrusted.isDownloading }
        try check(untrusted.file == nil, "download uses platform certificate validation and rejects untrusted TLS")

        var post = URLRequest(url: URL(string: "http://127.0.0.1:8765/download-post")!)
        post.httpMethod = "POST"; post.httpBody = Data("synthetic=download".utf8)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            retryTab.webView.startDownload(using: post) { download in
                manager.add(download, owner: retryTab.id, browser: retryTab); continuation.resume()
            }
        }
        let postResult = manager.items[0]
        try await wait(timeout: 30) { postResult.state == .failed && !postResult.isDownloading }
        try check(!postResult.canRetry && postResult.request == nil && postResult.resumeData == nil,
                  "failed POST download never offers a potentially mutating replay")

        await start("download-slow?stale=1")
        let stale = manager.items[0]
        manager.cancel(stale); manager.retry(stale); manager.remove(stale)
        try await Task.sleep(for: .milliseconds(250))
        try check(!manager.items.contains(where: { $0.id == stale.id }), "removed retry cannot reappear after its asynchronous callback")
        try check(!FileManager.default.fileExists(atPath: manager.store.directory.appendingPathComponent(stale.id.uuidString).path), "stale retry does not recreate deleted download files")

        func retryThenCloseSource(afterProgress: Bool) async throws {
            let source = session.newTab()
            try await load(source, "")
            let request = URLRequest(url: URL(string: "http://127.0.0.1:8765/download-slow?retry-close=\(afterProgress)")!)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                source.webView.startDownload(using: request) { download in
                    manager.add(download, owner: source.id, source: source.webView, browser: source); continuation.resume()
                }
            }
            let restarted = manager.items[0]
            try await wait { restarted.received > 0 && restarted.isDownloading }
            manager.cancel(restarted)
            // Exercise the authenticated GET restart path deterministically, not an optional resume token.
            restarted.resumeData = nil
            manager.retry(restarted)
            try check(manager.hasWork(for: source.id), "GET retry owns its source while WebKit creates the transfer (afterProgress=\(afterProgress))")
            if afterProgress { try await wait { restarted.received > 0 && restarted.isDownloading } }
            session.close(source.id)
            session.releaseClosedTab() // Expire Undo now: this must work without its eight-second retention.
            mount(session.selected)
            try await wait(timeout: 30) { !restarted.isDownloading }
            let content = try restarted.file.map { try String(contentsOf: $0, encoding: .utf8) }
            try check(restarted.state == .completed && content?.hasPrefix("Authenticated synthetic") == true,
                      "authenticated GET retry completes after source closure (afterProgress=\(afterProgress))")
        }
        try await retryThenCloseSource(afterProgress: false)
        try await retryThenCloseSource(afterProgress: true)

        func rejectReplacedDocumentRetry(reload: Bool) async throws {
            let source = session.newTab()
            try await load(source, "")
            let originalURL = source.webView.url, originalDocument = source.documentGeneration
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                source.webView.startDownload(using: URLRequest(url: URL(string: "http://127.0.0.1:8765/download-slow?stale-document=\(reload)")!)) { download in
                    manager.add(download, owner: source.id, source: source.webView, browser: source); continuation.resume()
                }
            }
            let staleDocument = manager.items[0]
            try await wait { staleDocument.received > 0 && staleDocument.isDownloading }
            manager.cancel(staleDocument)
            if reload {
                source.webView.reload()
                try await wait { source.documentGeneration != originalDocument && !source.webView.isLoading }
            } else {
                try await load(source, "next")
                try await load(source, "")
            }
            // Force the no-token GET path even if WebKit supplied an optional cancellation token.
            staleDocument.resumeData = nil; staleDocument.canRetry = true
            let activeBefore = manager.activeCount
            manager.retry(staleDocument)
            try check(source.webView.url == originalURL && source.documentGeneration != originalDocument &&
                      !staleDocument.isDownloading && !staleDocument.canRetry && manager.activeCount == activeBefore,
                      "GET retry rejects a replacement document at the same URL (reload=\(reload))")
            manager.remove(staleDocument); session.close(source.id); session.releaseClosedTab(); mount(session.selected)
        }
        try await rejectReplacedDocumentRetry(reload: true)
        try await rejectReplacedDocumentRetry(reload: false)

        await start("download-slow?last-normal=1")
        let lastNormal = manager.items[0]
        try await wait { lastNormal.received > 0 }
        session.close(retryTab.id)
        try check(session.selected.loadedWebView == nil, "last normal tab closes to native Start Page without a mounted webpage")
        try await wait(timeout: 30) { !lastNormal.isDownloading }
        try check(lastNormal.state == .completed, "download finishes after last normal tab closes to native Start Page")

        let privateTab = session.newTab(privateTab: true)
        try await load(privateTab, "")
        _ = try await js(privateTab, "document.querySelector('a[download]').click()")
        let privateManager = privateTab.downloads
        try await wait(timeout: 30) { privateManager.completedCount == 1 }
        let privateFile = privateManager.items[0].file!
        try check(!FileManager.default.fileExists(atPath: privateManager.store.directory.appendingPathComponent("downloads.json").path), "private download metadata never persists")
        session.closePrivateTabs()
        try check(privateManager.items.isEmpty && !FileManager.default.fileExists(atPath: privateFile.path), "last private-tab closure clears private transfers and files")
        try check(FileManager.default.fileExists(atPath: originalFile.path), "private cleanup preserves normal downloads")
        let manifest = try String(contentsOf: manager.store.directory.appendingPathComponent("downloads.json"), encoding: .utf8)
        try check(!manifest.contains("127.0.0.1") && !manifest.contains("duo-download") && !manifest.contains("resumeData"), "normal manifest excludes origins, cookies and resume tokens")
        let failingDelete = BrowserDownloads(isPrivate: false, dataStore: profile, directory: manager.store.directory,
            removeFile: { _ in throw CocoaError(.fileWriteNoPermission) })
        let retainedFirst = failingDelete.items.first { $0.id == first.id }!
        failingDelete.remove(retainedFirst)
        try check(failingDelete.items.contains(where: { $0.id == first.id }) && failingDelete.errorMessage != nil && FileManager.default.fileExists(atPath: originalFile.path),
                  "filesystem deletion failure retains the download row and explains recovery")
        manager.remove(first)
        try check(!FileManager.default.fileExists(atPath: originalFile.path), "explicit Remove deletes the retained app copy")
        try check(manager.items.contains(where: { $0.id == second.id }), "removing one retained file leaves other downloads available")
    }

    func run() async {
        if ProcessInfo.processInfo.arguments.contains("--saved-pages-preview") { savedPagesPreview(); return }
        if ProcessInfo.processInfo.arguments.contains("--download-checks") {
            do { try await downloadsChecks() } catch { results.append("FAIL: " + String(describing: error)) }
            let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("DownloadChecks.txt")
            try? results.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--reddit-preview") {
            let defaults = UserDefaults(suiteName: "DuoBrowser.RedditPreview")!
            defaults.removePersistentDomain(forName: "DuoBrowser.RedditPreview")
            let routing = RedditLinkRouting(storage: defaults)
            routing.canOpen = { _ in true }
            routing.open = { url, completion in
                let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("RedditPreview.txt")
                try? url.absoluteString.write(to: file, atomically: true, encoding: .utf8)
                completion(true)
            }
            let model = BrowserModel(dataStore: .nonPersistent())
            model.redditLinks = routing
            mount(model)
            model.webView.loadHTMLString("""
                <meta name="viewport" content="width=device-width,initial-scale=1">
                <style>body{font:24px -apple-system;margin:100px 24px;background:white;color:black}a,input{display:block;margin:32px 0;padding:16px}</style>
                <h1>Reddit link check</h1><input placeholder="Draft to preserve" value="Keep this draft">
                <a href="https://www.google.com/url?q=https%3A%2F%2Fwww.reddit.com%2Fr%2Fswift%2Fcomments%2Fabc123%2Ftitle%2Fdef456%2F%3Fcontext%3D3">Open Reddit comment</a>
                <p>Only Apollo availability and the OS launch are simulated. This link needs a real tap.</p>
                """, baseURL: URL(string: "https://fixture.invalid"))
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(30)) }
            model.close()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--reddit-checks") {
            do { try await redditChecks() } catch { results.append("FAIL: " + String(describing: error)) }
            let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("RedditChecks.txt")
            try? results.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--setup-preview") {
            try? await wait { self.host.view.window != nil }
            try? setupPreview()
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--setup-checks") {
            do { try await setupChecks() } catch { results.append("FAIL: " + String(describing: error)) }
            let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("SetupChecks.txt")
            try? results.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--address-completion-checks") {
            do { try addressCompletionChecks() } catch { results.append("FAIL: \(error)") }
            let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AddressCompletionChecks.txt")
            try? results.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--tab-overview-demo") { await overviewDemo(); return }
        if ProcessInfo.processInfo.arguments.contains("--tab-stack-checks") {
            do { try await tabStackChecks(); try wideTabLayoutChecks(); try await tabZoomChecks() } catch { results.append("FAIL: \(error)") }
            let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("TabStackChecks.txt")
            try? results.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--upgrade-checks") { await upgradeChecks(); return }
        if ProcessInfo.processInfo.arguments.contains("--settling-checks") { await settlingChecks(); return }
        if ProcessInfo.processInfo.arguments.contains("--memory-checks") { await memoryChecks(); return }
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
        defaults.removeObject(forKey: "browser.showSystemStatus")
        let session = BrowserSession(storage: defaults, archiveStore: store, dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            defaults.removeObject(forKey: "browser.showSystemStatus")
            try? FileManager.default.removeItem(at: directory)
        }
        do {
            try betaReadinessChecks()
            try addressCompletionChecks()
            try await websiteIconChecks()
            try check(!session.showSystemStatus, "status bar is hidden by default")
            session.showSystemStatus = true
            try check(defaults.bool(forKey: "browser.showSystemStatus"), "status bar choice is saved immediately")
            try check(TabStackMotion.shouldDismiss(translation: -40, velocity: -1000, width: 210) &&
                      !TabStackMotion.shouldDismiss(translation: -40, velocity: 0, width: 210),
                      "left flick closes while short slow drag cancels")
            try check(!TabStackMotion.shouldDismiss(translation: -150, velocity: 400, width: 210),
                      "reversing right cancels dismissal")
            try check(!TabStackMotion.shouldDismiss(translation: 150, velocity: 1000, width: 210),
                      "rightward swipe never closes a tab")
            try check(!TabStackMotion.shouldDismiss(translation: .nan, velocity: -1000, width: 210), "invalid drag does not close")
            try check(!TabStackMotion.shouldDismiss(translation: -90, velocity: 0, width: 0), "unmeasured card does not close")
            try check(TabStackMotion.shouldDismiss(translation: -100, velocity: 0, width: 210), "deliberate slow left drag closes")
            try check(!TabStackMotion.shouldDismiss(translation: -10, velocity: -2000, width: 210), "tiny accidental flick does not close")
            try check(TabStackMotion.shouldDismiss(translation: -75, velocity: 0, width: 210) &&
                      !TabStackMotion.shouldDismiss(translation: -75, velocity: 0, width: 300), "dismissal threshold follows resized card width")
            let portrait = CGRect(x: 0, y: 0, width: 466, height: 678)
            try check(BrowserViewportState.controlLift(in: portrait, height: 180, safeBottom: 34,
                regions: [CGRect(x: 390, y: 30, width: 60, height: 60)]) == 0, "top camera does not lift bottom controls")
            let landscape = CGRect(x: 0, y: 0, width: 678, height: 466)
            try check(BrowserViewportState.controlLift(in: landscape, height: 180, safeBottom: 34,
                regions: [CGRect(x: 610, y: 380, width: 60, height: 60)]) == 86, "bottom camera lifts native controls clear of its region")
            try check(BrowserViewportState.controlLift(in: landscape, height: 180, safeBottom: 34, regions: []) == 0,
                "removing an occlusion restores the original control position")
            let normal = session.selected
            mount(normal)
            try await wait { normal.showingStartPage && !normal.webView.isLoading }
            try check(normal.showingStartPage, "new tabs show the native start page")
            normal.navigate(to: "http://127.0.0.1:1/unreachable")
            try await wait { normal.errorMessage != nil }
            try check(normal.showingStartPage, "failed first navigation preserves the native start page")
            try await load(normal, "normal")
            try check(!normal.showingStartPage, "navigation dismisses the start page")
            let blank = BrowserModel(dataStore: .nonPersistent())
            mount(blank)
            blank.webView.loadHTMLString("<p>Site-owned blank document</p>", baseURL: nil)
            try await wait { !blank.webView.isLoading }
            try check(!blank.showingStartPage, "site-owned about blank is not a start page")
            blank.close()
            mount(normal)
            results.append("STEP: normal fixture loaded")
            _ = try await js(normal, "document.cookie='profile=normal;path=/'; localStorage.setItem('profile','normal');document.querySelector('#kept').value='unsent synthetic value'")
            let priorID = session.selectedID
            try check(!session.openExternalURL(URL(string: "javascript:alert(1)")!) && session.selectedID == priorID,
                      "external handler rejects nonweb schemes without disturbing current tab")
            try check(session.openExternalURL(URL(string: "http://127.0.0.1:8765/external?value=one#section")!), "external HTTP link accepted")
            let external = session.selected
            mount(external)
            try await wait { !external.webView.isLoading && external.webView.url?.path == "/external" }
            try check(external.id != normal.id && external.webView.url?.query == "value=one" && external.webView.url?.fragment == "section",
                      "external link opens exact URL in a separate tab")
            session.close(external.id)
            session.select(normal.id)
            mount(normal)
            try check(try await js(normal, "document.querySelector('#kept').value") as? String == "unsent synthetic value",
                      "external navigation preserves existing form draft")
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
            try check(session.openExternalURL(URL(string: "http://127.0.0.1:8765/external-private")!), "external link accepted in private mode")
            let externalPrivate = session.selected
            try check(externalPrivate.isPrivate && !externalPrivate.webView.configuration.websiteDataStore.isPersistent,
                      "external link preserves ephemeral private mode")
            session.close(externalPrivate.id)
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
            _ = try await js(memoryTab, "document.querySelector = () => null; true")
            let protected = await memoryTab.suspendIfIdle { true }
            try check(!protected && memoryTab.loadedWebView != nil, "tab with unsent form is protected from reclamation")
            try check(try await js(memoryTab, "document.getElementById('kept').value") as? String == "unsent synthetic value", "protected form retains its unsent value")
            try await load(memoryTab, "reading")
            _ = try await js(memoryTab, "document.body.insertAdjacentHTML('beforeend', '<button onclick=\"this.textContent=123\">Stateful control</button>')")
            mount(normal)
            let inlineProtected = await memoryTab.suspendIfIdle { true }
            try check(!inlineProtected, "inline event handlers protect a document from reclamation")
            try await load(memoryTab, "reading")
            _ = try await js(memoryTab, "window.scrollTo(0,400)")
            try await wait { memoryTab.webView.scrollView.contentOffset.y >= 399 }
            mount(normal)
            weak let reclaimedView = memoryTab.loadedWebView
            let suspended = await memoryTab.suspendIfIdle { true }
            try await wait { reclaimedView == nil }
            try check(reclaimedView == nil, "reclaimed WKWebView actually deallocates")
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
            try check(restored.showSystemStatus, "status bar choice survives session restoration")
            restored.showSystemStatus = false
            try check(!defaults.bool(forKey: "browser.showSystemStatus"), "hiding the status bar persists")
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
@MainActor
private final class SetupFixtureTransport: BrowserTransferTransport {
    var continuation: AsyncThrowingStream<BEBrowserData, Error>.Continuation?
    var requestContinuation: CheckedContinuation<Bool, Error>?
    func request(scene: UIWindowScene) async throws -> Bool {
        try await withCheckedThrowingContinuation { requestContinuation = $0 }
    }
    func items(token: UUID) -> AsyncThrowingStream<BEBrowserData, Error> {
        AsyncThrowingStream { continuation = $0 }
    }
}
#endif
