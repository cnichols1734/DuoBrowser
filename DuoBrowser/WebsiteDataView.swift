import SwiftUI

struct ClearBrowsingDataView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var model: WebsiteDataController
    @State private var selection = BrowsingDataSelection()
    @State private var confirm = false
    @State private var result: String?
    @State private var websiteMessage: String?

    var body: some View {
        Form {
            Section {
                Toggle("Browsing History", isOn: $selection.history)
                Toggle("Cookies & Site Data", isOn: $selection.siteData)
                Toggle("Cached Files", isOn: $selection.cache)
            } header: { Text("Normal Browsing") } footer: {
                Text("Cookies and site data can keep you signed in and store website preferences. Removing them may sign you out. Cached files can be downloaded again.")
            }
            .disabled(model.isBusy || session.privateMode)
            Section {
                Button("Clear Selected Data", role: .destructive) { result = nil; confirm = true }
                    .disabled(selection.isEmpty || model.isBusy || session.privateMode)
                if model.isBusy { ProgressView("Removing data…") }
                if let result { Text(result).foregroundStyle(.secondary) }
                if let websiteMessage { Text(websiteMessage).foregroundStyle(.secondary) }
            } footer: {
                Text("Saved pages, bookmarks, downloaded files and open tabs remain. Open websites can save new data after clearing. Private browsing is separate.")
            }
        }
        .navigationTitle("Clear Browsing Data")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isRemoving)
        .interactiveDismissDisabled(model.isRemoving)
        .confirmationDialog("Clear the selected normal browsing data?", isPresented: $confirm) {
            Button("Clear Selected Data", role: .destructive) { clearConfirmed() }
        } message: { Text(selection.siteData ? "This cannot be undone. Cookies and site data may sign you out of websites." : "This cannot be undone.") }
    }

    private func clearConfirmed() {
        guard !session.privateMode, !selection.isEmpty, !model.isBusy else { return }
        let requested = selection
        Task { @MainActor in
            guard !session.privateMode, !model.isBusy else { return }
            result = nil
            websiteMessage = nil
            if requested.history && !session.clearHistoryFromSettings() {
                result = "Browsing history couldn’t be cleared. Try again."
                return
            }
            if await model.clear(requested) { result = "Selected data cleared." }
            else if requested.history { result = "Browsing history cleared." }
            websiteMessage = model.message
        }
    }
}

struct WebsiteDataView: View {
    @ObservedObject var session: BrowserSession
    @ObservedObject var model: WebsiteDataController
    @State private var search = ""
    @State private var removing: WebsiteDataController.Entry?
    @State private var confirmRemoval = false
    private var searchTerm: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var visibleEntries: [WebsiteDataController.Entry] {
        model.entries.filter { searchTerm.isEmpty || $0.name.localizedCaseInsensitiveContains(searchTerm) }
    }

    var body: some View {
        List {
            if session.privateMode {
                Text("Return to normal browsing to manage its saved website data.")
            } else {
                if model.isBusy { ProgressView(model.isRemoving ? "Removing website data…" : "Loading website data…") }
                if let message = model.message { Text(message).font(.callout).foregroundStyle(.secondary) }
                if model.entries.isEmpty && !model.isBusy && model.hasLoaded {
                    ContentUnavailableView("No Website Data", systemImage: "globe", description: Text("Data saved by websites in normal browsing appears here."))
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else if !searchTerm.isEmpty, visibleEntries.isEmpty, !model.isBusy, model.hasLoaded {
                    ContentUnavailableView.search(text: searchTerm)
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                Section {
                    ForEach(visibleEntries) { entry in
                        Button { removing = entry; confirmRemoval = true } label: {
                            HStack {
                                Text(verbatim: entry.name).foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "trash").foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove website data for " + entry.name)
                        .disabled(model.isBusy)
                    }
                } footer: {
                    Text("WebKit groups related website data by domain. Removing a group clears its cookies, stored data and cached files, and may sign you out. This does not delete bookmarks or downloads.")
                }
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.reload() } }
                    .frame(minHeight: 44).disabled(model.isBusy)
            }
        }
        .searchable(text: $search, prompt: "Search Websites")
        .navigationTitle("Website Data")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isRemoving)
        .interactiveDismissDisabled(model.isRemoving)
        .task { if !session.privateMode { await model.reload() } }
        .onDisappear { model.cancelRefresh() }
        .onChange(of: session.privateMode) { _, _ in removing = nil; confirmRemoval = false; model.cancelRefresh() }
        .confirmationDialog("Remove data for \(removing?.name ?? "this website")?", isPresented: $confirmRemoval) {
            Button("Remove Website Data", role: .destructive) {
                guard !session.privateMode, let entry = removing else { return }
                removing = nil
                Task { @MainActor in
                    guard !session.privateMode else { return }
                    await model.removeEntry(entry.id)
                }
            }
        } message: { Text("This cannot be undone and may sign you out. Related subdomains in this WebKit group are included.") }
    }
}
