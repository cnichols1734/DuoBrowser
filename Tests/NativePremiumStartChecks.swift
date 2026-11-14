#if DEBUG
import SwiftUI
import UIKit
import WebKit

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

        let bounds = CGRect(x: 0, y: 0, width: 400, height: 120)
        let trailing = CGRect(x: 350, y: 30, width: 50, height: 50)
        let side = StartPageLayout.clearance(in: bounds, applied: .zero, regions: [trailing])
        try check(side.right == 58 && side.left == 0 && side.top == 0,
                  "Start: local section clears measured trailing occlusion without a full-height rail")
        let bottom = CGRect(x: 0, y: 100, width: 400, height: 20)
        let first = StartPageLayout.clearance(in: bounds, applied: .zero, regions: [bottom])
        let grown = CGRect(x: 0, y: 0, width: 400, height: bounds.height + first.top + first.bottom)
        try check(first.bottom == 28 && StartPageLayout.clearance(in: grown, applied: first, regions: [bottom]) == first,
                  "Start: bottom clearance reaches a stable layout instead of growing on every pass")
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
#endif
