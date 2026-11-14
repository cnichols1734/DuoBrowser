#if DEBUG
import SwiftUI
import UIKit
import WebKit
import Combine

extension NativeCheckRunner {
    func premiumStartChecks() async throws {
        let suite = "DuoBrowser.PremiumStartChecks." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        var rejectWrites = false
        let archive = BrowserArchiveStore(directory: directory, writeData: { data, url, options in
            if rejectWrites { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: options)
        })
        let session = BrowserSession(storage: defaults, archiveStore: archive, dataStore: .nonPersistent())
        defer {
            session.closePrivateTabs(); session.tabs.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let a = LibraryEntry(address: "https://a.example", title: "First")
        let b = LibraryEntry(address: "https://b.example", title: "Second", isFavorite: true)
        let kept = LibraryEntry(address: "https://kept.example", title: "Library bookmark", isFavorite: false)
        session.bookmarks = [a, kept, b]
        try check(session.saveNow(), "Start: seeded normal favorites save to isolated archive")
        try check(session.reorderStartPageFavorites([b.id, a.id]), "Start: native favorite move succeeds")
        try check(session.bookmarks.map(\.id) == [b.id, kept.id, a.id] && archive.load()?.bookmarks.map(\.id) == [b.id, kept.id, a.id],
                  "Start: moved favorites persist while nonfavorite bookmark stays in place")
        try check(!session.reorderStartPageFavorites([a.id]) && session.favorites.map(\.id) == [b.id, a.id],
                  "Start: stale partial favorite order is rejected without mutation")
        rejectWrites = true
        try check(!session.reorderStartPageFavorites([a.id, b.id]) && session.favorites.map(\.id) == [b.id, a.id],
                  "Start: failed persistence rolls back favorite ordering")
        try check(!session.removeStartPageFavorite(a.id) && session.favorites.contains { $0.id == a.id },
                  "Start: failed removal preserves favorite and bookmark")
        rejectWrites = false
        try check(session.removeStartPageFavorite(a.id) && session.bookmarks.contains { $0.id == a.id && $0.isFavorite == false },
                  "Start: removing a favorite preserves its Library bookmark")
        session.switchMode(true)
        try check(!session.reorderStartPageFavorites([b.id]) && !session.removeStartPageFavorite(b.id),
                  "Start: private mode cannot edit the normal start-page favorites")
        session.switchMode(false)
        let folder = BookmarkFolder(title: "Preserved folder", parentID: nil)
        try session.saveFolder(folder)
        var existing = kept
        existing.folderID = folder.id
        existing.date = Date(timeIntervalSince1970: 1234)
        try session.savePage(existing, reading: false)
        try check(session.saveStartPageFavorite(LibraryEntry(address: "", title: ""), address: URL(string: kept.address)!, name: "Added favorite"),
                  "Start: adding an existing bookmark address promotes it to Favorites")
        let promoted = session.bookmarks.filter { $0.address == kept.address }
        try check(promoted.count == 1 && promoted[0].id == kept.id && promoted[0].folderID == folder.id &&
                  promoted[0].date == existing.date && promoted[0].title == "Added favorite" && promoted[0].isFavorite == true,
                  "Start: favorite promotion preserves existing bookmark folder date and identity without duplication")

        let recent = StartPageRecentSitesProjection()
        var projectionUpdates = 0
        let projectionObservation = recent.$sites.dropFirst().sink { _ in projectionUpdates += 1 }
        defer { projectionObservation.cancel() }
        let recentEntry = LibraryEntry(address: "https://recent.example/page", title: "Recent synthetic page")
        recent.bind(to: session, enabled: false)
        session.history = [recentEntry]
        try check(recent.sites.isEmpty && projectionUpdates == 0,
                  "Start: hidden Recent Sites does not build a history projection when data changes")
        recent.bind(to: session, enabled: true)
        let firstProjectionUpdates = projectionUpdates
        for _ in 0..<20 { recent.bind(to: session, enabled: true) }
        try check(recent.sites.map(\.id) == [recentEntry.id] && projectionUpdates == firstProjectionUpdates,
                  "Start: repeated view binding retains the cached Recent Sites projection")
        let newestEntry = LibraryEntry(address: "https://newest.example/page", title: "Newer synthetic page")
        session.history = [newestEntry, recentEntry]
        try check(recent.sites.map(\.id) == [newestEntry.id, recentEntry.id] && projectionUpdates == firstProjectionUpdates + 1,
                  "Start: Recent Sites rebuilds when normal history actually changes")
        recent.bind(to: session, enabled: false)
        let hiddenUpdates = projectionUpdates
        session.history = [newestEntry]
        try check(recent.sites.isEmpty && projectionUpdates == hiddenUpdates,
                  "Start: hiding Recent Sites drops its subscription and cached results")
        session.switchMode(true)
        recent.bind(to: session, enabled: true)
        try check(recent.sites.isEmpty && projectionUpdates == hiddenUpdates,
                  "Start: a private start cannot enable a normal history projection")
        session.switchMode(false)

        let bounds = CGRect(x: 0, y: 0, width: 400, height: 120)
        let trailing = CGRect(x: 350, y: 30, width: 50, height: 50)
        let side = StartPageLayout.clearance(in: bounds, applied: .zero, regions: [trailing])
        try check(side.right == 58 && side.left == 0 && side.top == 0,
                  "Start: local section clears measured trailing occlusion without a full-height rail")
        let bottom = CGRect(x: 0, y: 100, width: 400, height: 20)
        let first = StartPageLayout.clearance(in: bounds, applied: .zero, regions: [bottom])
        let grown = CGRect(x: 0, y: 0, width: 400, height: bounds.height + first.top + first.bottom)
        try check(first.top == 128 && first.bottom == 0 && StartPageLayout.clearance(in: grown, applied: first, regions: [bottom]) == first,
                  "Start: low full-width occlusion moves actual content below it with stable top clearance")
        try check(StartPageLayout.clearance(in: bounds, applied: side, regions: []).right == 0,
                  "Start: section returns to full width when system occlusion disappears")
        let top = CGRect(x: 0, y: 0, width: 400, height: 22)
        try check(StartPageLayout.clearance(in: bounds, applied: .zero, regions: [top]).top == 30,
                  "Start: full-width top island is cleared vertically from actual geometry")

        let start = session.selected
        var frames: [String: CGRect] = [:]
        let controller = UIHostingController(rootView: BrowserStartPage(session: session, browser: start,
            chrome: start.chrome, viewport: start.viewport, onSearch: {}, layoutDidChange: {
                frames.merge($0, uniquingKeysWith: { _, latest in latest })
            }).id(start.id).defaultAppStorage(defaults))
        host.addChild(controller); controller.view.frame = host.view.bounds
        host.view.addSubview(controller.view); controller.didMove(toParent: host)
        defer { controller.willMove(toParent: nil); controller.view.removeFromSuperview(); controller.removeFromParent() }
        try await wait { frames["search"] != nil && frames["favorites"] != nil }
        let windowBounds = controller.view.convert(controller.view.bounds, to: controller.view.window)
        try check(["heading", "search", "favorites"].allSatisfy {
            guard let frame = frames[$0] else { return false }
            return frame.width > 0 && frame.height > 0 && frame.minX >= windowBounds.minX && frame.maxX <= windowBounds.maxX
        }, "Start: rendered normal heading/search/favorites remain within horizontal window bounds")
        try check(frames["private"] == nil, "Start: normal start has no private explanation")
        var privateFrames: [String: CGRect] = [:]
        session.switchMode(true)
        let privateTab = session.selected
        controller.rootView = BrowserStartPage(session: session, browser: privateTab, chrome: privateTab.chrome,
            viewport: privateTab.viewport, onSearch: {}, layoutDidChange: {
                privateFrames.merge($0, uniquingKeysWith: { _, latest in latest })
            }).id(privateTab.id).defaultAppStorage(defaults)
        try await wait { privateFrames["private"] != nil && privateFrames["search"] != nil }
        try check(privateFrames["favorites"] == nil && privateFrames["openTabs"] == nil && privateFrames["recentSites"] == nil && privateFrames["customize"] == nil,
                  "Start: rendered private start omits normal favorite/history/tab/customization surfaces")
        try check(session.bookmarks.contains { $0.id == b.id }, "Start: private presentation leaves normal saved pages intact")
        try await premiumStartRenderedClearanceChecks()
    }

    private func premiumStartRenderedClearanceChecks() async throws {
        let cases: [(String, CGRect, LayoutDirection, CGFloat, CGFloat)] = [
            ("low full-width region", CGRect(x: 0, y: 100, width: 400, height: 20), .leftToRight, 0, 128),
            ("wide interior region", CGRect(x: 80, y: 45, width: 240, height: 30), .leftToRight, 0, 83),
            ("right region LTR", CGRect(x: 350, y: 30, width: 50, height: 50), .leftToRight, -58, 0),
            ("right region RTL", CGRect(x: 350, y: 30, width: 50, height: 50), .rightToLeft, -58, 0),
            ("left region LTR", CGRect(x: 0, y: 30, width: 50, height: 50), .leftToRight, 58, 0),
            ("left region RTL", CGRect(x: 0, y: 30, width: 50, height: 50), .rightToLeft, 58, 0)
        ]
        for (name, region, direction, horizontal, top) in cases {
            let regions = PremiumStartFixtureRegions([region])
            var measured: [String: CGRect] = [:]
            let controller = UIHostingController(rootView: PremiumStartClearanceFixture(regions: regions, direction: direction) {
                measured[$0] = $1
            })
            host.addChild(controller); controller.view.frame = CGRect(x: 0, y: 0, width: 400, height: 300)
            host.view.addSubview(controller.view); controller.didMove(toParent: host)
            defer { controller.willMove(toParent: nil); controller.view.removeFromSuperview(); controller.removeFromParent() }
            try await wait {
                guard let outer = measured["outer"], let content = measured["content"] else { return false }
                let expectedX = horizontal > 0 ? outer.minX + horizontal : outer.minX
                let expectedWidth = outer.width - abs(horizontal)
                return abs(content.minX - expectedX) < 1 && abs(content.width - expectedWidth) < 1 &&
                    abs(content.minY - outer.minY - top) < 1 && abs(content.height - 120) < 1
            }
            guard let outer = measured["outer"], let content = measured["content"] else {
                throw NSError(domain: "missing rendered start clearance frames", code: 1)
            }
            let obstruction = region.offsetBy(dx: outer.minX, dy: outer.minY)
            try check(!content.intersects(obstruction) && content.minX >= outer.minX && content.maxX <= outer.maxX &&
                      content.minY >= outer.minY && content.maxY <= outer.maxY + 1,
                      "Start: actual rendered tap surface clears \(name) and stays inside its expanded section")
            if name == "low full-width region" {
                guard let scroll = premiumStartScrollView(in: controller.view) else {
                    throw NSError(domain: "missing start clearance fixture scroll view", code: 1)
                }
                try await wait { scroll.contentSize.height > scroll.bounds.height + 200 }
                scroll.setContentOffset(CGPoint(x: 0, y: 150), animated: false)
                try check(scroll.isScrollEnabled && scroll.contentOffset.y > 100,
                          "Start: moved section expands native scroll content and leaves later controls reachable")
                scroll.setContentOffset(.zero, animated: false)
                regions.value = []
                try await wait {
                    guard let outer = measured["outer"], let content = measured["content"] else { return false }
                    return abs(content.minX - outer.minX) < 1 && abs(content.minY - outer.minY) < 1 &&
                        abs(content.width - 400) < 1 && abs(outer.height - 120) < 1
                }
                try check(true, "Start: removing a system region restores the actual rendered content frame and section height")
            }
        }
    }

    private func premiumStartScrollView(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.premiumStartScrollView(in: $0) }.first
    }

