import SwiftUI

struct BrowserLibrary: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section = 0
    @State private var search = ""
    @State private var confirmClear = false
    @State private var creatingFolder = false
    @State private var offlineArticle: ReaderArticle?
    @State private var error: String?
    @State private var unreadOnly = false
    private var sectionPicker: some View {
        Picker("Library", selection: $section) {
            Text("Bookmarks").tag(0)
            Text("History").tag(1)
            Text("Reading List").tag(2)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Group {
                    if dynamicTypeSize.isAccessibilitySize { sectionPicker.pickerStyle(.menu).labelsHidden() }
                    else { sectionPicker.pickerStyle(.segmented) }
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 12, trailing: 0))
                if section == 2 { Toggle("Unread Only", isOn: $unreadOnly) }
                LibraryContents(session: session, section: section, folderID: nil, search: search, unreadOnly: unreadOnly, open: open)
            }
            .searchable(text: $search, prompt: "Search Library")
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if section == 0 {
                    ToolbarItem(placement: .bottomBar) { Button("New Folder", systemImage: "folder.badge.plus") { creatingFolder = true } }
                }
                if section == 1, !session.history.isEmpty {
                    ToolbarItem(placement: .bottomBar) { Button("Clear History", role: .destructive) { confirmClear = true } }
                }
            }
            .sheet(isPresented: $creatingFolder) { FolderEditor(session: session, folder: BookmarkFolder(title: "", parentID: nil)) }
            .fullScreenCover(item: $offlineArticle) { ReaderView(article: $0, sourceBrowser: session.selected) }
            .alert("Couldn’t Open Article", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
            .confirmationDialog("Clear all browsing history on this device?", isPresented: $confirmClear) {
                Button("Clear History", role: .destructive) { session.deleteHistory() }
            } message: { Text("This removes the history list. Cookies and open tabs stay available.") }
        }
    }
    private func open(_ entry: LibraryEntry) {
        do {
            let savedArticle = section == 2 ? try session.articleForOpening(entry) : nil
            if let savedArticle { offlineArticle = savedArticle }
            else { session.selected.navigate(to: entry.address); dismiss() }
        } catch { self.error = error.localizedDescription + " You can also choose Open Website from the item’s menu." }
    }
}

private struct LibraryContents: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var section: Int
    var folderID: UUID?
    var search: String
    var unreadOnly = false
    var open: (LibraryEntry) -> Void
    @State private var editingEntry: LibraryEntry?
    @State private var editingFolder: BookmarkFolder?
    @State private var error: String?
    @State private var deletingFolder: BookmarkFolder?

    private var entries: [LibraryEntry] {
        let all = section == 0 ? session.bookmarks : section == 1 ? session.history : session.readingList
        return all.filter {
            if section == 2 && unreadOnly && $0.isRead == true { return false }
            if !search.isEmpty { return $0.title.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search) }
            return section != 0 || $0.folderID == folderID
        }
    }
    private var folders: [BookmarkFolder] {
        section == 0 && search.isEmpty ? session.bookmarkFolders.filter { $0.parentID == folderID } : []
    }
    var body: some View {
        if entries.isEmpty && folders.isEmpty {
            if !search.isEmpty { ContentUnavailableView.search(text: search) }
            else {
                ContentUnavailableView(section == 1 ? "Your recent pages" : "Your saved pages",
                    systemImage: section == 1 ? "clock" : "book",
                    description: Text(section == 1 ? "Pages you visit appear here. Private browsing never adds to history." : "Choose Save Page in Page options to keep a favorite, bookmark, or article for later."))
            }
        }
        ForEach(folders) { folder in
            NavigationLink {
                List { LibraryContents(session: session, section: 0, folderID: folder.id, search: "", open: open) }
                    .navigationTitle(Text(verbatim: folder.title.isEmpty ? "Untitled Folder" : folder.title))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .bottomBar) { Button("New Folder", systemImage: "folder.badge.plus") { editingFolder = BookmarkFolder(title: "", parentID: folder.id) } } }
            } label: { Label(folder.title.isEmpty ? "Untitled Folder" : folder.title, systemImage: "folder").frame(minHeight: 44) }
                .contextMenu { Button("Edit Folder", systemImage: "pencil") { editingFolder = folder } }
                .swipeActions {
                    Button("Edit") { editingFolder = folder }.tint(.blue)
                    Button("Delete", role: .destructive) { deletingFolder = folder }
                }
        }
        .sheet(item: $editingFolder) { FolderEditor(session: session, folder: $0) }
        .sheet(item: $editingEntry) { SavePageView(session: session, entry: $0, editing: true, reading: section == 2) }
        .alert("Couldn’t Update Library", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        .confirmationDialog("Delete this folder and its saved pages?", isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })) {
            Button("Delete Folder", role: .destructive) {
                if let folder = deletingFolder, !session.deleteBookmarkFolder(folder.id) {
                    error = session.selected.errorMessage ?? SavedPageError.saveFailed.localizedDescription
                }
                deletingFolder = nil
            }
        }
        ForEach(entries) { entry in
            Button { open(entry) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.title.isEmpty ? entry.address : entry.title)
                        .font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: URL(string: entry.address)?.host ?? entry.address).lineLimit(1)
                            if section == 2 {
                                Text([entry.isRead != true ? "Unread" : nil, entry.offlineID != nil ? "Offline" : nil].compactMap { $0 }.joined(separator: " · "))
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            Text(verbatim: URL(string: entry.address)?.host ?? entry.address).lineLimit(1)
                            if section == 2 {
                                if entry.isRead != true { Text("Unread") }
                                if entry.offlineID != nil { Label("Offline", systemImage: "arrow.down.circle") }
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(entry.offlineID != nil ? "Opens the saved offline article" : "Opens this page in the current tab")
            .contextMenu {
                if section != 1 { Button("Edit", systemImage: "pencil") { editingEntry = entry } }
                if section == 2 {
                    Button(entry.isRead == true ? "Mark Unread" : "Mark Read", systemImage: entry.isRead == true ? "circle" : "checkmark.circle") {
                        do { var changed = entry; changed.isRead = entry.isRead != true; try session.savePage(changed, reading: true) } catch { self.error = error.localizedDescription }
                    }
                    Button("Open Website", systemImage: "globe") { session.newTab(url: URL(string: entry.address)); session.showingLibrary = false }
                    if entry.offlineID != nil {
                        Button("Remove Offline Copy", systemImage: "trash") {
                            do { try session.removeOfflineCopy(entry) } catch { self.error = error.localizedDescription }
                        }
                    }
                }
            }
            .swipeActions {
                Button("Delete", role: .destructive) {
                    if section == 0 {
                        if !session.deleteBookmarks(ids: [entry.id]) { error = session.selected.errorMessage ?? SavedPageError.saveFailed.localizedDescription }
                    }
                    else if section == 1 { session.deleteHistory(ids: [entry.id]) }
                    else if !session.deleteReadingList(ids: [entry.id]) { error = session.selected.errorMessage ?? SavedPageError.saveFailed.localizedDescription }
                }
            }
        }
    }
}
