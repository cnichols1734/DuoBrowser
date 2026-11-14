#if DEBUG
import SwiftUI
import WebKit
import Combine

extension NativeCheckRunner {
    func premiumTabsChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PremiumTabs-" + UUID().uuidString)
        let defaults = UserDefaults(suiteName: "PremiumTabs-" + UUID().uuidString)!
        let archive = BrowserArchiveStore(directory: directory)
        let session = BrowserSession(storage: defaults, archiveStore: archive, dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            try? FileManager.default.removeItem(at: directory)
        }
        let original = session.selected
        let workspace = original.workspaceID
        try await load(original, "")
        _ = try await js(original, "document.querySelector('#kept').value='A premium tab keeps this draft'; true")
        let originalView = original.webView
        let second = session.newTab()
        let third = session.newTab()
        session.select(original.id)
        try check(session.adjacentTabID(-1) == nil && session.adjacentTabID(1) == second.id,
                  "adjacent tabs follow visible order without wrapping")
        try check(session.adjacentTabID(0) == nil && session.adjacentTabID(2) == nil,
                  "adjacent lookup rejects invalid direction")
        try check(session.reorderVisibleTabs([third.id, original.id, second.id]), "complete visible reorder is accepted")
        try check(session.visibleTabs.map(\.id) == [third.id, original.id, second.id] && session.selected === original,
                  "reordering preserves selection and exact model identities")
        try check(original.webView === originalView, "reordering keeps the live form web view")
        try check(try await js(original, "document.querySelector('#kept').value") as? String == "A premium tab keeps this draft",
                  "reordering preserves unsent website input")
        try check(!session.reorderVisibleTabs([original.id, second.id]) &&
                  !session.reorderVisibleTabs([original.id, second.id, second.id]), "partial and duplicated stale reorder snapshots are rejected")
        session.togglePin(second)
        _ = session.reorderVisibleTabs([third.id, original.id, second.id])
        try check(session.visibleTabs.first === second && second.isPinned, "reorder preserves pinned-first policy without changing pins")
        session.togglePin(second)
        _ = session.reorderVisibleTabs([third.id, original.id, second.id])
        session.tabOverviewStyle = .list
        try check(defaults.string(forKey: "browser.tabOverviewStyle") == "list", "overview layout choice is remembered locally")

