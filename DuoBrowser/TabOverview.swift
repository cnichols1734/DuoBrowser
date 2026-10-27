import SwiftUI

struct TabOverview: View {
    @ObservedObject var session: BrowserSession
    @State private var search = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var filteredTabs: [BrowserModel] {
        session.tabs.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
            || $0.siteName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Tabs")
                .font(.title2.weight(.bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 20)
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search Tabs", text: $search)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel("Search Tabs")
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("Clear tab search")
                }
            }
            .padding(.horizontal, 16).frame(height: 44)
            .glassEffect(.regular, in: Capsule())
            .padding(.horizontal, 20).padding(.bottom, 4)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 160), spacing: 20)], spacing: 24) {
                    ForEach(filteredTabs) { tab in
                        TabPreview(tab: tab, selected: session.selectedID == tab.id,
                                   select: { session.select(tab.id) }, close: {
                            withAnimation(reduceMotion ? nil : .smooth(duration: 0.22)) { session.close(tab.id) }
                        })
                    }
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if filteredTabs.isEmpty { ContentUnavailableView.search(text: search) }
            }
            ZStack {
                Text("\(session.tabs.count) \(session.tabs.count == 1 ? "Tab" : "Tabs")")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 22).frame(height: 48)
                    .glassEffect(.regular, in: Capsule())
                HStack {
                    Button { session.newTab() } label: {
                        Image(systemName: "plus").font(.title2).frame(width: 48, height: 48)
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("New Tab")
                    Spacer()
                    Button("Done") { session.showingTabs = false }
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 18).frame(height: 48)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20).padding(.bottom, 8)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .ignoresSafeArea(.container, edges: .horizontal)
        .statusBarHidden(true)
    }
}

private struct TabPreview: View {
    @ObservedObject var tab: BrowserModel
    let selected: Bool
    let select: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "globe").font(.caption).foregroundStyle(.secondary)
                Text(tab.title).font(.subheadline.weight(.medium)).lineLimit(1)
            }
            .padding(.horizontal, 4)
            ZStack(alignment: .topTrailing) {
                Button(action: select) {
                    GeometryReader { geometry in
                        Group {
                            if let image = tab.snapshot {
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
                .accessibilityLabel("Open tab, \(tab.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])

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
