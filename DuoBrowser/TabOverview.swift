import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers
import CoreTransferable

struct TabOverview: View {
    @State private var showingRecentlyClosed = false
    @ObservedObject var session: BrowserSession
    @ObservedObject private var wallpaper = BrowserWallpaperStore.shared
    @State private var search = ""
    @State private var searching = false
    @State private var manageWorkspaces = false
    @State private var appearance = false
    @State private var controlLift: CGFloat = 0
    @State private var footerHeight: CGFloat = 0
    @State private var contentInsets = UIEdgeInsets.zero
    @State private var photo: PhotosPickerItem?
    @State private var wallpaperError: String?
    @FocusState private var searchFocused: Bool
    @AppStorage("browser.tabBackgroundHex") private var backgroundHex = ""
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var filteredTabs: [BrowserModel] {
        session.visibleTabs.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
            || $0.siteName.localizedCaseInsensitiveContains(search) }
    }
    private var accessibleList: Bool { dynamicTypeSize.isAccessibilitySize || voiceOver }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if searching {
                    HStack {
                        Image(systemName: "magnifyingglass").accessibilityHidden(true)
                        TextField("Search Tabs", text: $search)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .focused($searchFocused)
                        Button("Cancel") { search = ""; searching = false; searchFocused = false }
                    }
                    .padding(12).glassEffect(.regular, in: Capsule())
                    .padding(.horizontal, max(16, max(contentInsets.left, contentInsets.right) + 8))
                    .padding(.top, max(8, contentInsets.top + 8))
                }
                if filteredTabs.isEmpty {
                    ContentUnavailableView.search(text: search)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if accessibleList {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredTabs) { tab in tabItem(tab, list: true).environmentObject(TabCardGeometry()) }
                        }.padding(16)
                    }.scrollDismissesKeyboard(.interactively)
                    .padding(.horizontal, max(contentInsets.left, contentInsets.right))
                    .padding(.top, searching ? 0 : contentInsets.top)
                } else {
                    TabStack(tabs: filteredTabs, selectedID: session.selectedID,
                             reduceMotion: reduceMotion, close: { session.close($0) }) { tab, close in
                        tabItem(tab, list: false, close: close)
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
                OverviewRegionReader(footerHeight: footerHeight, bottomInset: max(8, geometry.safeAreaInsets.bottom)) {
                    controlLift = $0; contentInsets = $1
                }.allowsHitTesting(false)
                if reduceTransparency { Color(uiColor: .systemGroupedBackground) }
                else { Rectangle().fill(.ultraThinMaterial) }
            }
        }
        // Reclaim the display at the measuring container, not just its inner content.
        .ignoresSafeArea(.container)
        .statusBarHidden(true)
        .onChange(of: session.showingTabs) { _, showing in
            if showing { search = ""; searching = false; searchFocused = false }
        }
        .sheet(isPresented: $showingRecentlyClosed) { RecentlyClosedView(session: session) }
        .sheet(isPresented: $manageWorkspaces) { WorkspaceView(session: session) }
        .sheet(isPresented: $appearance) {
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
        .task(id: photo) {
            guard let selectedPhoto = photo else { return }
            let token = wallpaper.beginImport()
            do {
                guard let imported = try await selectedPhoto.loadTransferable(type: WallpaperImport.self) else { throw CocoaError(.fileReadCorruptFile) }
                guard !Task.isCancelled, photo == selectedPhoto else { return }
                try wallpaper.save(imported, token: token)
                wallpaperError = nil
                photo = nil
            } catch {
                guard !Task.isCancelled, photo == selectedPhoto else { return }
                wallpaperError = "This photo couldn't be used. Please choose another."
                photo = nil
            }
        }
    }

    private func tabItem(_ tab: BrowserModel, list: Bool, close: (() -> Void)? = nil) -> some View {
        TabPreview(tab: tab, selected: session.selectedID == tab.id, list: list,
                   select: { session.select(tab.id) }, close: close ?? {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { session.close(tab.id) }
        })
        .contextMenu {
            Button("Close Tab", systemImage: "xmark", role: .destructive) { session.close(tab.id) }
            Button(tab.isPinned ? "Unpin Tab" : "Pin Tab", systemImage: "pin") { session.togglePin(tab) }
            if !tab.isPrivate {
                Menu("Move to Workspace") {
                    ForEach(session.workspaces) { workspace in
                        Button(workspace.name) { session.move(tab, to: workspace.id) }
                    }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if accessibleList { modeMenu }
            HStack(spacing: 12) {
                Button { session.newTab() } label: { Image(systemName: "plus").frame(width: 48, height: 48) }
                    .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel("New Tab")
                if !accessibleList { Spacer(minLength: 0); modeMenu; Spacer(minLength: 0) }
                else { Spacer(minLength: 0) }
                Menu {
                    Button("Search Tabs", systemImage: "magnifyingglass") { searching = true; searchFocused = true }
                    if !session.privateMode {
                        Button("Recently Closed", systemImage: "clock.arrow.circlepath") { showingRecentlyClosed = true }
                        Menu("Workspaces", systemImage: "square.stack") {
                            ForEach(session.workspaces) { workspace in
                                Button(workspace.name) { search = ""; session.switchWorkspace(workspace.id); session.showingTabs = true }
                            }
                            Button("Manage Workspaces") { manageWorkspaces = true }
                        }
                    }
                    Button("Tab Appearance", systemImage: "photo") { appearance = true }
                } label: { Image(systemName: "ellipsis").frame(width: 48, height: 48) }
                    .glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel("Tab options")
                Button { session.showingTabs = false } label: {
                    Image(systemName: "checkmark").fontWeight(.semibold).frame(width: 48, height: 48)
                }.buttonStyle(.plain).foregroundStyle(.white)
                    .glassEffect(.regular.tint(.accentColor).interactive(), in: Circle()).accessibilityLabel("Done")
            }.font(.title3).buttonStyle(.plain)
        }
    }

    private var modeMenu: some View {
        Menu {
            Button("Tabs") { search = ""; session.switchMode(false) }
            Button("Private") { search = ""; session.switchMode(true) }
            if session.privateMode {
                Button("Close All Private Tabs", role: .destructive) { session.closePrivateTabs() }
            }
        } label: {
            Text(session.privateMode ? "Private · \(session.visibleTabs.count)" : "\(session.visibleTabs.count) \(session.visibleTabs.count == 1 ? "Tab" : "Tabs")")
                .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 16).frame(minHeight: 48)
        }
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel("Browsing mode, \(session.privateMode ? "Private" : session.workspaceName), \(session.visibleTabs.count) open")
    }
}

private struct TabPreview: View {
    @ObservedObject var tab: BrowserModel
    let selected: Bool
    let list: Bool
    let select: () -> Void
    let close: () -> Void
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
                    .accessibilityLabel("\(tab.isPinned ? "Pinned tab" : "Open tab"), \(tab.title)")
                    .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
                .accessibilityLabel("\(tab.isPinned ? "Pinned tab" : "Open tab"), \(tab.title)")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)

                if let origin = geometry.closeOrigin {
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