        let content = UIViewController()
        content.view.backgroundColor = .systemBackground
        originalView.removeFromSuperview()
        content.view.addSubview(originalView)
        originalView.frame = content.view.bounds
        originalView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let swipe = TabSwipeController(content: content, session: session)
        host.addChild(swipe)
        swipe.view.frame = host.view.bounds
        host.view.addSubview(swipe.view)
        swipe.didMove(toParent: host)
        swipe.view.layoutIfNeeded()
        defer {
            swipe.cancelImmediately()
            swipe.willMove(toParent: nil)
            swipe.view.removeFromSuperview()
            swipe.removeFromParent()
        }
        let width = swipe.view.bounds.width
        session.tabSwipe.receive?(.changed(-width * 0.18))
        try check(session.selected === original && originalView.superview === content.view,
                  "interactive tab drag keeps source live and does not select its preview")
        try check(abs(content.view.transform.tx) > 0 || UIAccessibility.isReduceMotionEnabled,
                  "tab drag follows the finger unless system Reduce Motion requests a fade")
        guard let preview = swipe.view.subviews.first(where: { $0 !== content.view }) else {
            throw NSError(domain: "missing native adjacent-tab preview", code: 1)
        }
        let previewBeforeLayout = preview.convert(preview.bounds, to: swipe.view)
        let sourceBeforeLayout = content.view.convert(content.view.bounds, to: swipe.view)
        let previewTransform = preview.transform
        swipe.view.setNeedsLayout()
        swipe.view.layoutIfNeeded()
        let previewAfterLayout = preview.convert(preview.bounds, to: swipe.view)
        let sourceAfterLayout = content.view.convert(content.view.bounds, to: swipe.view)
        try check(swipe.hasActivePresentation && session.selected === original && preview.transform == previewTransform
                  && abs(previewAfterLayout.minX - previewBeforeLayout.minX) < 0.5
                  && abs(sourceAfterLayout.minX - sourceBeforeLayout.minX) < 0.5,
                  "same-bounds layout preserves the live source and translated adjacent preview during a drag")
        session.tabSwipe.receive?(.changed(-width * 0.20))
        let nextPreview = preview.convert(preview.bounds, to: swipe.view)
        let expectedMovement: CGFloat = UIAccessibility.isReduceMotionEnabled ? 0 : -width * 0.02
        try check(abs(nextPreview.minX - previewAfterLayout.minX - expectedMovement) < 0.5
                  && original.loadedWebView === originalView,
                  "continuing a drag after layout moves the neighbor from its retained position without replacing WebKit")
        session.tabSwipe.receive?(.cancelled)
        try await wait { !swipe.hasActivePresentation && content.view.transform == .identity && content.view.alpha == 1 }
        try check(session.selected === original, "cancelled drag restores the same selected tab")
        try check(try await js(original, "document.querySelector('#kept').value") as? String == "A premium tab keeps this draft",
                  "cancelled drag preserves the unsent form")
        session.tabSwipe.receive?(.changed(-width * 0.3))
        session.tabSwipe.receive?(.ended(-width * 0.3, -width * 0.7))
        try await wait { session.selectedID == second.id }
        try check(session.selected === second && content.view.transform == .identity && content.view.alpha == 1,
                  "committed swipe selects the existing neighbor and clears presentation")
        session.select(original.id)
        let draftAfterCommit = try await js(original, "document.querySelector('#kept').value") as? String
        try check(original.webView === originalView && draftAfterCommit == "A premium tab keeps this draft",
                  "returning after committed swipe restores exact live page and draft")
        session.tabSwipe.receive?(.changed(-width * 0.18))
        if !UIAccessibility.isReduceMotionEnabled {
            try await wait { abs((content.view.layer.presentation()?.affineTransform().tx ?? 0) + width * 0.18) < 2 }
        }
        let beforeInterruption = content.view.layer.presentation()?.affineTransform().tx ?? content.view.transform.tx
        session.tabSwipe.receive?(.cancelled)
        // Start another real gesture while snap-back is still active, without waiting it away.
        session.tabSwipe.receive?(.changed(-width * 0.03))
        try check(swipe.hasActivePresentation &&
                  (UIAccessibility.isReduceMotionEnabled || abs(content.view.transform.tx - beforeInterruption) < 3),
                  "a new tab drag catches a returning page at its current presentation without a jump")
        session.tabSwipe.receive?(.ended(-width * 0.3, -width * 1.1))
        try await wait { session.selectedID == second.id }
        try check(session.selected === second && !swipe.hasActivePresentation,
                  "an interrupted snap-back accepts and commits the next gesture")
        session.select(original.id)
        session.tabSwipe.receive?(.changed(-width * 0.18))
        if !UIAccessibility.isReduceMotionEnabled {
            try await wait { abs((content.view.layer.presentation()?.affineTransform().tx ?? 0) + width * 0.18) < 2 }
        }
        let beforeOpposite = content.view.layer.presentation()?.affineTransform().tx ?? content.view.transform.tx
        session.tabSwipe.receive?(.cancelled)
        session.tabSwipe.receive?(.changed(width * 0.03))
        try check(swipe.hasActivePresentation &&
                  (UIAccessibility.isReduceMotionEnabled || abs(content.view.transform.tx - beforeOpposite) < 3),
                  "an opposite drag catches the same returning presentation without jumping")
        session.tabSwipe.receive?(.ended(width * 0.3, width * 1.1))
        try await wait { session.selectedID == third.id }
        try check(session.selected === third && !swipe.hasActivePresentation,
                  "a fresh rightward gesture after cancelled leftward motion selects the previous tab")
        session.select(original.id)
        session.tabSwipe.receive?(.changed(-width * 0.45))
        if !UIAccessibility.isReduceMotionEnabled {
            try await wait { abs((content.view.layer.presentation()?.affineTransform().tx ?? 0) + width * 0.45) < 2 }
        }
        session.tabSwipe.receive?(.cancelled)
        session.tabSwipe.receive?(.changed(20))
        session.tabSwipe.receive?(.ended(20, 20))
        try await wait { !swipe.hasActivePresentation }
        try check(session.selected === original,
                  "a tiny fresh opposite gesture cannot inherit a commitment from the old page offset")
        let draftAfterOpposite = try await js(original, "document.querySelector('#kept').value") as? String
        try check(original.webView === originalView && draftAfterOpposite == "A premium tab keeps this draft",
                  "opposite-direction interruptions preserve the original live page and form draft")
        session.tabSwipe.receive?(.changed(width * 0.3))
        swipe.view.frame.size.width += 20
        swipe.view.setNeedsLayout(); swipe.view.layoutIfNeeded()
        session.tabSwipe.receive?(.ended(width * 0.3, width * 0.7))
        try check(session.selected === original && content.view.transform == .identity,
                  "fold or rotation geometry invalidates an in-flight swipe")
        swipe.view.frame = host.view.bounds
        swipe.view.setNeedsLayout(); swipe.view.layoutIfNeeded()
        swipe.reduceMotion = true
        session.tabSwipe.receive?(.changed(-width * 0.3))
        try check(content.view.transform == .identity, "Reduce Motion avoids page translation during tab swipe")
        session.tabSwipe.receive?(.cancelled)
        try await wait { !swipe.hasActivePresentation && content.view.alpha == 1 }
        session.tabSwipe.receive?(.changed(-width * 0.3))
        session.tabSwipe.receive?(.cancelled)
        session.tabSwipe.receive?(.changed(width * 0.03))
        session.tabSwipe.receive?(.ended(width * 0.3, width * 1.1))
        try await wait { session.selectedID == third.id }
        try check(session.selected === third && content.view.transform == .identity && !swipe.hasActivePresentation,
                  "Reduce Motion also uses fresh opposite-gesture intent to choose the previous tab")
        session.select(original.id)

