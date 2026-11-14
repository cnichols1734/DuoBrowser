import SwiftUI

struct StartPageFavoritesManager: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var editing: LibraryEntry?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                if session.favorites.isEmpty {
                    ContentUnavailableView("Your Favorites", systemImage: "star",
                                           description: Text("Add the sites you want close at hand."))
                }
                Section {
                    ForEach(session.favorites) { entry in
                        Button { editing = entry } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: entry.title.isEmpty ? StartPagePolicy.host(entry.address) ?? entry.address : entry.title)
                                    .font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                                Text(verbatim: StartPagePolicy.host(entry.address) ?? entry.address)
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityHint("Edit this favorite")
                    }
                    .onMove { source, destination in
                        var order = session.favorites.map(\.id)
                        order.move(fromOffsets: source, toOffset: destination)
                        if !session.reorderStartPageFavorites(order) { failed = true }
                    }
                    .onDelete { offsets in
                        let ids = offsets.compactMap { session.favorites.indices.contains($0) ? session.favorites[$0].id : nil }
                        for id in ids where !session.removeStartPageFavorite(id) { failed = true }
                    }
                } footer: {
                    if !session.favorites.isEmpty {
                        Text("Drag to change the order. Removing a favorite keeps its bookmark in your Library.")
                    }
                }
                Button("Add Favorite", systemImage: "plus") {
                    editing = LibraryEntry(address: "", title: "", isFavorite: true)
                }.frame(minHeight: 44)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Favorites").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { StartPageFavoriteEditor(session: session, entry: $0) }
            .alert("Couldn’t Update Favorites", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: { Text("Please try again. Your bookmarks are still in your Library.") }
            .onChange(of: session.privateMode) { _, isPrivate in if isPrivate { dismiss() } }
        }
    }
}

struct StartPageFavoriteEditor: View {
    @ObservedObject var session: BrowserSession
    let entry: LibraryEntry
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var address: String
    @State private var failed = false
    @FocusState private var focused: Field?
    private enum Field { case address, title }

    init(session: BrowserSession, entry: LibraryEntry) {
        self.session = session; self.entry = entry
        _title = State(initialValue: entry.title)
        _address = State(initialValue: entry.address)
    }

    private var isNew: Bool { !session.bookmarks.contains { $0.id == entry.id } }
    private var destination: URL? { StartPagePolicy.favoriteURL(address) }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Website", text: $address)
                        .keyboardType(.URL).textContentType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($focused, equals: .address)
                        .submitLabel(.next).onSubmit { focused = .title }
                        .accessibilityIdentifier("start.favorite.address")
                    TextField("Name", text: $title)
                        .focused($focused, equals: .title)
                        .submitLabel(.done).onSubmit { if destination != nil { save() } }
                        .accessibilityIdentifier("start.favorite.name")
                } footer: { Text("For example, apple.com. A name is optional.") }
                if title.count > 512 { Text("Use a shorter name.").foregroundStyle(.secondary) }
            }
            .navigationTitle(isNew ? "Add Favorite" : "Edit Favorite").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.semibold)
                        .disabled(destination == nil || title.count > 512 || session.privateMode)
                        .keyboardShortcut("s", modifiers: .command)
                        .accessibilityIdentifier("start.favorite.save")
                }
            }
            .alert("Couldn’t Save Favorite", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            } message: { Text("Check the website address and try again.") }
            .onAppear { if address.isEmpty { focused = .address } }
            .onChange(of: session.privateMode) { _, isPrivate in if isPrivate { dismiss() } }
        }
    }

    private func save() {
        guard !session.privateMode, title.count <= 512, let destination else { return }
        if session.saveStartPageFavorite(entry, address: destination, name: title) { dismiss() }
        else { failed = true }
    }
}
