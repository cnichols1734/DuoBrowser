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
        try await premiumListViewportChecks(session: session, defaults: defaults)
    }

    private func premiumListViewportChecks(session: BrowserSession, defaults: UserDefaults) async throws {
        session.tabOverviewStyle = .list
        session.showingTabs = true
        let state = CompactListWindowRegions()
        var probes: [String: UIView] = [:]
        var rows: [UUID: UIView] = [:]
        let list = UIHostingController(rootView: CompactDensityList(session: session, state: state,
            register: { probes[$0] = $1 }, row: { rows[$0] = $1 }).defaultAppStorage(defaults))
        list.safeAreaRegions = .keyboard
        host.addChild(list); list.view.frame = host.view.bounds
        host.view.addSubview(list.view); list.didMove(toParent: host)
        defer { list.willMove(toParent: nil); list.view.removeFromSuperview(); list.removeFromParent() }
        func frame(_ key: String) -> CGRect? {
            guard let probe = probes[key], let window = probe.window else { return nil }
            return probe.convert(probe.bounds, to: window)
        }
        func same(_ a: CGRect?, _ b: CGRect) -> Bool {
            guard let a else { return false }
            return abs(a.minX - b.minX) < 1 && abs(a.minY - b.minY) < 1 && abs(a.width - b.width) < 1 && abs(a.height - b.height) < 1
        }
        func containedRows(_ lane: CGRect) -> [CGRect] {
            var seen = Set<ObjectIdentifier>()
            return rows.values.compactMap { probe in
                var current: UIView? = probe
                while let view = current, view !== list.view {
                    if view is UICollectionViewCell || view is UITableViewCell {
                        guard seen.insert(ObjectIdentifier(view)).inserted, let window = view.window else { return nil }
                        let rect = view.convert(view.bounds, to: window)
                        return rect.height >= 44 && lane.insetBy(dx: -1, dy: -1).contains(rect) ? rect : nil
                    }
                    current = view.superview
                }
                return nil
            }
        }
        func rowsClear(of regions: [CGRect]) -> Bool {
            guard let lane = frame("lane"), lane.width > 1, lane.height > 1 else { return false }
            let actualRows = containedRows(lane)
            return !actualRows.isEmpty && actualRows.allSatisfy { row in !regions.contains { row.intersects($0) } }
        }
        try await wait { frame("viewport") != nil && rowsClear(of: []) }
        let viewport = frame("viewport")!, header = frame("header")!
        let band = CGRect(x: viewport.minX, y: viewport.minY + 48, width: viewport.width, height: 32)
        state.regions = [band]
        try await wait { (frame("lane")?.minY ?? 0) >= band.maxY + 7 && rowsClear(of: [band]) }
        try check(same(frame("header"), header) && rowsClear(of: [band]),
                  "Density List: actual accessibility-size native row cells fit a clear viewport below a full-width region without moving the compact header")
        guard let scroll = compactListScroll(in: list.view) else { throw NSError(domain: "missing native density List scroll view", code: 1) }
        try await wait { scroll.contentSize.height > scroll.bounds.height + 120 }
        scroll.setContentOffset(CGPoint(x: 0, y: 120), animated: false)
        try await wait { scroll.contentOffset.y > 0 && rowsClear(of: [band]) }
        try check(rowsClear(of: [band]), "Density List: scrolling actual row cells keeps reachable rows inside the clear viewport instead of behind the full-width region")
        scroll.setContentOffset(.zero, animated: false)
        let moved = CGRect(x: viewport.minX, y: viewport.maxY - 64, width: viewport.width, height: 32)
        state.regions = [moved]
        try await wait { abs((frame("lane")?.minY ?? -1) - viewport.minY) < 1 && (frame("lane")?.maxY ?? .infinity) <= moved.minY - 7 && rowsClear(of: [moved]) }
        try check(same(frame("header"), header) && rowsClear(of: [moved]),
                  "Density List: moving a full-width region selects the larger clear band and preserves actual row containment")
        state.regions = [CGRect(x: viewport.minX, y: viewport.maxY + 20, width: viewport.width, height: 20)]
        try await wait { same(frame("lane"), viewport) && rowsClear(of: []) }
        try check(true, "Density List: an exclusion outside the actual body creates no duplicated header or top clearance")
        state.regions = []
        try await wait { same(frame("lane"), viewport) && rowsClear(of: []) }
        try check(compactListScroll(in: list.view) === scroll,
                  "Density List: removing regions restores the complete viewport without replacing the native List")
        let side = CGRect(x: viewport.minX, y: viewport.minY, width: 68, height: viewport.height)
        state.direction = .rightToLeft
        state.regions = [side, band]
        try await wait { (frame("lane")?.minX ?? 0) >= side.maxX + 7 && (frame("lane")?.minY ?? 0) >= band.maxY + 7 && rowsClear(of: [side, band]) }
        try check(rowsClear(of: [side, band]), "Density List: actual RTL accessibility rows remain inside the asymmetric clear lane with both side and full-width regions")
        state.regions = [viewport]
        let point = CGPoint(x: viewport.midX, y: viewport.midY)
        let pixelTolerance = 1 / (list.view.window?.screen.scale ?? 1)
        do {
            try await wait {
                guard let lane = frame("lane") else { return false }
                // Native backing views round the tiny hidden canvas outward to physical pixels.
                return lane.width <= 1 + pixelTolerance + 1e-6 && lane.height <= 1 + pixelTolerance + 1e-6
            }
        } catch {
            let scrollFrame = scroll.window.map { scroll.convert(scroll.bounds, to: $0) }
            let target = list.view.window?.hitTest(point, with: nil)
            let covered = target.map { $0 === scroll || $0.isDescendant(of: scroll) } ?? false
            throw NSError(domain: "Density fully-covered List did not settle; lane=\(String(describing: frame("lane"))) scroll=\(String(describing: scrollFrame)) header=\(String(describing: frame("header"))) rowHit=\(covered)", code: 1)
        }
        let hit = list.view.window?.hitTest(point, with: nil)
        try check((hit.map { $0 !== scroll && !$0.isDescendant(of: scroll) } ?? true) && same(frame("header"), header),
                  "Density List: a completely occluded body hides its retained List and exposes no row hit target; lane=\(String(describing: frame("lane"))) header=\(String(describing: frame("header")))")
        state.direction = .leftToRight
        state.regions = []
        try await wait { same(frame("lane"), viewport) && rowsClear(of: []) }
        try check(compactListScroll(in: list.view) === scroll && same(frame("header"), header),
                  "Density List: clearing a fully occluded body restores native rows identity and header position")
    }

    private func compactListScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        return view.subviews.lazy.compactMap { self.compactListScroll(in: $0) }.first
    }

    private func compactDensityGrid(in controller: UIViewController) -> TabStackController? {
        if let grid = controller as? TabStackController { return grid }
        return controller.children.lazy.compactMap { self.compactDensityGrid(in: $0) }.first
    }
}

@MainActor
private final class CompactListWindowRegions: ObservableObject {
    @Published var regions: [CGRect] = []
    @Published var direction: LayoutDirection = .leftToRight
}

private struct CompactDensityList: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var state: CompactListWindowRegions
    let register: (String, UIView) -> Void
    let row: (UUID, UIView) -> Void
    var body: some View {
        TabOverview(session: session, search: "", didRenderTabs: { _ in },
            didMeasureHeader: { register("header", $0) }, didMeasureListViewport: { register("viewport", $0) },
            didMeasureListLane: { register("lane", $0) }, didMeasureListRow: row)
            .environment(\.startPageTestRegions, [])
            .environment(\.tabListTestRegionsInWindow, state.regions)
            .environment(\.layoutDirection, state.direction)
            .environment(\.dynamicTypeSize, .accessibility3)
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
