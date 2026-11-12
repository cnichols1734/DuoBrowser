import SwiftUI

struct SavePageView: View {
    @ObservedObject var session: BrowserSession
    let browser: BrowserModel?
    let original: LibraryEntry
    let editing: Bool
    let editingReading: Bool
    private let generation: UUID?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var destination: String
    @State private var folderID: UUID?
    @State private var offline = false
    @State private var error: String?
    @State private var saving = false
    @State private var saveTask: Task<Void, Never>?
    @State private var creatingFolder = false

    init(session: BrowserSession, browser: BrowserModel? = nil, entry: LibraryEntry, editing: Bool = false, reading: Bool = false) {
        self.session = session; self.browser = browser; original = entry
        self.editing = editing; editingReading = reading; generation = browser?.documentGeneration
        _title = State(initialValue: entry.title)
        _destination = State(initialValue: reading ? "reading" : entry.isFavorite == false ? "bookmarks" : "favorites")
        _folderID = State(initialValue: entry.folderID)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title, axis: .vertical).lineLimit(1...4)
                        .accessibilityIdentifier("savedPageTitle")
                    Text(URL(string: original.address)?.host ?? original.address)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Save to") {
                    if !editingReading {
                        Picker("Destination", selection: $destination) {
                            Label("Favorites", systemImage: "star").tag("favorites")
                            Label("Bookmarks", systemImage: "bookmark").tag("bookmarks")
                            if !editing { Label("Read Later", systemImage: "eyeglasses").tag("reading") }
                        }
                        .pickerStyle(.inline).labelsHidden()
                    } else { Label("Reading List", systemImage: "eyeglasses") }
                    if destination == "bookmarks" {
                        FolderPicker(folders: session.bookmarkFolders, selection: $folderID)
                        Button("New Folder", systemImage: "folder.badge.plus") { creatingFolder = true }
                    }
                }
                if destination == "reading", browser != nil {
                    Section {
                        Toggle("Save Article Offline", isOn: $offline)
                    } footer: {
                        Text("Saves readable text and up to eight images from this site. Some images may be unavailable. Videos and interactive content aren’t saved. Offline articles use up to 50 MB on this device.")
                    }
                }
                if browser?.isPrivate == true {
                    Section { Label("This saved page will remain in your Library after private tabs close.", systemImage: "hand.raised").font(.footnote) }
                }
                if let error { Section { Text(error).foregroundStyle(.red).accessibilityLabel("Couldn’t save. " + error) } }
                if saving { Section { ProgressView(offline ? "Saving article…" : "Saving page…") } }
            }
            .disabled(saving)
            .navigationTitle(editing ? "Edit Saved Page" : "Save Page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { saveTask?.cancel(); dismiss() }.keyboardShortcut(.cancelAction) }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).keyboardShortcut("s", modifiers: .command).fontWeight(.semibold).disabled(saving || title.count > 512) }
            }
            .sheet(isPresented: $creatingFolder) {
                FolderEditor(session: session, folder: BookmarkFolder(title: "", parentID: folderID)) { folderID = $0 }
            }
            .onDisappear { saveTask?.cancel() }
        }
    }
    private func save() {
        saving = true; error = nil
        saveTask = Task { @MainActor in
            do {
                var entry = original
                entry.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if entry.title.isEmpty { entry.title = URL(string: entry.address)?.host ?? "Saved Page" }
                entry.isFavorite = destination == "favorites"
                entry.folderID = destination == "bookmarks" ? folderID : nil
                var article: OfflineArticle?
                if offline, destination == "reading", let browser, let generation, let url = URL(string: entry.address) {
                    article = try await browser.captureOfflineArticle(expectedURL: url, generation: generation)
                }
                try Task.checkCancellation()
                if let browser {
                    guard session.tabs.contains(where: { $0 === browser }), browser.documentGeneration == generation,
                          browser.restorationURL?.absoluteString == original.address else { throw SavedPageError.stalePage }
                }
                try session.savePage(entry, reading: destination == "reading", offline: article)
                dismiss()
            } catch is CancellationError { } catch { self.error = error.localizedDescription }
            saving = false
        }
    }
}

struct FolderPicker: View {
    let folders: [BookmarkFolder]
    @Binding var selection: UUID?
    var movingID: UUID?
    var body: some View {
        Picker("Folder", selection: $selection) {
            Text("All Bookmarks").tag(nil as UUID?)
            ForEach(folders.filter { SavedPagesPolicy.canMove(movingID, to: $0.id, folders: folders) }) { folder in
                Text(path(folder)).tag(Optional(folder.id))
            }
        }
    }
    private func path(_ folder: BookmarkFolder) -> String {
        var names = [folder.title]
        var parent = folder.parentID
        for _ in 0..<32 {
            guard let id = parent, let next = folders.first(where: { $0.id == id }) else { break }
            names.insert(next.title, at: 0); parent = next.parentID
        }
        return names.joined(separator: " / ")
    }
}

struct FolderEditor: View {
    @ObservedObject var session: BrowserSession
    let folder: BookmarkFolder
    var saved: ((UUID) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var parentID: UUID?
    @State private var error: String?
    init(session: BrowserSession, folder: BookmarkFolder, saved: ((UUID) -> Void)? = nil) {
        self.session = session; self.folder = folder; self.saved = saved
        _title = State(initialValue: folder.title); _parentID = State(initialValue: folder.parentID)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Folder Name", text: $title).accessibilityIdentifier("savedFolderName")
                FolderPicker(folders: session.bookmarkFolders, selection: $parentID, movingID: folder.id)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle(folder.title.isEmpty ? "New Folder" : "Edit Folder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            var edited = folder; edited.title = title.trimmingCharacters(in: .whitespacesAndNewlines); edited.parentID = parentID
                            try session.saveFolder(edited); saved?(edited.id); dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.keyboardShortcut("s", modifiers: .command).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 512)
                }
            }
        }
    }
}
