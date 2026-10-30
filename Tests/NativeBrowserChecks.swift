#if DEBUG
import SwiftUI
import WebKit
import Darwin

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
    func upgradeChecks() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UpgradeChecks-" + UUID().uuidString)
        let store = BrowserArchiveStore(directory: directory)
        let session = BrowserSession(storage: UserDefaults(suiteName: "DuoBrowser.UpgradeChecks")!, archiveStore: store, dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            try? FileManager.default.removeItem(at: directory)
        }
        do {
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
            try check(normal.blockingStatus == "Basic protection on", "bundled content rules compile and attach before navigation")
            // Substitute only the ad host with a loopback host; all rule flags and production installation remain identical.
            let rulesURL = Bundle.main.url(forResource: "BlockingRules", withExtension: "json")!
            let json = try String(contentsOf: rulesURL, encoding: .utf8)
            let fixtureRules = json.replacingOccurrences(of: "doubleclick\\\\.net", with: "localhost")
            ContentBlocking.useTestRules(fixtureRules)
            try await load(normal, "upgrades")
            let blocked = try await asyncJS(normal, "return await fetch('http://localhost:8765/probe').then(()=>false).catch(()=>true)") as? Bool
            try check(blocked == true, "native blocker prevents third-party synthetic request")
            normal.blockAds = false
            try await wait { normal.blockingStatus == "Off for this site" && !normal.isLoading }
            try check(try await asyncJS(normal, "return await fetch('http://localhost:8765/probe').then(()=>true).catch(()=>false)") as? Bool == true, "site exception allows synthetic request after reload")
            normal.blockAds = true
            try await wait { normal.blockingStatus == "Basic protection on" && !normal.isLoading }
            try check(try await asyncJS(normal, "return await fetch('http://localhost:8765/probe').then(()=>false).catch(()=>true)") as? Bool == true, "reenabling protection blocks again")
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
            try check(opener.blockAds && opener.blockingStatus == "Basic protection on" && !popup.blockAds, "new-window exception leaves opener protection enabled")
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

    func run() async {
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
            try check(!session.showSystemStatus, "status bar is hidden by default")
            session.showSystemStatus = true
            try check(defaults.bool(forKey: "browser.showSystemStatus"), "status bar choice is saved immediately")
            let portrait = CGRect(x: 0, y: 0, width: 466, height: 678)
            try check(BrowserViewportState.controlLift(in: portrait, height: 180, safeBottom: 34,
                regions: [CGRect(x: 390, y: 30, width: 60, height: 60)]) == 0, "top camera does not lift bottom controls")
            let landscape = CGRect(x: 0, y: 0, width: 678, height: 466)
            try check(BrowserViewportState.controlLift(in: landscape, height: 180, safeBottom: 34,
                regions: [CGRect(x: 610, y: 380, width: 60, height: 60)]) == 86, "bottom camera lifts native controls clear of its region")
            try check(BrowserViewportState.controlLift(in: landscape, height: 180, safeBottom: 34, regions: []) == 0,
                "removing an occlusion restores the original control position")
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
#endif
