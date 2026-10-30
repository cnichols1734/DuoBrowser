import SwiftUI

struct TabOverview: View {
    @ObservedObject var session: BrowserSession
    @State private var search = ""
    @State private var manageWorkspaces = false
    @AppStorage("browser.tabBackgroundHex") private var backgroundHex = ""
    private var backgroundColor: Color {
        guard let value = UInt32(backgroundHex, radix: 16), backgroundHex.count == 6 else { return Color(uiColor: .systemGroupedBackground) }
        return Color(uiColor: .systemGroupedBackground).mix(with: Color(red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255), by: 0.22)
    }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var searchLineHeight = 20.0

    private var filteredTabs: [BrowserModel] {
        session.visibleTabs.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
            || $0.siteName.localizedCaseInsensitiveContains(search) }
    }
    private var largeText: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 8) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(session.privateMode ? "Private Tabs" : session.workspaceName)
                            .font(.title2.weight(.bold))
                            .accessibilityAddTraits(.isHeader)
                            .padding(.trailing, geometry.safeAreaInsets.trailing)
                        HStack {
                            ColorPicker("Tab background", selection: colorChoice, supportsOpacity: false)
                            if !backgroundHex.isEmpty { Button("Reset") { backgroundHex = "" } }
                        }.font(.subheadline).frame(minHeight: 44)
                        if !session.privateMode {
                            Menu {
                                ForEach(session.workspaces) { workspace in
                                    Button(workspace.name) { search = ""; session.switchWorkspace(workspace.id); session.showingTabs = true }
                                }
                                Button("Manage Workspaces") { manageWorkspaces = true }
                            } label: { Label("Workspaces", systemImage: "square.stack").frame(minHeight: 44) }
                        }
                        if session.privateMode {
                            Text("Private tabs are not saved. Closing them clears this private session.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.system(size: 20))
                                .foregroundStyle(.secondary).accessibilityHidden(true)
                            TextField("Search Tabs", text: $search)
                                .textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityLabel("Search Tabs")
                            if !search.isEmpty {
                                Button { search = "" } label: {
                                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).frame(width: 44, height: 44)
                                }.accessibilityLabel("Clear tab search")
                            }
                        }
                        .padding(.horizontal, 16).frame(minHeight: max(44, searchLineHeight + 16))
                        .glassEffect(.regular, in: Capsule())
                        LazyVGrid(columns: largeText ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 160), spacing: 20)], spacing: 24) {
                            ForEach(filteredTabs) { tab in
                                TabPreview(tab: tab, selected: session.selectedID == tab.id,
                                           select: { session.select(tab.id) }, close: {
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
                        }
                        if filteredTabs.isEmpty {
                            if search.isEmpty {
                                ContentUnavailableView {
                                    Label("A little room to explore", systemImage: "square.on.square")
                                } description: {
                                    Text("Open a new tab to start browsing in this workspace.")
                                } actions: {
                                    Button("New Tab", systemImage: "plus") { session.newTab() }.buttonStyle(.borderedProminent)
                                }
                            } else { ContentUnavailableView.search(text: search) }
                        }
                    }.padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                Group {
                    if largeText {
                        VStack(spacing: 8) { modeMenu; footerActions }
                    } else {
                        ZStack { modeMenu; footerActions }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.bottom, 8)
                .frame(maxWidth: 700).frame(maxWidth: .infinity)
            }
            .background(backgroundColor.ignoresSafeArea())
            .ignoresSafeArea(.container, edges: .horizontal)
        }
        .statusBarHidden(!session.showSystemStatus)
        .sheet(isPresented: $manageWorkspaces) { WorkspaceView(session: session) }

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
                .font(.subheadline.weight(.semibold)).lineLimit(1)
                .padding(.horizontal, 22).padding(.vertical, 6).frame(minHeight: 48)
        }
        .glassEffect(.regular.interactive(), in: Capsule())
        .accessibilityLabel("Browsing mode, \(session.privateMode ? "Private" : "Tabs"), \(session.visibleTabs.count) open")
    }
    private var footerActions: some View {
        HStack {
            Button { session.newTab() } label: {
                Image(systemName: "plus").font(.system(size: 24)).frame(width: 52, height: 52)
            }.glassEffect(.regular.interactive(), in: Circle()).accessibilityLabel("New Tab")
            Spacer()
            Button("Done") { session.showingTabs = false }
                .font(.body.weight(.semibold)).padding(.horizontal, 18).padding(.vertical, 6).frame(minHeight: 48)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
    }
}

private struct TabPreview: View {
    @ObservedObject var tab: BrowserModel
    let selected: Bool
    let select: () -> Void
    let close: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
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
                .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 3) }
            } else { previewCard }
        }.accessibilityElement(children: .contain)
    }
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: tab.isPinned ? "pin.fill" : "globe").font(.caption).foregroundStyle(.secondary)
                Text(tab.title).font(.subheadline.weight(.medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4).accessibilityHidden(true)
            ZStack(alignment: .topTrailing) {
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
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                    .aspectRatio(0.68, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.08), lineWidth: selected ? 3 : 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(tab.isPinned ? "Pinned tab" : "Open tab"), \(tab.title)")
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)

                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                        .frame(width: 28, height: 28)
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