    /// Synthetic start-page scene for closed/open/partial/rotation/large-type visual review.
    func premiumStartPreview() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PremiumStartPreview-" + UUID().uuidString)
        let session = BrowserSession(storage: UserDefaults(suiteName: "DuoBrowser.PremiumStartPreview")!,
            archiveStore: BrowserArchiveStore(directory: directory), dataStore: .nonPersistent())
        session.setup.finish()
        session.bookmarks = [
            LibraryEntry(address: "https://apple.example", title: "Apple"),
            LibraryEntry(address: "https://wikipedia.example", title: "Wikipedia"),
            LibraryEntry(address: "https://reddit.example", title: "Reddit"),
            LibraryEntry(address: "https://github.example", title: "GitHub"),
            LibraryEntry(address: "https://youtube.example", title: "YouTube"),
            LibraryEntry(address: "https://news.example", title: "News")
        ]
        session.workspaces.append(Workspace(name: "Weekend"))
        session.newTab(url: URL(string: "http://127.0.0.1:8765/upgrades"))
        session.newTab(url: URL(string: "http://127.0.0.1:8765/preview"))
        session.newTab()
        if ProcessInfo.processInfo.arguments.contains("--premium-private-preview") { session.switchMode(true) }
        let controller = UIHostingController(rootView: BrowserZoomPresenter(session: session).ignoresSafeArea(.container))
        host.addChild(controller); controller.view.frame = host.view.bounds
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.addSubview(controller.view); controller.didMove(toParent: host)
    }
}

