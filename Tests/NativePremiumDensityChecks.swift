#if DEBUG
import SwiftUI
import UIKit
import WebKit

extension NativeCheckRunner {
    func premiumDensityChecks() async throws {
        let suite = "DuoBrowser.CompactDensity." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let session = BrowserSession(storage: defaults, archiveStore: BrowserArchiveStore(directory: directory), dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        for _ in 0..<9 { session.newTab() }
        session.select(session.tabs[0].id)
        session.showingTabs = true
        let regions = CompactDensityRegions()
        var headerProbe: UIView?
        let tabs = UIHostingController(rootView: CompactDensityTabs(session: session, regions: regions) { headerProbe = $0 }
            .environment(\.dynamicTypeSize, .large).defaultAppStorage(defaults))
        tabs.safeAreaRegions = .keyboard
        host.addChild(tabs); tabs.view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        host.view.addSubview(tabs.view); tabs.didMove(toParent: host)
        defer {
            if tabs.parent != nil { tabs.willMove(toParent: nil); tabs.view.removeFromSuperview(); tabs.removeFromParent() }
        }
        func header() -> CGRect? {
            guard let headerProbe, let window = headerProbe.window else { return nil }
            return headerProbe.convert(headerProbe.bounds, to: window)
        }
        try await wait { (header()?.height ?? 0) >= 44 }
        let baseline = header()!
        let windowBounds = tabs.view.convert(tabs.view.bounds, to: tabs.view.window)
        try check(baseline.minY >= windowBounds.minY && baseline.minY <= windowBounds.minY + 20 && baseline.height <= 52,
                  "Density: actual regular tab header uses one reachable row near the display top without a camera collision")
        regions.value = [CGRect(x: 0, y: 120, width: 368, height: 24)]
        tabs.view.setNeedsLayout(); tabs.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        try check(header() == baseline,
                  "Density: a reserved region below the actual tab header does not create an unused top band")
        regions.value = [CGRect(x: 300, y: 0, width: 68, height: 20)]
        try await wait {
            guard let current = header() else { return false }
            return current.maxX <= baseline.minX + 292 + 1 && abs(current.minY - baseline.minY) < 1
        }
        let fitted = header()!
        let obstruction = CGRect(x: baseline.minX + 300, y: baseline.minY, width: 68, height: 20)
        try check(!fitted.intersects(obstruction) && abs(fitted.minX - baseline.minX) < 1 && fitted.height <= 52,
                  "Density: actual compact tab header clears a physical side region without padding the opposite edge or moving below it")
        regions.value = []
        try await wait { header() == baseline }
        try check(true, "Density: removing a header region restores the full compact row")

        guard let grid = compactDensityGrid(in: tabs) else { throw NSError(domain: "missing embedded density grid", code: 1) }
        try await wait { grid.collectionView.contentSize.height > grid.collectionView.bounds.height + 220 }
        var scrollFrames: [String] = []
        func allocatedAndHittable(_ stage: String) -> Bool {
            guard let current = header(), let window = tabs.view.window else { return false }
            let body = grid.view.convert(grid.view.bounds, to: window)
            let center = CGPoint(x: current.midX, y: current.midY)
            let hit = tabs.view.hitTest(tabs.view.convert(center, from: window), with: nil)
            let covered = hit.map { $0 === grid.collectionView || $0.isDescendant(of: grid.collectionView) } ?? true
            scrollFrames.append("\(stage): header=\(current) body=\(body) offset=\(grid.collectionView.contentOffset) covered=\(covered)")
            return current.height >= 44 && abs(current.minY - baseline.minY) < 1 && body.minY >= current.maxY - 1 && !covered
        }
        grid.collectionView.setContentOffset(CGPoint(x: 0, y: 220), animated: false)
        tabs.view.setNeedsLayout(); tabs.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let afterScroll = allocatedAndHittable("scrolled")
        grid.collectionView.setContentOffset(.zero, animated: false)
        tabs.view.setNeedsLayout(); tabs.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let afterReturn = allocatedAndHittable("returned to first row")
        grid.collectionView.setContentOffset(CGPoint(x: 0, y: -180), animated: false)
        tabs.view.setNeedsLayout(); tabs.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let afterOverscroll = allocatedAndHittable("negative overscroll")
        grid.collectionView.setContentOffset(.zero, animated: false)
        tabs.view.setNeedsLayout(); tabs.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        let afterBounce = allocatedAndHittable("returned after overscroll")
        try check(afterScroll && afterReturn && afterOverscroll && afterBounce,
                  "Density: actual embedded-grid scrolling preserves header height body allocation and header hit area; " + scrollFrames.joined(separator: "; "))

        tabs.willMove(toParent: nil); tabs.view.removeFromSuperview(); tabs.removeFromParent()
        session.showingTabs = false
        let start = session.selected
        var frames: [String: CGRect] = [:]
        let startView = UIHostingController(rootView: BrowserStartPage(session: session, browser: start, chrome: start.chrome,
            viewport: start.viewport, onSearch: {}, layoutDidChange: { frames.merge($0, uniquingKeysWith: { _, latest in latest }) })
            .environment(\.dynamicTypeSize, .large).environment(\.startPageTestRegions, [])
            .defaultAppStorage(defaults).ignoresSafeArea(.container))
        startView.safeAreaRegions = .keyboard
        host.addChild(startView); startView.view.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        host.view.addSubview(startView.view); startView.didMove(toParent: host)
        defer { startView.willMove(toParent: nil); startView.view.removeFromSuperview(); startView.removeFromParent() }
        try await wait { frames["heading"] != nil && frames["search"] != nil }
        let startBounds = startView.view.convert(startView.view.bounds, to: startView.view.window)
        let heading = frames["heading"]!, search = frames["search"]!
        try check(heading.minY >= startBounds.minY && heading.minY <= startBounds.minY + 24 && heading.height <= 52,
                  "Density: actual regular start heading has one compact top baseline without repeating a safe-area inset")
        try check(search.height >= 48 && search.height <= 52 && search.minY - heading.maxY >= 18 && search.minY - heading.maxY <= 24,
                  "Density: direct start search remains obvious and reachable with compact rendered height and spacing")
    }

    private func compactDensityGrid(in controller: UIViewController) -> TabStackController? {
        if let grid = controller as? TabStackController { return grid }
        return controller.children.lazy.compactMap { self.compactDensityGrid(in: $0) }.first
    }
}

@MainActor
private final class CompactDensityRegions: ObservableObject {
    @Published var value: [CGRect] = []
}

private struct CompactDensityTabs: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var regions: CompactDensityRegions
    let register: (UIView) -> Void
    var body: some View {
        TabOverview(session: session, search: "", didRenderTabs: { _ in }, didMeasureHeader: register)
            .environment(\.startPageTestRegions, regions.value)
    }
}
#endif
