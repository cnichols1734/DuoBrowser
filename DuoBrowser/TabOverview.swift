import SwiftUI
import PhotosUI
import ImageIO

struct TabOverview: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject private var wallpaper = BrowserWallpaperStore.shared
    @State private var search = ""
    @State private var searching = false
    @State private var manageWorkspaces = false
    @State private var appearance = false
    @State private var controlLift: CGFloat = 0
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
                    .padding(.horizontal, 16).padding(.top, 8)
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
                } else {
                    TabStack(tabs: filteredTabs, selectedID: session.selectedID,
                             reduceMotion: reduceMotion, close: { session.close($0) }) { tab, close in
                        tabItem(tab, list: false, close: close)
                    }
                }
                footer
                    .padding(.horizontal, 16).padding(.top, 8)
                    .padding(.bottom, max(8, geometry.safeAreaInsets.bottom) + controlLift)
            }
            .background {
                BrowserWallpaper()
                OverviewRegionReader { controlLift = $0 }.allowsHitTesting(false)
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
        .sheet(isPresented: $manageWorkspaces) { WorkspaceView(session: session) }
        .sheet(isPresented: $appearance) {
            NavigationStack {
                Form {
                    Section("Wallpaper") {
                        PhotosPicker("Choose Photo", selection: $photo, matching: .images)
                        if wallpaper.image != nil { Button("Remove Photo") { wallpaper.remove() } }
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
            guard let photo else { return }
            do {
                guard let data = try await photo.loadTransferable(type: Data.self), !Task.isCancelled else { return }
                try wallpaper.save(data)
                wallpaperError = nil
            } catch { wallpaperError = "This photo couldn't be used. Please choose another." }
        }
    }

    private func tabItem(_ tab: BrowserModel, list: Bool, close: (() -> Void)? = nil) -> some View {
        TabPreview(tab: tab, selected: session.selectedID == tab.id, list: list,
                   select: { session.select(tab.id) }, close: close ?? {
            withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { session.close(tab.id) }
        })
        .contextMenu {
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
            ZStack(alignment: geometry.closeOnLeading ? .topLeading : .topTrailing) {
                Button(action: select) {
                    GeometryReader { geometry in
                        Group {
                            if tab.showingStartPage {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(tab.isPrivate ? "Private Browsing" : "Start Page").font(.headline)
                                    if !tab.isPrivate { Text("Favorites").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                                    Spacer()
                                }
                                .padding(16).frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                            } else if let image = tab.snapshot {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                            } else {
                                VStack(spacing: 12) {
                                    Image(systemName: "globe").font(.largeTitle).foregroundStyle(.tertiary)
                                    Text(tab.siteName).font(.callout).foregroundStyle(.secondary).lineLimit(2)
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

                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 32)
                        .glassEffect(.regular.interactive(), in: Circle())
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(2)
                .accessibilityLabel("Close tab, \(tab.title)")
            }
        }
    }
}

/// App-owned wallpaper: only an explicitly selected photo is read, downsampled and stored locally.
@MainActor
final class BrowserWallpaperStore: ObservableObject {
    static let shared = BrowserWallpaperStore()
    @Published private(set) var image: UIImage?
    private let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BrowserWallpaper.jpg")

    private init() { image = UIImage(contentsOfFile: file.path) }

    func save(_ data: Data) throws {
        guard data.count <= 40 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary), let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try jpeg.write(to: file, options: .atomic)
        image = UIImage(cgImage: thumbnail)
    }

    func remove() { try? FileManager.default.removeItem(at: file); image = nil }
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
                Color.black.opacity(colorScheme == .dark ? 0.18 : 0)
            }
        }.ignoresSafeArea().accessibilityHidden(true)
    }
}

private struct OverviewRegionReader: UIViewRepresentable {
    let changed: (CGFloat) -> Void
    func makeUIView(context: Context) -> OverviewRegionView { OverviewRegionView() }
    func updateUIView(_ view: OverviewRegionView, context: Context) { view.changed = changed; view.setNeedsLayout() }
}

private final class OverviewRegionView: UIView {
    var changed: ((CGFloat) -> Void)?
    private var lastLift: CGFloat = -1
    override func layoutSubviews() {
        super.layoutSubviews()
        let regions = reservedRegions(kind: .occlusion).filter(\.isActive).map(\.frame)
        let lift = BrowserViewportState.controlLift(in: bounds, height: 72, safeBottom: 0, regions: regions)
        guard lift != lastLift else { return }
        lastLift = lift
        DispatchQueue.main.async { [weak self] in
            guard let self, self.lastLift == lift else { return }
            self.changed?(lift)
        }
    }
    override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); setNeedsLayout() }
}
