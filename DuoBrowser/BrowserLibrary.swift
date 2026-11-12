import SwiftUI

struct BrowserLibrary: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section = 0
    @State private var search = ""
    @State private var confirmClear = false
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
                if dynamicTypeSize.isAccessibilitySize { sectionPicker.pickerStyle(.menu) }
                else { sectionPicker.pickerStyle(.segmented) }
                LibraryContents(session: session, section: section, folderID: nil, search: search, open: open)
            }
            .searchable(text: $search, prompt: "Search Library")
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if section == 1, !session.history.isEmpty {
                    ToolbarItem(placement: .bottomBar) { Button("Clear History", role: .destructive) { confirmClear = true } }
                }
            }
            .confirmationDialog("Clear all browsing history on this device?", isPresented: $confirmClear) {
                Button("Clear History", role: .destructive) { session.deleteHistory() }
            } message: { Text("This removes the history list. Cookies and open tabs stay available.") }
        }
    }
    private func open(_ entry: LibraryEntry) { session.selected.navigate(to: entry.address); dismiss() }
}

private struct LibraryContents: View {
    @ObservedObject var session: BrowserSession
    var section: Int
    var folderID: UUID?
    var search: String
    var open: (LibraryEntry) -> Void
    @State private var deletingFolder: BookmarkFolder?

    private var entries: [LibraryEntry] {
        let all = section == 0 ? session.bookmarks : section == 1 ? session.history : session.readingList
        return all.filter {
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
                    description: Text(section == 1 ? "Pages you visit appear here. Private browsing never adds to history." : "Save a bookmark from Page options, or transfer saved pages from Set Up DuoBrowser."))
            }
        }
        ForEach(folders) { folder in
            NavigationLink {
                List { LibraryContents(session: session, section: 0, folderID: folder.id, search: "", open: open) }
                    .navigationTitle(Text(verbatim: folder.title.isEmpty ? "Untitled Folder" : folder.title))
                    .navigationBarTitleDisplayMode(.inline)
            } label: { Label(folder.title.isEmpty ? "Untitled Folder" : folder.title, systemImage: "folder").frame(minHeight: 44) }
                .swipeActions {
                    Button("Delete", role: .destructive) { deletingFolder = folder }
                }
        }
        .confirmationDialog("Delete this folder and its saved pages?", isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } })) {
            Button("Delete Folder", role: .destructive) {
                if let folder = deletingFolder { session.deleteBookmarkFolder(folder.id) }
                deletingFolder = nil
            }
        }
        ForEach(entries) { entry in
            Button { open(entry) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.title.isEmpty ? entry.address : entry.title)
                        .font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                    Text(verbatim: URL(string: entry.address)?.host ?? entry.address)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.vertical, 4).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens this page in the current tab")
            .swipeActions {
                Button("Delete", role: .destructive) {
                    if section == 0 { session.deleteBookmarks(ids: [entry.id]) }
                    else if section == 1 { session.deleteHistory(ids: [entry.id]) }
                    else { session.deleteReadingList(ids: [entry.id]) }
                }
            }
        }
    }
}
