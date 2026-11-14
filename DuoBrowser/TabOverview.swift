import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable
import Combine

/// Refresh only the overview when a visible tab changes. Private updates never pass
/// through BrowserSession's normal-history/archive observers.
@MainActor
final class TabOverviewUpdates: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private var ids: [UUID] = []
    private var observation: AnyCancellable?

    func observe(_ tabs: [BrowserModel]) {
        let current = tabs.map(\.id)
        guard current != ids || observation == nil else { return }
        ids = current
        observation = Publishers.MergeMany(tabs.map(\.objectWillChange))
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.objectWillChange.send() }
    }

    func stop() { observation = nil; ids = [] }
}

struct TabOverview: View {
    @State private var showingRecentlyClosed = false
    @ObservedObject var session: BrowserSession
    @ObservedObject private var wallpaper = BrowserWallpaperStore.shared
    @StateObject private var tabUpdates = TabOverviewUpdates()
    @State private var search = ""
    @State private var selecting = false
    @State private var selectedTabs: Set<UUID> = []
    @State private var confirmClose = false
    @State private var manageWorkspaces = false
    @State private var appearance = false
    @State private var controlLift: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var photo: PhotosPickerItem?
    @State private var wallpaperError: String?
    @State private var operationError: String?
    @FocusState private var searchFocused: Bool
    @AppStorage("browser.tabBackgroundHex") private var backgroundHex = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ScaledMetric(relativeTo: .body) private var searchRowHeight = 44.0
    #if DEBUG
    private var didRenderTabs: (([UUID]) -> Void)?
    private var didMeasureHeader: ((UIView) -> Void)?
    private var didMeasureListViewport: ((UIView) -> Void)?
    private var didMeasureListLane: ((UIView) -> Void)?
    private var didMeasureListRow: ((UUID, UIView) -> Void)?
    #endif

    init(session: BrowserSession) { self.session = session }

    #if DEBUG
    init(session: BrowserSession, search: String, didRenderTabs: @escaping ([UUID]) -> Void,
         didMeasureHeader: ((UIView) -> Void)? = nil, didMeasureListViewport: ((UIView) -> Void)? = nil,
         didMeasureListLane: ((UIView) -> Void)? = nil, didMeasureListRow: ((UUID, UIView) -> Void)? = nil) {
        self.session = session
        _search = State(initialValue: search)
        self.didRenderTabs = didRenderTabs
        self.didMeasureHeader = didMeasureHeader
        self.didMeasureListViewport = didMeasureListViewport
        self.didMeasureListLane = didMeasureListLane
        self.didMeasureListRow = didMeasureListRow
    }
    #endif

