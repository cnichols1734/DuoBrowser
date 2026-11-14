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

/// Clear only a section that actually intersects a current system occlusion. The rest keeps its full width.
struct StartPageClearance: ViewModifier {
    @State private var insets = UIEdgeInsets.zero
    @Environment(\.startPageScrollOffset) private var scrollOffset
    @Environment(\.layoutDirection) private var layoutDirection
    init() {}
    func body(content: Content) -> some View {
        content
            .padding(StartPageLayout.directionalPadding(insets, direction: layoutDirection))
            .background {
                StartPageRegionReader(applied: insets, scrollOffset: scrollOffset) { insets = $0 }
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

private struct StartPageRegionReader: UIViewRepresentable {
    let applied: UIEdgeInsets
    let scrollOffset: CGFloat
    let update: (UIEdgeInsets) -> Void
    #if DEBUG
    @Environment(\.startPageTestRegions) private var testRegions
    #endif
    func makeUIView(context: Context) -> RegionView { RegionView() }
    func updateUIView(_ view: RegionView, context: Context) {
        view.applied = applied; view.update = update; view.setNeedsLayout()
        #if DEBUG
        view.testRegions = testRegions
        #endif
    }
    final class RegionView: UIView {
        var applied = UIEdgeInsets.zero
        var update: ((UIEdgeInsets) -> Void)?
        private var last = UIEdgeInsets.zero
        #if DEBUG
        var testRegions: [CGRect]?
        #endif
        override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
        override func layoutSubviews() {
            super.layoutSubviews()
            var regions = reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
            #if DEBUG
            if let testRegions { regions = testRegions }
            #endif
            let next = StartPageLayout.clearance(in: bounds, applied: applied, regions: regions)
            guard next != last else { return }
            last = next
            DispatchQueue.main.async { [weak self] in
                guard let self, self.last == next else { return }
                self.update?(next)
            }
        }
    }
}

enum StartPageLayout {
    static func clearance(in bounds: CGRect, applied: UIEdgeInsets, regions: [CGRect]) -> UIEdgeInsets {
        // The probe surrounds padding. Reconstruct the content's baseline height so moving it
        // below a region does not increase the correction on every subsequent layout pass.
        let baseline = CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width,
                              height: max(0, bounds.height - applied.top - applied.bottom))
        guard !baseline.isEmpty, !baseline.isInfinite else { return .zero }
        let active = regions.filter { !$0.isNull && !$0.isInfinite && !$0.isEmpty }
        let hits = active.filter { $0.intersects(baseline) }
        var result = UIEdgeInsets.zero
        for region in hits {
            // Prefer the larger free side, then verify that the resulting lane is useful.
            let leftSpace = region.minX - baseline.minX
            let rightSpace = baseline.maxX - region.maxX
            if leftSpace >= rightSpace { result.right = max(result.right, baseline.maxX - region.minX + 8) }
            else { result.left = max(result.left, region.maxX - baseline.minX + 8) }
        }
        let minimumWidth = min(220, baseline.width * 0.6)
        if baseline.width - result.left - result.right < minimumWidth { result = .zero }
        var content = CGRect(x: baseline.minX + result.left, y: baseline.minY,
                             width: baseline.width - result.left - result.right, height: baseline.height)
        // Bottom padding alone leaves low/interior content covered. Move the entire section below
        // any remaining collision; padding expands the ScrollView's content rather than clipping it.
        for _ in 0...active.count {
            guard let bottom = active.filter({ $0.intersects(content) }).map(\.maxY).max() else { break }
            result.top = max(result.top, bottom - baseline.minY + 8)
            content.origin.y = baseline.minY + result.top
        }
        return result
    }

    static func directionalPadding(_ insets: UIEdgeInsets, direction: LayoutDirection) -> EdgeInsets {
        EdgeInsets(top: insets.top, leading: direction == .rightToLeft ? insets.right : insets.left,
                   bottom: insets.bottom, trailing: direction == .rightToLeft ? insets.left : insets.right)
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
