import SwiftUI
import UIKit

/// A navigation canvas: favorites first, then the normal tabs already open in this workspace.
struct BrowserStartPage: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @ObservedObject var chrome: BrowserChromeState
    @ObservedObject var viewport: BrowserViewportState
    var onSearch: () -> Void = {}
    @AppStorage("startPage.showFavorites") private var showFavorites = true
    @AppStorage("startPage.showOpenTabs") private var showOpenTabs = true
    @AppStorage("startPage.showRecentSites") private var showRecentSites = false
    @State private var customizing = false
    @State private var editingFavorites = false
    @State private var editingFavorite: LibraryEntry?
    @State private var favoriteError = false
    @State private var scrollOffset: CGFloat = 0
    @StateObject private var recentSitesProjection = StartPageRecentSitesProjection()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var favoriteRibbonHeight = 112.0
    #if DEBUG
    var layoutDidChange: (([String: CGRect]) -> Void)?
    #endif

    private var privateStart: Bool { browser.isPrivate || session.privateMode }
    private var openTabs: [BrowserModel] {
        guard !privateStart else { return [] }
        let ids = StartPagePolicy.openTabIDs(session.tabs.map {
            .init(id: $0.id, address: $0.restorationURL?.absoluteString ?? "", workspaceID: $0.workspaceID,
                  lastUsed: $0.lastUsed, isPrivate: $0.isPrivate)
        }, selectedID: browser.id, workspaceID: session.workspaceID, isPrivate: false)
        let lookup = Dictionary(session.tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { lookup[$0] }
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    heading
                        .startPageFrame("heading", update: reportFrame)
                        .startPageClearance()
                    searchInvitation
                        .startPageFrame("search", update: reportFrame)
                        .startPageClearance()
                    if privateStart { privateExplanation.startPageFrame("private", update: reportFrame).startPageClearance() }
                    else {
                        if showFavorites { favoritesSection.startPageFrame("favorites", update: reportFrame).startPageClearance() }
                        if showOpenTabs, !openTabs.isEmpty { openTabsSection.startPageFrame("openTabs", update: reportFrame).startPageClearance() }
                        if showRecentSites, !recentSitesProjection.sites.isEmpty {
                            recentSitesSection.startPageFrame("recentSites", update: reportFrame).startPageClearance()
                        }
                        customizeButton.startPageFrame("customize", update: reportFrame).startPageClearance()
                    }
                }
                .frame(maxWidth: 800, alignment: .leading)
                .padding(.horizontal, dynamicTypeSize.isAccessibilitySize ? 20 : 28)
                .padding(.top, max(32, geometry.safeAreaInsets.top + 20))
                .padding(.bottom, chrome.expandedHeight + viewport.bottomControlLift + geometry.safeAreaInsets.bottom + 44)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, value in scrollOffset = value }
            .environment(\.startPageScrollOffset, scrollOffset)
            .background { BrowserWallpaper() }
        }
        .sheet(isPresented: $customizing) {
            StartPageCustomization(showFavorites: $showFavorites, showOpenTabs: $showOpenTabs,
                                   showRecentSites: $showRecentSites)
        }
        .sheet(isPresented: $editingFavorites) { StartPageFavoritesManager(session: session) }
        .sheet(item: $editingFavorite) { StartPageFavoriteEditor(session: session, entry: $0) }
        .alert("Couldn’t Update Favorites", isPresented: $favoriteError) {
            Button("OK", role: .cancel) {}
        } message: { Text("Your favorites are unchanged. Please try again.") }
        .onAppear { bindRecentSites() }
        .onChange(of: showRecentSites) { _, _ in bindRecentSites() }
        .onChange(of: privateStart) { _, isPrivate in
            bindRecentSites()
            if isPrivate { customizing = false; editingFavorites = false; editingFavorite = nil }
        }
    }

    private func bindRecentSites() { recentSitesProjection.bind(to: session, enabled: showRecentSites && !privateStart) }

    private func reportFrame(_ name: String, _ frame: CGRect) {
        #if DEBUG
        layoutDidChange?([name: frame])
        #endif
    }

    private var heading: some View {
        Group {
            if privateStart {
                VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "hand.raised")
                    .font(.title2.weight(.medium)).foregroundStyle(.secondary).accessibilityHidden(true)
                    Text("Private Browsing").font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                }
            } else if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    workspaceMenu
                    Text("DuoBrowser").font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("DuoBrowser").font(.largeTitle.bold()).fixedSize()
                            .accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 0)
                        workspaceMenu.fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DuoBrowser").font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        workspaceMenu
                    }
                }
            }
        }
    }

    private var workspaceMenu: some View {
        Menu {
            ForEach(session.workspaces) { workspace in
                Button {
                    guard !privateStart else { return }
                    session.switchWorkspace(workspace.id)
                } label: {
                    if workspace.id == session.workspaceID { Label(workspace.name, systemImage: "checkmark") }
                    else { Text(verbatim: workspace.name) }
                }
            }
            Divider()
            Button("Manage Workspaces", systemImage: "square.stack") { session.showingWorkspaces = true }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "square.stack").imageScale(.small)
                Text(verbatim: session.workspaceName).lineLimit(2)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary).frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Workspace, \(session.workspaceName)")
        .accessibilityHint("Switch or manage workspaces")
    }

    private var searchInvitation: some View {
        Button(action: onSearch) {
            HStack(spacing: 14) {
                Image(systemName: "magnifyingglass").font(.title3.weight(.medium)).accessibilityHidden(true)
                Text("Search or enter website")
                    .font(.body).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.vertical, 19)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24))
        .accessibilityLabel(privateStart ? "Search privately or enter website" : "Search or enter website")
        .accessibilityIdentifier("start.search")
    }

    private var privateExplanation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("A separate space to browse.").font(.headline)
            Text("Private tabs don’t appear in history or on your normal start page. Website data is removed when you close every private tab.")
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Private browsing doesn’t hide your activity from websites or your network.")
                .font(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeading("Favorites", action: session.favorites.isEmpty ? "Add" : "Edit") {
                if session.favorites.isEmpty { editingFavorite = LibraryEntry(address: "", title: "", isFavorite: true) }
                else { editingFavorites = true }
            }
            if session.favorites.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your everyday sites, close at hand.").font(.body.weight(.medium))
                    Text("Add a favorite here, or save a page while you browse.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.fixedSize(horizontal: false, vertical: true)
            } else {
                if dynamicTypeSize.isAccessibilitySize {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 132), spacing: 16)], alignment: .leading, spacing: 24) {
                        ForEach(Array(session.favorites.prefix(12))) { entry in favorite(entry) }
                    }
                } else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment: .top, spacing: 18) {
                            ForEach(Array(session.favorites.prefix(12))) { entry in favorite(entry).frame(width: 78) }
                        }
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)
                    .contentMargins(.trailing, 8, for: .scrollContent)
                    .frame(height: favoriteRibbonHeight)
                }
                if session.favorites.count > 12 {
                    Button("All \(session.favorites.count) Favorites", systemImage: "star") { editingFavorites = true }
                        .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                }
            }
        }
        .accessibilityIdentifier("start.favorites")
    }

    private func favorite(_ entry: LibraryEntry) -> some View {
        Button {
            guard !privateStart else { return }
            browser.navigate(to: entry.address)
        } label: {
            VStack(spacing: 10) {
                WebsiteIcon(address: entry.address)
                Text(verbatim: entry.title.isEmpty ? StartPagePolicy.host(entry.address) ?? entry.address : entry.title)
                    .font(.caption).lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .top).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this favorite")
        .contextMenu {
            Button("Edit Favorite", systemImage: "pencil") { editingFavorite = entry }
            Button("Open in New Tab", systemImage: "plus.square") {
                guard !privateStart else { return }
                session.newTab(url: URL(string: entry.address))
            }
            Button("Remove from Favorites", systemImage: "star.slash") {
                if !session.removeStartPageFavorite(entry.id) { favoriteError = true }
            }
        }
    }

    private var openTabsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            sectionHeading("Open Tabs", action: "Show All") { session.showTabs() }
                .padding(.bottom, 8)
            ForEach(openTabs) { tab in
                StartPageOpenTab(tab: tab) {
                    guard !privateStart, session.tabs.contains(where: { $0.id == tab.id && !$0.isPrivate }),
                          tab.workspaceID == session.workspaceID else { return }
                    session.select(tab.id)
                }
                if tab.id != openTabs.last?.id { Divider().padding(.leading, 50) }
            }
        }
        .accessibilityIdentifier("start.openTabs")
    }

    private var recentSitesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Recent Sites").font(.title3.bold()).accessibilityAddTraits(.isHeader).padding(.bottom, 12)
            ForEach(recentSitesProjection.sites) { entry in
                Button {
                    guard !privateStart else { return }
                    browser.navigate(to: entry.address)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "clock").font(.body).foregroundStyle(.secondary).frame(width: 36)
                        Text(verbatim: StartPagePolicy.host(entry.address) ?? entry.title)
                            .font(.body).lineLimit(2).foregroundStyle(.primary)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 12).frame(minHeight: 48).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
        .accessibilityIdentifier("start.recentSites")
    }

    private var customizeButton: some View {
        HStack {
            Spacer()
            Button("Customize", systemImage: "slider.horizontal.3") { customizing = true }
                .font(.subheadline.weight(.medium)).padding(.horizontal, 16).frame(minHeight: 44)
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityLabel("Customize Start Page")
                .accessibilityIdentifier("start.customize")
        }
        .padding(.top, 4)
    }

    private func sectionHeading(_ title: String, action: String, perform: @escaping () -> Void) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 0)
                Button(action, action: perform).font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
                Button(action, action: perform).font(.subheadline.weight(.medium)).frame(minHeight: 44)
            }
        }
    }
}

