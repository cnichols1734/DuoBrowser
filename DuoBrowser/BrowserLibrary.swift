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
                    if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        ContentUnavailableView(section == 0 ? "Your saved pages" : "Your recent pages",
                            systemImage: section == 0 ? "bookmark" : "clock",
                            description: Text(section == 0 ? "Save a bookmark from Page options to keep a page here." : "Pages you visit appear here. Private browsing never adds to history."))
                    }
                }
                ForEach(entries) { entry in
                    Button {
                        session.selected.navigate(to: entry.address)
                        dismiss()
                    } label: {
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