        let beforePrivate = session.visibleTabs.map(\.id)
        let privateTab = session.newTab(privateTab: true)
        try check(session.adjacentTabID(-1) == nil && session.adjacentTabID(1) == nil,
                  "private swipe cannot reveal a normal tab")
        try check(!session.reorderVisibleTabs(beforePrivate) && session.closeTabs(Set(beforePrivate)) == 0,
                  "private operations reject normal-profile selection IDs")
        try check(session.moveTabs([privateTab.id], to: workspace) == 0, "private tabs cannot move into a normal workspace")
        let records = session.recentlyClosed.count
        _ = session.closeTabs([privateTab.id])
        try check(!session.tabs.contains { $0.id == privateTab.id } && session.recentlyClosed.count == records,
                  "batch private closure creates no Recently Closed record")
        session.select(original.id)
        session.createWorkspace("Research")
        let research = session.workspaceID
        session.switchWorkspace(workspace)
        session.select(original.id)
        try check(session.moveTabs([second.id, third.id], to: research) == 2,
                  "selected normal tabs move together to an existing workspace")
        try check(session.selected === original && original.webView === originalView &&
                  second.workspaceID == research && third.workspaceID == research,
                  "batch move preserves source page and each destination tab identity")
        try check(session.moveTabs([original.id], to: UUID()) == 0 && session.closeTabs([second.id]) == 0,
                  "unknown destination and out-of-workspace stale close selection are rejected")
        session.select(second.id)
        try check(session.closeTabs([second.id, third.id]) == 2 && !session.tabs.contains { $0.id == second.id || $0.id == third.id },
                  "batch close removes only validated selected tabs")
        try check(session.tabs.contains { $0 === original } && original.webView === originalView,
                  "batch closure preserves unselected live page")
        try check(session.tabs.contains { !$0.isPrivate } && session.tabs.contains { $0.id == session.selectedID },
                  "batch close always leaves a valid normal session and selected tab")
        try check(archive.load()?.session.tabs.contains { $0.id == privateTab.id } == false,
                  "private tab and private reorder never enter the persistent archive")
        try check(TabSwipeMotion.shouldCommit(translation: -120, predicted: -200, width: 466) &&
                  !TabSwipeMotion.shouldCommit(translation: -12, predicted: -500, width: 466),
                  "deliberate tab swipe commits while an accidental tiny flick does not")
        try check(!TabSwipeMotion.shouldCommit(translation: .nan, predicted: -500, width: 466) &&
                  !TabSwipeMotion.shouldCommit(translation: -120, predicted: 300, width: 466) &&
                  !TabSwipeMotion.shouldCommit(translation: -120, predicted: -300, width: 0),
                  "invalid geometry and reversed intent cannot commit a tab swipe")
        try premiumTabWriteFailureChecks()
        try premiumBatchClosePersistenceChecks()
        try await premiumPrivateTabRowChecks()
    }

    private func premiumBatchClosePersistenceChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PremiumBatchClose-" + UUID().uuidString)
        let suite = "PremiumBatchClose-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        var primaryWrites = 0
        var backupWrites = 0
        var rejectPrimary = false
        let archive = BrowserArchiveStore(directory: directory, writeData: { data, url, options in
            if url.lastPathComponent == "session.json" {
                primaryWrites += 1
                if rejectPrimary { throw CocoaError(.fileWriteOutOfSpace) }
            } else if url.lastPathComponent == "session.backup.json" { backupWrites += 1 }
            try data.write(to: url, options: options)
        })
        let session = BrowserSession(storage: defaults, archiveStore: archive, dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let kept = session.selected
        let closing = (0..<12).map { _ in session.newTab() }
        let selected = session.selected
        session.showingTabs = true
        try check(session.saveNow(), "batch close seeds a durable session for counted writes")
        var previousIDs = Set(session.tabs.map(\.id))
        var removalOrder: [UUID] = []
        let tabObservation = session.$tabs.sink { tabs in
            let currentIDs = Set(tabs.map(\.id))
            removalOrder.append(contentsOf: previousIDs.subtracting(currentIDs))
            previousIDs = currentIDs
        }
        defer { tabObservation.cancel() }
        primaryWrites = 0; backupWrites = 0
        try check(session.closeTabs(Set(closing.map(\.id))) == closing.count,
                  "batch close tears down every selected tab including the active tab")
        try check(primaryWrites == 1 && backupWrites == 1,
                  "multi-tab close performs exactly one primary and one backup archive write")
        try check(removalOrder.last == selected.id && removalOrder.count == closing.count,
                  "batch teardown removes the active tab last without intermediate replacements")
        try check(session.selected === kept && session.tabs.count == 1 && session.showingTabs &&
                  !session.tabs.contains { $0 === selected }, "batch close keeps its unselected neighbor and overview state")
        try check(archive.load()?.session.tabs.map(\.id) == [kept.id], "single batch archive contains the complete final tab state")
        primaryWrites = 0; backupWrites = 0
        try check(session.closeTabs(Set(closing.map(\.id))) == 0 && primaryWrites == 0 && backupWrites == 0,
                  "a stale closed selection performs no additional archive writes")
        let single = session.newTab()
        _ = session.saveNow()
        primaryWrites = 0; backupWrites = 0
        session.close(single.id)
        try check(primaryWrites == 1 && backupWrites == 1 && session.selected === kept,
                  "ordinary single-tab close still persists immediately")
        let final = session.newTab()
        _ = session.saveNow()
        primaryWrites = 0; backupWrites = 0; rejectPrimary = true
        try check(session.closeTabs([final.id]) == 1 && primaryWrites == 1 && backupWrites == 1 &&
                  session.selected.errorMessage == "Your browsing changes could not be saved on this device.",
                  "a failed batch commit reports its save error on the remaining selected tab")
    }

    private func premiumPrivateTabRowChecks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PremiumPrivateRow-" + UUID().uuidString)
        let suite = "PremiumPrivateRow-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        var primaryWrites = 0
        let archive = BrowserArchiveStore(directory: directory, writeData: { data, url, options in
            if url.lastPathComponent == "session.json" { primaryWrites += 1 }
            try data.write(to: url, options: options)
        })
        let session = BrowserSession(storage: defaults, archiveStore: archive, dataStore: .nonPersistent())
        defer {
            session.closePrivateTabs(); session.tabs.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let tab = session.newTab(privateTab: true)
        try await load(tab, "")
        session.showingTabs = true
        var renderedTitle = ""
        var renderedSite = ""
        var renderEvents = 0
        let row = UIHostingController(rootView: TabListRow(tab: tab, current: true, didRender: { title, site in
            renderedTitle = title; renderedSite = site; renderEvents += 1
        }))
        host.addChild(row)
        row.view.frame = CGRect(x: 0, y: 0, width: host.view.bounds.width, height: 120)
        host.view.addSubview(row.view); row.didMove(toParent: host)
        defer { row.willMove(toParent: nil); row.view.removeFromSuperview(); row.removeFromParent() }
        try await wait { renderedTitle == tab.title && renderedSite == "127.0.0.1" }
        let initialEvents = renderEvents
        var sessionPublications = 0
        let observation = session.objectWillChange.sink { sessionPublications += 1 }
        defer { observation.cancel() }
        _ = session.saveNow()
        primaryWrites = 0
        let updatedTitle = "Private title updates independently"
        _ = try await js(tab, "document.title='Private title updates independently'; true")
        try await wait { tab.title == updatedTitle && renderedTitle == updatedTitle }
        try check(renderEvents > initialEvents && sessionPublications == 0,
                  "a hosted list row observes a private page title without normal-session publication")
        tab.webView.load(URLRequest(url: URL(string: "about:blank")!))
        try await wait { !tab.isLoading && tab.webView.url?.absoluteString == "about:blank" && renderedSite == "Start Page" }
        try check(session.showingTabs && renderedSite == tab.siteName && sessionPublications == 0,
                  "private navigation refreshes the rendered list-row site while the overview stays open")
        try check(primaryWrites == 0 && archive.load()?.session.tabs.contains { $0.id == tab.id } == false,
                  "private row updates remain unarchived and trigger no normal-session writes")
        session.tabOverviewStyle = .list
        sessionPublications = 0
        var filteredIDs: [UUID] = []
        var filterRenders = 0
        let overview = UIHostingController(rootView: TabOverview(session: session, search: "needle", didRenderTabs: { ids in
            filteredIDs = ids; filterRenders += 1
        }))
        host.addChild(overview); overview.view.frame = host.view.bounds
        host.view.addSubview(overview.view); overview.didMove(toParent: host)
        defer { overview.willMove(toParent: nil); overview.view.removeFromSuperview(); overview.removeFromParent() }
        try await wait { filterRenders > 0 && filteredIDs.isEmpty }
        _ = try await js(tab, "document.title='Private needle arrives'; true")
        try await wait { tab.title == "Private needle arrives" && filteredIDs == [tab.id] }
        try check(session.showingTabs && sessionPublications == 0 && primaryWrites == 0,
                  "a renamed private page enters a rendered nonempty tab search without changing the query or session")
        _ = try await js(tab, "document.title='Private renamed away'; true")
        try await wait { tab.title == "Private renamed away" && filteredIDs.isEmpty }
        try check(filterRenders >= 3 && sessionPublications == 0 && primaryWrites == 0,
                  "a renamed private page leaves the same rendered search with no normal archive writes")
    }

    private func premiumTabWriteFailureChecks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("PremiumTabWriteFailure-" + UUID().uuidString)
        let suite = "PremiumTabWriteFailure-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        var failPrimaryWrite = false
        let archive = BrowserArchiveStore(directory: directory, writeData: { data, url, options in
            if failPrimaryWrite, url.lastPathComponent == "session.json" { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: options)
        })
        let session = BrowserSession(storage: defaults, archiveStore: archive, dataStore: .nonPersistent())
        defer {
            session.tabs.forEach { $0.close() }
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let first = session.selected
        let workspace = session.workspaceID
        let second = session.newTab()
        session.createWorkspace("Destination")
        let destination = session.workspaceID
        session.switchWorkspace(workspace)
        session.select(first.id)
        session.showingTabs = true
        try check(session.saveNow(), "tab write-failure regression seeds a durable baseline")
        let order = session.visibleTabs.map(\.id)
        let selectedView = first.webView
        failPrimaryWrite = true
        try check(!session.reorderVisibleTabs(Array(order.reversed())), "failed durable reorder reports failure")
        try check(session.visibleTabs.map(\.id) == order && session.selected === first && first.webView === selectedView,
                  "failed reorder rolls back order without replacing selection or page")
        try check(session.moveTabs([first.id, second.id], to: destination) == 0,
                  "failed durable batch move reports no moved tabs")
        try check(first.workspaceID == workspace && second.workspaceID == workspace && session.workspaceID == workspace &&
                  session.selected === first && session.showingTabs,
                  "failed batch move restores workspace membership and preserves selection and overview")
        let disk = archive.load()!
        try check(disk.session.tabs.first { $0.id == first.id }?.workspaceID == workspace &&
                  disk.session.tabs.first { $0.id == second.id }?.workspaceID == workspace,
                  "failed tab writes leave the durable session at its original memberships")
    }
}
#endif
