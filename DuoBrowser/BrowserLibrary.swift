import SwiftUI

struct BrowserLibrary: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var section = 0
    @State private var search = ""
    @State private var confirmClear = false
    private var entries: [LibraryEntry] {
        (section == 0 ? session.bookmarks : session.history).filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.address.localizedCaseInsensitiveContains(search)
        }
    }
    private var sectionPicker: some View {
        Picker("Library", selection: $section) {
            Text("Bookmarks").tag(0)
            Text("History").tag(1)
        }
    }
    var body: some View {
        NavigationStack {
            List {
                if dynamicTypeSize.isAccessibilitySize { sectionPicker.pickerStyle(.menu) }
                else { sectionPicker.pickerStyle(.segmented) }
                if entries.isEmpty {
                    ContentUnavailableView(section == 0 ? "No Bookmarks" : "No History", systemImage: section == 0 ? "bookmark" : "clock",
                        description: Text(section == 0 ? "Save a page from Page options." : "Private browsing never adds to history."))
                }
                ForEach(entries) { entry in
                    Button {
                        session.selected.navigate(to: entry.address)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title.isEmpty ? entry.address : entry.title).foregroundStyle(.primary).lineLimit(2)
                            Text(URL(string: entry.address)?.host ?? entry.address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) {
                            if section == 0 { session.deleteBookmarks(ids: [entry.id]) }
                            else { session.deleteHistory(ids: [entry.id]) }
                        }
                    }
                }
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
}