private struct StartPageOpenTab: View {
    @ObservedObject var tab: BrowserModel
    let select: () -> Void
    var body: some View {
        Button(action: select) {
            HStack(spacing: 14) {
                Image(systemName: tab.isPinned ? "pin.fill" : "globe")
                    .font(.title3).foregroundStyle(.secondary).frame(width: 36).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: tab.title).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                    Text(verbatim: tab.siteName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 12).frame(minHeight: 64).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Returns to your open tab")
    }
}

private struct StartPageCustomization: View {
    @Binding var showFavorites: Bool
    @Binding var showOpenTabs: Bool
    @Binding var showRecentSites: Bool
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Show on Start Page") {
                    Toggle("Favorites", isOn: $showFavorites)
                    Toggle("Open Tabs", isOn: $showOpenTabs)
                    Toggle("Recent Sites", isOn: $showRecentSites)
                }
                Section {
                    Button("Restore Default Sections") {
                        showFavorites = true; showOpenTabs = true; showRecentSites = false
                    }
                }
            }
            .navigationTitle("Start Page").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// One child is measured at full width and at bounded candidate widths; no duplicate view tree is created.
struct StartPageClearance: ViewModifier {
    @State private var regions: [CGRect] = []
    @Environment(\.startPageScrollOffset) private var scrollOffset
    init() {}
    func body(content: Content) -> some View {
        StartPageAvoidanceLayout(regions: regions) { content }
            .background {
                StartPageRegionReader(scrollOffset: scrollOffset) { regions = $0 }
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

private struct StartPageRegionReader: UIViewRepresentable {
    let scrollOffset: CGFloat
    let update: ([CGRect]) -> Void
    #if DEBUG
    @Environment(\.startPageTestRegions) private var testRegions
    #endif
    func makeUIView(context: Context) -> RegionView { RegionView() }
    func updateUIView(_ view: RegionView, context: Context) {
        view.update = update; view.setNeedsLayout()
        #if DEBUG
        view.testRegions = testRegions
        #endif
    }
    final class RegionView: UIView {
        var update: (([CGRect]) -> Void)?
        private var last: [CGRect] = []
        #if DEBUG
        var testRegions: [CGRect]?
        #endif
        override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
        override func layoutSubviews() {
            super.layoutSubviews()
            var next = reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
            #if DEBUG
            if let testRegions { next = testRegions }
            #endif
            guard next != last else { return }
            last = next
            DispatchQueue.main.async { [weak self] in
                guard let self, self.last == next else { return }
                self.update?(next)
            }
        }
    }
}

private struct StartPageAvoidanceLayout: Layout {
    let regions: [CGRect]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let ideal = child.sizeThatFits(.unspecified)
        let width = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? ideal.width
        return placement(width: width, child: child, direction: subviews.layoutDirection).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        let plan = placement(width: bounds.width, child: child, direction: subviews.layoutDirection)
        // SwiftUI mirrors Layout placement coordinates in RTL. Convert the physical UIKit rectangle
        // to that logical coordinate system while preserving the child's own text/layout direction.
        let x = subviews.layoutDirection == .rightToLeft ? bounds.width - plan.content.midX : plan.content.midX
        child.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + plan.content.midY), anchor: .center,
                    proposal: ProposedViewSize(width: plan.proposalWidth, height: plan.content.height))
    }

