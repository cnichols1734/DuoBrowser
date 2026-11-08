import SwiftUI
import SafariServices
import UniformTypeIdentifiers

struct SafariImportView: View {
    @ObservedObject var session: BrowserSession
    @Environment(\.dismiss) private var dismiss
    @State private var picking = false
    @State private var loading = false
    @State private var preview: SafariBookmarkImport.Preview?
    @State private var folder = ""
    @State private var message: String?
    @State private var finished = false

    private var initialDirectory: URL? {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--import-qa") {
            return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        #endif
        return nil
    }
    var body: some View {
        NavigationStack {
            List {
                if let preview {
                    Section {
                        Picker("Folder", selection: $folder) {
                            Text("All Bookmarks").tag("")
                            ForEach(preview.folders, id: \.self) { Text($0).tag($0) }
                        }
                        let entries = preview.entries(in: folder)
                        Text("\(entries.count) websites").foregroundStyle(.secondary)
                        ForEach(Array(entries.prefix(12))) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: entry.title).lineLimit(1)
                                Text(verbatim: URL(string: entry.address)?.host ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } header: { Text("Preview") } footer: {
                        Text("Existing favorites stay in place. Duplicate addresses are skipped. Up to 500 favorites can be saved.")
                    }
                    Button("Import Favorites") {
                        do {
                            let count = try session.importFavorites(preview.entries(in: folder))
                            message = count == 0 ? "These favorites are already saved." : "Added \(count) favorites."
                            finished = true
                        } catch { message = error.localizedDescription }
                    }.disabled(preview.entries(in: folder).isEmpty)
                } else {
                    Section {
                        Text("Bring your Safari favorites into DuoBrowser.")
                        Text("Export Bookmarks from Safari, then return here and choose the exported ZIP or HTML file.")
                            .foregroundStyle(.secondary)
                        Button("Export from Safari") {
                            SFSafariSettings.openExportBrowsingDataSettings { error in
                                if error != nil { message = "Open Settings → Apps → Safari → Export Browsing Data, then select Bookmarks." }
                            }
                        }
                    } footer: { Text("Choose only Bookmarks in Safari’s export screen. DuoBrowser imports website bookmarks, never passwords, payment details, or browsing history.") }
                }
                Section {
                    Button(preview == nil ? "Choose Exported File" : "Choose Another File") { picking = true }
                        .disabled(loading)
                    if loading { ProgressView("Reading bookmarks…") }
                } footer: { Text("Favorites are saved on this device. Website icons are loaded directly from the saved websites.") }
            }
            .navigationTitle("Import Safari Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(loading) } }
            .fileImporter(isPresented: $picking, allowedContentTypes: [.zip, .html], allowsMultipleSelection: false) { result in
                guard case let .success(urls) = result, let url = urls.first else { return }
                loading = true
                Task {
                    do {
                        let value = try await Task.detached(priority: .userInitiated) { try SafariBookmarkImport.read(url) }.value
                        preview = value; folder = value.preferredFolder
                    } catch { message = error.localizedDescription }
                    loading = false
                }
            }
            .fileDialogDefaultDirectory(initialDirectory)
            .alert(finished ? "Favorites Imported" : "Import Favorites", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil; if finished { dismiss() } }
            } message: { Text(message ?? "") }
        }
    }
}
