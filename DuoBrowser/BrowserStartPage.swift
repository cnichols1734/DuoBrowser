import SwiftUI

struct BrowserStartPage: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @ObservedObject var chrome: BrowserChromeState
    @ObservedObject var viewport: BrowserViewportState
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var expanded = true
    @State private var importing = false
    @ScaledMetric(relativeTo: .caption) private var iconSize = 72.0

    var body: some View {
        GeometryReader { geometry in
            let leading = max(20, viewport.nativeInsets.left)
            let trailing = max(20, viewport.nativeInsets.right)
            let width = max(1, geometry.size.width - leading - trailing)
            let columns = max(1, min(typeSize.isAccessibilitySize ? 3 : 6, Int(width / (iconSize + 16))))
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if browser.isPrivate {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Private Browsing").font(.title2.bold())
                            Text("Your private tabs and browsing history aren’t saved.").font(.body).foregroundStyle(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Favorites").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                                Spacer()
                                if session.bookmarks.count > columns * 2 {
                                    Button { expanded.toggle() } label: {
                                        HStack(spacing: 4) {
                                            Text(expanded ? "Show Less" : "Show All")
                                            Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption.weight(.semibold))
                                        }.font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    }.buttonStyle(.plain).frame(minHeight: 44)
                                }
                            }.frame(height: typeSize.isAccessibilitySize ? nil : 24)
                            if session.bookmarks.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Keep your favorite websites here.").font(.subheadline).foregroundStyle(.secondary)
                                    Button("Import Safari Favorites") { importing = true }.font(.body)
                                }.padding(.vertical, 12)
                            } else {
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: columns), alignment: .leading, spacing: 16) {
                                    ForEach(Array(session.bookmarks.prefix(expanded ? 500 : columns * 2))) { entry in
                                        Button { browser.navigate(to: entry.address) } label: {
                                            VStack(spacing: 8) {
                                                WebsiteIcon(address: entry.address, title: entry.title, size: iconSize)
                                                Text(verbatim: entry.title.isEmpty ? URL(string: entry.address)?.host ?? "Website" : entry.title)
                                                    .font(.caption.weight(.medium)).lineLimit(2)
                                                    .multilineTextAlignment(.center).frame(maxWidth: .infinity)
                                            }.frame(maxWidth: .infinity, alignment: .top).contentShape(Rectangle())
                                        }.buttonStyle(.plain).accessibilityHint("Opens this favorite")
                                            .contextMenu {
                                                Button("Open in New Tab", systemImage: "plus.square") { session.newTab(url: URL(string: entry.address)) }
                                                Button("Delete Favorite", systemImage: "trash", role: .destructive) { session.deleteBookmarks(ids: [entry.id]) }
                                            }
                                    }
                                }
                            }
                        }
                        if !session.bookmarks.isEmpty {
                            Button("Import Safari Favorites") { importing = true }.font(.subheadline)
                                .frame(minHeight: 44)
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.leading, leading).padding(.trailing, trailing)
                .padding(.top, max(32, viewport.nativeInsets.top + 16))
                .padding(.bottom, chrome.expandedHeight + viewport.bottomControlLift + geometry.safeAreaInsets.bottom + 32)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        }
        .sheet(isPresented: $importing) { SafariImportView(session: session) }
    }
}