    private func placement(width: CGFloat, child: LayoutSubview, direction: LayoutDirection) -> StartPageLayout.Placement {
        StartPageLayout.placement(width: width, regions: regions, direction: direction) { candidate in
            child.sizeThatFits(ProposedViewSize(width: candidate, height: nil))
        }
    }
}

enum StartPageLayout {
    struct Placement: Equatable {
        var size: CGSize
        var content: CGRect
        var proposalWidth: CGFloat
        var insets: UIEdgeInsets {
            UIEdgeInsets(top: content.minY, left: content.minX, bottom: 0, right: size.width - content.maxX)
        }
    }

    static func placement(width: CGFloat, regions: [CGRect], direction: LayoutDirection = .leftToRight,
                          measure: (CGFloat) -> CGSize) -> Placement {
        guard width.isFinite, width > 0 else { return Placement(size: .zero, content: .zero, proposalWidth: 0) }
        let fullSize = measure(width)
        guard fullSize.width.isFinite, fullSize.width >= 0, fullSize.height.isFinite, fullSize.height >= 0 else {
            return Placement(size: .zero, content: .zero, proposalWidth: width)
        }
        let baseline = CGRect(x: direction == .rightToLeft ? width - fullSize.width : 0, y: 0,
                              width: fullSize.width, height: fullSize.height)
        let active = regions.filter { !$0.isNull && !$0.isInfinite && !$0.isEmpty }
        var hits = active.filter { $0.intersects(baseline) }
        if hits.isEmpty { return Placement(size: CGSize(width: width, height: fullSize.height), content: baseline, proposalWidth: width) }
        var left: CGFloat = 0
        var right: CGFloat = 0
        let minimumWidth = min(220, width * 0.6)
        // A later region may collide only after text wraps. Measure that actual height and try at
        // most three narrower lanes before falling back to the independent full-width measurement.
        for _ in 0..<3 {
            let previous = (left, right)
            for region in hits {
                if region.minX >= width - region.maxX { right = max(right, width - region.minX + 8) }
                else { left = max(left, region.maxX + 8) }
            }
            let lane = width - left - right
            guard lane >= minimumWidth, left != previous.0 || right != previous.1 else { break }
            let fitted = measure(lane)
            guard fitted.width.isFinite, fitted.height.isFinite, fitted.height >= 0, fitted.width <= lane + 0.5 else { break }
            let candidateX = left + (direction == .rightToLeft ? lane - fitted.width : 0)
            let candidate = CGRect(x: candidateX, y: 0, width: fitted.width, height: fitted.height)
            hits = active.filter { $0.intersects(candidate) }
            if hits.isEmpty {
                return Placement(size: CGSize(width: width, height: fitted.height), content: candidate, proposalWidth: lane)
            }
        }
        var content = baseline
        // Full-width fallback has its own measured height, so candidate wrapping cannot feed back
        // into the next pass. Moving below a collision expands native scroll content, never clips it.
        for _ in 0...active.count {
            guard let bottom = active.filter({ $0.intersects(content) }).map(\.maxY).max() else { break }
            content.origin.y = bottom + 8
        }
        return Placement(size: CGSize(width: width, height: content.maxY), content: content, proposalWidth: width)
    }
}