@MainActor
private final class PremiumStartFixtureRegions: ObservableObject {
    @Published var value: [CGRect]
    init(_ value: [CGRect]) { self.value = value }
}

private struct PremiumStartClearanceFixture: View {
    @ObservedObject var regions: PremiumStartFixtureRegions
    let direction: LayoutDirection
    let update: (String, CGRect) -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Button {} label: { Text("Synthetic start action").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    .frame(height: 120)
                    .background { PremiumStartClearanceProbe(name: "content", update: update) }
                    .modifier(StartPageClearance())
                    .background { PremiumStartClearanceProbe(name: "outer", update: update) }
                Text("Synthetic controls farther down the start page").frame(height: 900)
            }
        }
        .environment(\.layoutDirection, direction)
        .environment(\.startPageTestRegions, regions.value)
        .ignoresSafeArea(.container)
    }
}

private struct PremiumStartClearanceProbe: UIViewRepresentable {
    let name: String
    let update: (String, CGRect) -> Void
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) { view.name = name; view.update = update; view.setNeedsLayout() }
    final class Probe: UIView {
        var name = ""
        var update: ((String, CGRect) -> Void)?
        private var last: CGRect?
        override func didMoveToWindow() { super.didMoveToWindow(); last = nil; setNeedsLayout() }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window else { return }
            let frame = convert(bounds, to: window)
            guard frame != last else { return }
            last = frame
            let name = name
            DispatchQueue.main.async { [weak self] in
                guard let self, self.last == frame else { return }
                self.update?(name, frame)
            }
        }
    }
}
#endif
