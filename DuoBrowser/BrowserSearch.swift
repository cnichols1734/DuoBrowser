import SwiftUI

struct BrowserSearch: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var browser: BrowserModel
    @State var query: String
    @Environment(\.dismiss) private var dismiss

    private var results: [SearchResult] { session.searchResults(query, isPrivate: browser.isPrivate) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    AddressField(text: $query, submit: navigate, cancel: { dismiss() }, cancelOnEndEditing: false)
                        .frame(minHeight: 48)
                }.padding(.horizontal, 16)
                List {
                    if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button(action: navigate) {
                            Label("Search or open “\(query)”", systemImage: "arrow.up.right").lineLimit(2)
                        }
                    }
                    if !results.isEmpty {
                        Section("Tabs, bookmarks & history") {
                            ForEach(results) { result in
                                Button {
                                    if let id = result.tabID { session.select(id) }
                                    else { browser.navigate(to: result.address) }
                                    dismiss()
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: result.kind == .tab ? "square.on.square" : result.kind == .bookmark ? "bookmark" : "clock")
                                            .foregroundStyle(.secondary).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(verbatim: result.title.isEmpty ? result.address : result.title).lineLimit(2)
                                            Text(result.kind == .tab ? "Switch to tab · \(result.detail)" : result.kind == .bookmark ? "Bookmark" : "History")
                                                .font(.caption).foregroundStyle(.secondary)
                                            Text(verbatim: result.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }.padding(.vertical, 4)
                                }.foregroundStyle(.primary)
                            }
                        }
                    }
                    Section("Actions") {
                        Button("Find on Page", systemImage: "doc.text.magnifyingglass") {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                browser.webView.findInteraction?.presentFindNavigator(showingReplace: false)
                            }
                        }
                        Button("New Private Tab", systemImage: "hand.raised") { session.newTab(privateTab: true); dismiss() }
                        Button("Workspaces", systemImage: "square.stack") { dismiss(); session.showWorkspacesAfterSearch() }
                    }
                    if browser.isPrivate { Text("Private search excludes your normal tabs and history.").font(.footnote).foregroundStyle(.secondary) }
                }.listStyle(.insetGrouped).scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
    private func navigate() { browser.navigate(to: query); dismiss() }
}

extension BrowserSession {
    func showWorkspacesAfterSearch() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            self?.showingWorkspaces = true
        }
    }
}