private struct StartPageScrollOffsetKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
private extension EnvironmentValues {
    var startPageScrollOffset: CGFloat {
        get { self[StartPageScrollOffsetKey.self] }
        set { self[StartPageScrollOffsetKey.self] = newValue }
    }
}

#if DEBUG
private struct StartPageTestRegionsKey: EnvironmentKey { static let defaultValue: [CGRect]? = nil }
extension EnvironmentValues {
    /// Debug synthetic layout fixture only. Production always reads UIKit reserved-region geometry.
    var startPageTestRegions: [CGRect]? {
        get { self[StartPageTestRegionsKey.self] }
        set { self[StartPageTestRegionsKey.self] = newValue }
    }
}
#endif

private extension View {
    func startPageClearance() -> some View { modifier(StartPageClearance()) }
    @ViewBuilder func startPageFrame(_ name: String, update: @escaping (String, CGRect) -> Void) -> some View {
        #if DEBUG
        background { StartPageFrameProbe(name: name, update: update).allowsHitTesting(false).accessibilityHidden(true) }
        #else
        self
        #endif
    }
}

#if DEBUG
private struct StartPageFrameProbe: UIViewRepresentable {
    let name: String
    let update: (String, CGRect) -> Void
    func makeUIView(context: Context) -> FrameView { FrameView() }
    func updateUIView(_ view: FrameView, context: Context) {
        view.name = name; view.update = update; view.setNeedsLayout()
    }
    final class FrameView: UIView {
        var name = "" { didSet { if name != oldValue { last = nil } } }
        var update: ((String, CGRect) -> Void)?
        private var last: CGRect?
        override func didMoveToWindow() { super.didMoveToWindow(); last = nil; setNeedsLayout() }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window else { return }
            let frame = convert(bounds, to: window)
            guard frame != last else { return }
            last = frame
            let key = name
            DispatchQueue.main.async { [weak self] in
                guard let self, self.last == frame else { return }
                self.update?(key, frame)
            }
        }
    }
}
#endif