    private var colorChoice: Binding<Color> {
        Binding(get: {
            guard let value = UInt32(backgroundHex, radix: 16), backgroundHex.count == 6 else { return .blue }
            return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
        }, set: { color in
            let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            guard resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return }
            backgroundHex = String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        })
    }
    private var filteredTabs: [BrowserModel] {
        session.visibleTabs.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
            || $0.siteName.localizedCaseInsensitiveContains(search) }
    }
    private var usesList: Bool { session.tabOverviewStyle == .list || dynamicTypeSize.isAccessibilitySize || voiceOver }
    private var scope: String { session.privateMode ? "Private" : session.workspaceName }

    var body: some View {
        #if DEBUG
        overview
            .onAppear { didRenderTabs?(filteredTabs.map(\.id)) }
            .onChange(of: filteredTabs.map(\.id)) { _, ids in didRenderTabs?(ids) }
        #else
        overview
        #endif
    }

    private var overview: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                header
                    .background {
                        #if DEBUG
                        CompactTabHeaderProbe(register: didMeasureHeader).allowsHitTesting(false).accessibilityHidden(true)
                        #endif
                    }
                    .modifier(StartPageClearance())
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                if filteredTabs.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if usesList { tabList }
                else {
                    TabStack(tabs: filteredTabs, selectedID: session.selectedID,
                             reduceMotion: reduceMotion, allowsDismiss: !selecting,
                             refreshID: selecting ? AnyHashable(selectedTabs) : nil, close: { session.close($0) }) { tab, close in
                        tabItem(tab, close: close)
                    }
                }
                ClosedTabNotice(session: session)
                footer
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
                    .padding(.horizontal, 16).padding(.top, 8)
                    .padding(.bottom, max(8, geometry.safeAreaInsets.bottom) + controlLift)
            }
            .background {
                BrowserWallpaper()
                OverviewRegionReader(footerHeight: footerHeight, bottomInset: max(8, geometry.safeAreaInsets.bottom)) { lift, _ in
                    controlLift = lift
                }.allowsHitTesting(false)
                if reduceTransparency { Color(uiColor: .systemGroupedBackground) }
                else { Rectangle().fill(.ultraThinMaterial) }
            }
        }
        .ignoresSafeArea(.container)
        .statusBarHidden(true)
        .onAppear { if session.showingTabs { tabUpdates.observe(session.visibleTabs) } }
        .onDisappear { tabUpdates.stop() }
        .onChange(of: session.showingTabs) { _, showing in
            if showing { search = ""; searchFocused = false; endSelection(); tabUpdates.observe(session.visibleTabs) }
            else { tabUpdates.stop() }
        }
        .onChange(of: session.visibleTabs.map(\.id)) { _, ids in
            selectedTabs.formIntersection(ids)
            if session.showingTabs { tabUpdates.observe(session.visibleTabs) }
        }
        .onChange(of: session.privateMode) { _, _ in search = ""; endSelection() }
        .onChange(of: session.workspaceID) { _, _ in search = ""; endSelection() }
        .sheet(isPresented: $showingRecentlyClosed) { RecentlyClosedView(session: session) }
        .sheet(isPresented: $manageWorkspaces) { WorkspaceView(session: session) }
        .sheet(isPresented: $appearance) { appearanceSheet }
        .alert("Couldn’t Save Changes", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("OK") { operationError = nil }
        } message: { Text(operationError ?? "") }
        .confirmationDialog("Close \(selectedTabs.count) \(selectedTabs.count == 1 ? "tab" : "tabs")?", isPresented: $confirmClose) {
            Button("Close \(selectedTabs.count) \(selectedTabs.count == 1 ? "Tab" : "Tabs")", role: .destructive) {
                _ = session.closeTabs(selectedTabs)
                endSelection()
            }
        } message: { Text("Unsaved changes in these tabs will be lost.") }
        .task(id: photo) {
            guard let selectedPhoto = photo else { return }
            let token = wallpaper.beginImport()
            do {
                guard let imported = try await selectedPhoto.loadTransferable(type: WallpaperImport.self) else { throw CocoaError(.fileReadCorruptFile) }
                guard !Task.isCancelled, photo == selectedPhoto else { return }
                try wallpaper.save(imported, token: token)
                wallpaperError = nil; photo = nil
            } catch {
                guard !Task.isCancelled, photo == selectedPhoto else { return }
                wallpaperError = "This photo couldn't be used. Please choose another."; photo = nil
            }
        }
    }

    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    searchField
                    HStack {
                        Text(selecting ? "\(selectedTabs.count) Selected" : "\(session.visibleTabs.count) Tabs")
                            .font(.headline).accessibilityAddTraits(.isHeader)
                        Spacer(minLength: 8)
                        selectionButton
                    }
                }
            } else {
                HStack(spacing: 12) {
                    searchField
                    selectionButton
                }
            }
        }
    }

    private var selectionButton: some View {
        Button(selecting ? "Cancel" : "Select") {
            if selecting { endSelection() }
            else { selecting = true; searchFocused = false }
        }
        .font(.body.weight(.medium)).fixedSize()
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel(selecting ? "Cancel tab selection, \(selectedTabs.count) selected" : "Select Tabs")
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
            TextField("Search Tabs", text: $search)
                .textInputAutocapitalization(.never).autocorrectionDisabled().focused($searchFocused)
                .accessibilityLabel("Search Tabs")
            if !search.isEmpty {
                Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 44, height: 44) }
                    .accessibilityLabel("Clear tab search")
            }
        }
        .padding(.horizontal, 14).frame(minHeight: max(44, searchRowHeight))
        .background(Color(uiColor: .secondarySystemGroupedBackground).opacity(0.88), in: RoundedRectangle(cornerRadius: 14))
    }

    private var tabList: some View {
        TabListViewport {
            listContents
                .background {
                    #if DEBUG
                    CompactTabHeaderProbe(register: didMeasureListLane).allowsHitTesting(false).accessibilityHidden(true)
                    #endif
                }
        }
        .background {
            #if DEBUG
            CompactTabHeaderProbe(register: didMeasureListViewport).allowsHitTesting(false).accessibilityHidden(true)
            #endif
        }
    }

    private var listContents: some View {
        List(selection: $selectedTabs) {
            ForEach(filteredTabs) { tab in
                Group {
                    if selecting { listLabel(tab) }
                    else { Button { session.select(tab.id) } label: { listLabel(tab) }.buttonStyle(.plain) }
                }
                .background {
                    #if DEBUG
                    CompactTabHeaderProbe(register: { didMeasureListRow?(tab.id, $0) }).allowsHitTesting(false).accessibilityHidden(true)
                    #endif
                }
                .tag(tab.id)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                .contextMenu { tabContextMenu(tab) }
            }
            .onMove { from, to in
                guard search.isEmpty else { return }
                var ids = session.visibleTabs.map(\.id)
                ids.move(fromOffsets: from, toOffset: to)
                reorder(ids)
            }
            .moveDisabled(!search.isEmpty)
        }
        .listStyle(.plain).scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(selecting ? .active : .inactive))
        .scrollDismissesKeyboard(.interactively)
    }

    private func listLabel(_ tab: BrowserModel) -> some View {
        TabListRow(tab: tab, current: tab.id == session.selectedID,
                   selection: selecting ? selectedTabs.contains(tab.id) : nil)
    }

    private func tabItem(_ tab: BrowserModel, close: @escaping () -> Void) -> some View {
        TabPreview(tab: tab, selected: session.selectedID == tab.id, list: false,
                   select: {
                       if selecting {
                           if selectedTabs.contains(tab.id) { selectedTabs.remove(tab.id) }
                           else { selectedTabs.insert(tab.id) }
                       } else { session.select(tab.id) }
                   }, close: close, selection: selecting ? selectedTabs.contains(tab.id) : nil)
        .contextMenu { tabContextMenu(tab) }
    }

    @ViewBuilder private func tabContextMenu(_ tab: BrowserModel) -> some View {
        Button("Close Tab", systemImage: "xmark", role: .destructive) { session.close(tab.id) }
        Button(tab.isPinned ? "Unpin Tab" : "Pin Tab", systemImage: "pin") { session.togglePin(tab) }
        Button("Move Earlier", systemImage: "arrow.up") { move(tab, by: -1) }.disabled(!canMove(tab, by: -1))
        Button("Move Later", systemImage: "arrow.down") { move(tab, by: 1) }.disabled(!canMove(tab, by: 1))
        if !tab.isPrivate {
            Menu("Move to Workspace") {
                ForEach(session.workspaces.filter { $0.id != tab.workspaceID }) { workspace in
                    Button(workspace.name) { _ = move([tab.id], to: workspace.id) }
                }
            }
        }
    }

    private func canMove(_ tab: BrowserModel, by direction: Int) -> Bool {
        let tabs = session.visibleTabs
        guard let index = tabs.firstIndex(where: { $0.id == tab.id }), tabs.indices.contains(index + direction) else { return false }
        return tabs[index + direction].isPinned == tab.isPinned
    }
    private func move(_ tab: BrowserModel, by direction: Int) {
        guard canMove(tab, by: direction), let index = session.visibleTabs.firstIndex(where: { $0.id == tab.id }) else { return }
        var ids = session.visibleTabs.map(\.id)
        ids.swapAt(index, index + direction)
        reorder(ids)
    }
    private func reorder(_ ids: [UUID]) {
        if !session.reorderVisibleTabs(ids) { operationError = "Your browsing changes could not be saved on this device. Try again." }
    }
    @discardableResult private func move(_ ids: Set<UUID>, to workspace: UUID) -> Bool {
        guard session.moveTabs(ids, to: workspace) > 0 else {
            operationError = "Your browsing changes could not be saved on this device. Try again."
            return false
        }
        return true
    }
    private func endSelection() { selecting = false; selectedTabs.removeAll() }

    private var footer: some View {
        Group {
            if selecting {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            selectionAllButton
                            HStack(spacing: 20) { selectionMoveMenu; Spacer(minLength: 0); selectionCloseButton }
                        }
                    } else {
                        HStack(spacing: 16) {
                            selectionAllButton
                            Spacer(minLength: 0)
                            selectionMoveMenu
                            selectionCloseButton
                        }
                    }
                }
                .font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 52)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20))
            } else {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) {
                            modeMenu
                            HStack(spacing: 12) {
                                newTabButton
                                Spacer(minLength: 0)
                                overviewOptions
                                doneButton
                            }
                        }
                    } else {
                        HStack(spacing: 12) {
                            newTabButton
                            Spacer(minLength: 0)
                            modeMenu
                            Spacer(minLength: 0)
                            overviewOptions
                            doneButton
                        }
                    }
                }
                .font(.title3).buttonStyle(.plain)
            }
        }
    }

    private var newTabButton: some View {
        Button { session.newTab() } label: { Image(systemName: "plus").frame(width: 48, height: 48) }
            .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel("New Tab")
    }

    private var overviewOptions: some View {
        Menu {
            Picker("Tab Layout", selection: $session.tabOverviewStyle) {
                ForEach(TabOverviewStyle.allCases, id: \.self) { style in Label(style.title, systemImage: style.symbol).tag(style) }
            }
            if !session.privateMode {
                Button("Recently Closed", systemImage: "clock.arrow.circlepath") { showingRecentlyClosed = true }
                Button("Manage Workspaces", systemImage: "square.stack") { manageWorkspaces = true }
            }
            Button("Tab Appearance", systemImage: "photo") { appearance = true }
        } label: { Image(systemName: "ellipsis").frame(width: 48, height: 48) }
            .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel("Tab options")
    }

    private var doneButton: some View {
        Button { session.showingTabs = false } label: {
            Image(systemName: "checkmark").fontWeight(.semibold).frame(width: 48, height: 48)
        }.buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel("Done")
    }

    private var selectionAllButton: some View {
        let ids = Set(filteredTabs.map(\.id))
        let allSelected = !ids.isEmpty && ids.isSubset(of: selectedTabs)
        return Button(allSelected ? "Deselect All" : "Select All") {
            if allSelected { selectedTabs.subtract(ids) }
            else { selectedTabs.formUnion(ids) }
        }.frame(minHeight: 44)
    }
    @ViewBuilder private var selectionMoveMenu: some View {
        if !session.privateMode {
            Menu {
                ForEach(session.workspaces.filter { $0.id != session.workspaceID }) { workspace in
                    Button(workspace.name) { if move(selectedTabs, to: workspace.id) { endSelection() } }
                }
            } label: { Label("Move", systemImage: "folder").frame(minHeight: 44) }
            .disabled(selectedTabs.isEmpty || session.workspaces.count < 2)
        }
    }
    private var selectionCloseButton: some View {
        Button("Close \(selectedTabs.count)", systemImage: "trash", role: .destructive) { confirmClose = true }
            .frame(minHeight: 44).disabled(selectedTabs.isEmpty)
    }

    private var modeMenu: some View {
        Menu {
            Button("Tabs") { search = ""; session.switchMode(false) }
            Button("Private") { search = ""; session.switchMode(true) }
            if session.privateMode { Button("Close All Private Tabs", role: .destructive) { session.closePrivateTabs() } }
            else {
                Section("Workspaces") {
                    ForEach(session.workspaces) { workspace in
                        Button(workspace.name) { search = ""; session.switchWorkspace(workspace.id); session.showingTabs = true }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(session.privateMode ? "Private" : scope).lineLimit(1)
                Text("· \(session.visibleTabs.count)").monospacedDigit().foregroundStyle(.secondary).fixedSize()
            }
            .font(.subheadline.weight(.semibold)).minimumScaleFactor(0.8)
            .padding(.horizontal, 16).frame(minHeight: 48)
        }
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel("Browsing mode, \(scope), \(session.visibleTabs.count) open")
    }

    private var appearanceSheet: some View {
        NavigationStack {
            Form {
                Section("Wallpaper") {
                    PhotosPicker("Choose Photo", selection: $photo, matching: .images)
                    if wallpaper.image != nil || photo != nil {
                        Button("Remove Photo") { photo = nil; wallpaper.remove(); wallpaperError = nil }
                    }
                    ColorPicker("Background tint", selection: colorChoice, supportsOpacity: false)
                    if !backgroundHex.isEmpty { Button("Reset Tint") { backgroundHex = "" } }
                    if let wallpaperError { Text(wallpaperError).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Tab Appearance")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { appearance = false } } }
        }.presentationDetents([.medium])
    }
}

/// Each tab publishes independently. Private page changes must update its row without
/// notifying the normal session, history or archive.
struct TabListRow: View {
    @ObservedObject var tab: BrowserModel
    let current: Bool
    var selection: Bool?
    #if DEBUG
    var didRender: ((String, String) -> Void)?
    #endif

    var body: some View {
        #if DEBUG
        row
            .onAppear { didRender?(tab.title, tab.siteName) }
            .onChange(of: tab.title) { _, title in didRender?(title, tab.siteName) }
            .onChange(of: tab.address) { _, _ in didRender?(tab.title, tab.siteName) }
        #else
        row
        #endif
    }

    private var row: some View {
        HStack(spacing: 14) {
            Image(systemName: tab.isPinned ? "pin.fill" : "globe")
                .font(.title3).foregroundStyle(.secondary).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(tab.title).font(.body.weight(.semibold)).lineLimit(2)
                Text(tab.siteName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if selection == nil, current {
                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(Color.accentColor)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits((selection ?? current) ? [.isSelected] : [])
    }
}

/// The reader remains on the original list allocation; resizing the clear lane cannot change its
/// region coordinates. One List identity retains selection/scroll state as that lane moves.
private struct TabListViewport<Content: View>: View {
    @State private var regions: [CGRect]?
    @Environment(\.layoutDirection) private var direction
    private let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        GeometryReader { geometry in
            let clear = regions.map { TabListViewportGeometry.clearRect(in: CGRect(origin: .zero, size: geometry.size), regions: $0, direction: direction) } ?? .zero
            content()
                .frame(width: max(1, clear.width), height: max(1, clear.height))
                .clipped()
                .opacity(clear.isEmpty ? 0 : 1)
                .allowsHitTesting(!clear.isEmpty)
                .accessibilityHidden(clear.isEmpty)
                .position(x: direction == .rightToLeft ? geometry.size.width - clear.midX : clear.midX, y: clear.midY)
        }
        .background { TabListRegionReader { regions = $0 }.allowsHitTesting(false).accessibilityHidden(true) }
    }
}

enum TabListViewportGeometry {
    static func clearRect(in bounds: CGRect, regions: [CGRect], direction: LayoutDirection) -> CGRect {
        guard !bounds.isEmpty, !bounds.isInfinite else { return .zero }
        let active = regions.filter { !$0.isNull && !$0.isInfinite && !$0.isEmpty && $0.intersects(bounds) }
        var candidates = [bounds]
        let minimumWidth = min(160, bounds.width), minimumHeight = min(88, bounds.height)
        func ordered(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
            let leftArea = lhs.width * lhs.height, rightArea = rhs.width * rhs.height
            if leftArea != rightArea { return leftArea > rightArea }
            if lhs.minY != rhs.minY { return lhs.minY < rhs.minY }
            return direction == .rightToLeft ? lhs.maxX > rhs.maxX : lhs.minX < rhs.minX
        }
        for region in active {
            let excluded = region.insetBy(dx: -8, dy: -8)
            var next: [CGRect] = []
            for candidate in candidates {
                if !candidate.intersects(excluded) { next.append(candidate); continue }
                let pieces = [
                    CGRect(x: candidate.minX, y: candidate.minY, width: max(0, excluded.minX - candidate.minX), height: candidate.height),
                    CGRect(x: max(candidate.minX, excluded.maxX), y: candidate.minY, width: max(0, candidate.maxX - excluded.maxX), height: candidate.height),
                    CGRect(x: candidate.minX, y: candidate.minY, width: candidate.width, height: max(0, excluded.minY - candidate.minY)),
                    CGRect(x: candidate.minX, y: max(candidate.minY, excluded.maxY), width: candidate.width, height: max(0, candidate.maxY - excluded.maxY))
                ]
                for piece in pieces where piece.width >= minimumWidth && piece.height >= minimumHeight && !next.contains(piece) { next.append(piece) }
            }
            // Every retained candidate has cleared every processed region. Bound work without
            // dropping any system exclusion; if no useful lane survives the List is noninteractive.
            candidates = Array(next.sorted(by: ordered).prefix(64))
        }
        return candidates.sorted(by: ordered).first ?? .zero
    }
}

private struct TabListRegionReader: UIViewRepresentable {
    let update: ([CGRect]) -> Void
    #if DEBUG
    @Environment(\.tabListTestRegionsInWindow) private var testRegions
    #endif
    func makeUIView(context: Context) -> RegionView { RegionView() }
    func updateUIView(_ view: RegionView, context: Context) {
        view.update = update
        #if DEBUG
        view.testRegions = testRegions
        #endif
        view.setNeedsLayout()
    }
    final class RegionView: UIView {
        var update: (([CGRect]) -> Void)?
        private var last: [CGRect]?
        #if DEBUG
        var testRegions: [CGRect]?
        #endif
        override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
        override func layoutSubviews() {
            super.layoutSubviews()
            var next = reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
            #if DEBUG
            if let testRegions, let window { next = testRegions.map { convert($0, from: window) } }
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

#if DEBUG
private struct TabListTestRegionsInWindowKey: EnvironmentKey { static let defaultValue: [CGRect]? = nil }
extension EnvironmentValues {
    var tabListTestRegionsInWindow: [CGRect]? {
        get { self[TabListTestRegionsInWindowKey.self] }
        set { self[TabListTestRegionsInWindowKey.self] = newValue }
    }
}

private struct CompactTabHeaderProbe: UIViewRepresentable {
    let register: ((UIView) -> Void)?
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
        register?(view)
    }
}


#endif

private struct TabPreview: View {
    @ObservedObject var tab: BrowserModel
    let selected: Bool
    let list: Bool
    let select: () -> Void
    let close: () -> Void
    var selection: Bool?
    @EnvironmentObject private var geometry: TabCardGeometry

    var body: some View {
        Group {
            if list {
                HStack(alignment: .center, spacing: 8) {
                    Button(action: select) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(tab.title).font(.headline).lineLimit(2)
                            Text(tab.siteName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(selection != nil ? "Select tab" : tab.isPinned ? "Pinned tab" : "Open tab"), \(tab.title)")
                    .accessibilityAddTraits((selection ?? selected) ? [.isButton, .isSelected] : .isButton)
                    Button(action: close) { Image(systemName: "xmark").font(.system(size: 20)).frame(width: 52, height: 52) }
                        .accessibilityLabel("Close tab, \(tab.title)")
                }
                .buttonStyle(.plain).padding(12)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            } else { previewCard }
        }.accessibilityElement(children: .contain)
    }
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                Button(action: select) {
                    GeometryReader { geometry in
                        Group {
                            if tab.showingStartPage {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(tab.isPrivate ? "Private Browsing" : "Start Page").font(.headline)
                                    if !tab.isPrivate { Text("Favorites").font(.caption.weight(.semibold)).foregroundStyle(.primary) }
                                    Spacer()
                                }
                                .padding(16).frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                            } else if let image = tab.snapshot {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "globe").font(.largeTitle).foregroundStyle(.primary)
                                    Text(tab.siteName).font(.callout).foregroundStyle(.primary).lineLimit(2)
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                            }
                        }
                        .background { BrowserWallpaper() }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(selection != nil ? "Select tab" : tab.isPinned ? "Pinned tab" : "Open tab"), \(tab.title)")
                .accessibilityAddTraits((selection ?? selected) ? [.isButton, .isSelected] : .isButton)

                if let origin = geometry.closeOrigin, let selection {
                    Image(systemName: selection ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 27, weight: .medium))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(selection ? Color.accentColor : Color.primary, Color(uiColor: .systemBackground))
                        .frame(width: 48, height: 48)
                        .position(x: origin.x + 24, y: origin.y + 24)
                        .allowsHitTesting(false).accessibilityHidden(true)
                } else if let origin = geometry.closeOrigin {
                    Button(action: close) {
                        Image(systemName: "xmark").font(.system(size: 16, weight: .medium))
                            .frame(width: 32, height: 32)
                            .glassEffect(.regular.interactive(), in: Circle())
                            .frame(width: 48, height: 48).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .position(x: origin.x + 24, y: origin.y + 24)
                    .accessibilityLabel("Close tab, \(tab.title)")
                }
            }
        }
    }
}

/// Downsample within the provider file's lifetime; never materialize the full photo or leave a temporary copy.
struct WallpaperImport: Transferable, Sendable {
    let jpeg: Data
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in try Self(file: received.file) }
    }

    init(file: URL) throws {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 40 * 1024 * 1024,
              let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary), let data = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        jpeg = data
    }
}

/// App-owned wallpaper: bounded file import with stale-result protection.
@MainActor
final class BrowserWallpaperStore: ObservableObject {
    static let shared = BrowserWallpaperStore()
    @Published private(set) var image: UIImage?
    private let file: URL
    private var generation = UUID()

    init(file: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BrowserWallpaper.jpg")) {
        self.file = file
        image = UIImage(contentsOfFile: file.path)
    }

    func beginImport() -> UUID { generation = UUID(); return generation }

    func save(_ imported: WallpaperImport, token: UUID) throws {
        guard token == generation else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try imported.jpeg.write(to: file, options: .atomic)
        image = UIImage(data: imported.jpeg)
    }

    func remove() { generation = UUID(); try? FileManager.default.removeItem(at: file); image = nil }
}

struct BrowserWallpaper: View {
    @ObservedObject private var wallpaper = BrowserWallpaperStore.shared
    @AppStorage("browser.tabBackgroundHex") private var backgroundHex = ""
    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        guard backgroundHex.count == 6, let value = UInt32(backgroundHex, radix: 16) else { return .teal }
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                if let image = wallpaper.image {
                    Image(uiImage: image).resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                } else {
                    LinearGradient(colors: [tint.opacity(0.55), Color(uiColor: .systemGroupedBackground), tint.opacity(0.28)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                // Keep primary text readable even over pure white/black photos.
                (colorScheme == .dark ? Color.black : Color.white).opacity(wallpaper.image == nil ? 0 : 0.72)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct OverviewRegionReader: UIViewRepresentable {
    let footerHeight: CGFloat
    let bottomInset: CGFloat
    let changed: (CGFloat, UIEdgeInsets) -> Void
    func makeUIView(context: Context) -> OverviewRegionView { OverviewRegionView() }
    func updateUIView(_ view: OverviewRegionView, context: Context) {
        view.footerHeight = footerHeight; view.bottomInset = bottomInset
        view.changed = changed; view.setNeedsLayout()
    }
}

final class OverviewRegionView: UIView {
    var footerHeight: CGFloat = 0
    var bottomInset: CGFloat = 8
    var changed: ((CGFloat, UIEdgeInsets) -> Void)?
    private var lastLift: CGFloat = -1
    private var lastInsets = UIEdgeInsets.zero
    override func layoutSubviews() {
        super.layoutSubviews()
        let regions = reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
        let lift = Self.footerLift(in: bounds, height: footerHeight, bottomInset: bottomInset, regions: regions)
        let insets = Self.clearInsets(in: bounds, regions: regions)
        guard lift != lastLift || insets != lastInsets else { return }
        lastInsets = insets
        lastLift = lift
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lastLift == lift, self.lastInsets == insets else { return }
            self.changed?(lift, insets)
        }
    }
    static func footerLift(in bounds: CGRect, height: CGFloat, bottomInset: CGFloat, regions: [CGRect]) -> CGFloat {
        guard height > 0 else { return 0 }
        // Measure the actual rows, but always reconstruct their unshifted position to avoid oscillation.
        let footer = CGRect(x: bounds.minX + 16, y: bounds.maxY - bottomInset - height,
                            width: max(0, bounds.width - 32), height: height)
        var lift: CGFloat = 0
        for _ in 0...regions.count {
            let hits = regions.filter { $0.intersects(footer.offsetBy(dx: 0, dy: -lift)) }
            guard let next = hits.map({ footer.maxY - $0.minY + 8 }).max(), next > lift else { break }
            lift = next
        }
        return lift
    }
    static func clearInsets(in bounds: CGRect, regions: [CGRect]) -> UIEdgeInsets {
        var result = UIEdgeInsets.zero
        for region in regions {
            let rect = region.intersection(bounds)
            guard !rect.isNull, !rect.isEmpty else { continue }
            let distances = [rect.minY - bounds.minY, bounds.maxX - rect.maxX,
                             bounds.maxY - rect.maxY, rect.minX - bounds.minX]
            // A spanning island belongs above/below content even when its nearest edges are the sides.
            let edges = rect.width >= bounds.width ? [0, 2] : rect.height >= bounds.height ? [1, 3] : Array(distances.indices)
            guard let edge = edges.min(by: { distances[$0] < distances[$1] }) else { continue }
            switch edge {
            case 0: result.top = max(result.top, rect.maxY - bounds.minY + 8)
            case 1: result.right = max(result.right, bounds.maxX - rect.minX + 8)
            case 2: result.bottom = max(result.bottom, bounds.maxY - rect.minY + 8)
            default: result.left = max(result.left, rect.maxX - bounds.minX + 8)
            }
        }
        return result
    }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
}
