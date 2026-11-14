import QuickLook
import SwiftUI

struct DownloadsView: View {
    @ObservedObject var manager: BrowserDownloads
    @Environment(\.dismiss) private var dismiss
    @State private var preview: URL?
    @State private var exporting: DownloadExport?
    @State private var removing: BrowserDownload?

    var body: some View {
        NavigationStack {
            List {
                if manager.items.isEmpty {
                    ContentUnavailableView("No Downloads", systemImage: "arrow.down.doc",
                        description: Text(manager.isPrivate
                            ? "Files downloaded in private tabs appear here. Save a copy to Files before closing all private tabs."
                            : "Files you download appear here. You can preview them or save a copy to Files."))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                } else {
                    Section {
                        ForEach(manager.items) { item in
                            DownloadRow(item: item, preview: { preview = item.file }, export: {
                                if let file = item.file { exporting = DownloadExport(url: file) }
                            }, retry: { manager.retry(item) }, cancel: { manager.cancel(item) }, remove: { removing = item })
                        }
                    } footer: {
                        Text(manager.isPrivate
                             ? "Private downloads are removed when you close all private tabs. Save a copy to Files to keep one."
                             : "Downloads stay on this device until you remove them. Save a copy to Files to keep it elsewhere.")
                    }
                }
            }
            .onAppear { manager.hasUnseenDownloads = false }
            .onDisappear { manager.hasUnseenDownloads = false }
            .navigationTitle(manager.isPrivate ? "Private Downloads" : "Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .quickLookPreview($preview)
            .sheet(item: $exporting) { DownloadExporter(file: $0.url) }
            .confirmationDialog("Remove this download?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
                Button("Remove Download", role: .destructive) {
                    if let removing { manager.remove(removing) }; removing = nil
                }
            } message: { Text("This removes the copy in DuoBrowser. Copies already saved to Files are kept.") }
            .alert("Downloads", isPresented: Binding(get: { manager.errorMessage != nil }, set: { if !$0 { manager.errorMessage = nil } })) {
                Button("OK") { manager.errorMessage = nil }
            } message: { Text(manager.errorMessage ?? "") }
            .onChange(of: manager.items.map(\.id)) { _, _ in
                if let preview, !manager.items.contains(where: { $0.file == preview }) { self.preview = nil }
                if let exporting, !manager.items.contains(where: { $0.file == exporting.url }) { self.exporting = nil }
                if let removing, !manager.items.contains(where: { $0.id == removing.id }) { self.removing = nil }
            }
        }
    }
}

private struct DownloadRow: View {
    @ObservedObject var item: BrowserDownload
    let preview: () -> Void
    let export: () -> Void
    let retry: () -> Void
    let cancel: () -> Void
    let remove: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var byteLabel: String {
        let received = ByteCountFormatter.string(fromByteCount: item.received, countStyle: .file)
        if item.isDownloading, item.expected > 0 {
            return received + " of " + ByteCountFormatter.string(fromByteCount: item.expected, countStyle: .file)
        }
        return received
    }
    private var ready: Bool { [.completed, .recovered].contains(item.state) && item.file != nil && !item.isDownloading }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: item.isCanceling || item.isDownloading ? "arrow.down.doc" : ready ? "doc" : "exclamationmark.circle")
                    .font(.title2).foregroundStyle(.secondary).frame(width: 28, height: 44).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 6) {
                if ready {
                    Button(action: preview) { filename }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.name), Preview")
                        .accessibilityHint("Opens a preview of this file")
                } else {
                    filename
                }
                if item.isCanceling {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Canceling…").font(.subheadline).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine)
                } else if item.isDownloading {
                    if item.expected > 0 {
                        ProgressView(value: Double(item.received), total: Double(max(item.expected, item.received)))
                            .accessibilityLabel("Download progress")
                    } else { ProgressView().accessibilityLabel("Downloading") }
                    Text(byteLabel).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                } else if ready {
                    Text(byteLabel + " · " + item.date.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    if item.state == .recovered {
                        Text("Recovered file. Check its contents before keeping a copy.").font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    Text(item.message ?? "Download interrupted").font(.subheadline).foregroundStyle(.secondary)
                    if item.canRetry { Button("Retry", action: retry).frame(minHeight: 44).buttonStyle(.borderless) }
                }
            }
            if item.isCanceling {
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            } else if item.isDownloading {
                Button(action: cancel) { Image(systemName: "xmark.circle").frame(width: 44, height: 44) }
                    .buttonStyle(.borderless).accessibilityLabel("Cancel download, \(item.name)")
            } else {
                Menu {
                    if ready {
                        Button("Preview", systemImage: "doc.text.magnifyingglass", action: preview)
                        Button("Save to Files", systemImage: "folder", action: export)
                    }
                    if item.canRetry { Button("Retry", systemImage: "arrow.clockwise", action: retry) }
                    Button("Remove Download", systemImage: "trash", role: .destructive, action: remove)
                } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44) }
                    .accessibilityLabel("Actions for \(item.name)")
            }
        }
        .padding(.vertical, 6)
        .swipeActions { Button("Remove", role: .destructive, action: remove).disabled(item.isCanceling) }
    }

    private var filename: some View {
        Text(verbatim: item.name).font(.body.weight(.medium)).foregroundStyle(.primary)
            .multilineTextAlignment(.leading).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
}

private struct DownloadExport: Identifiable { let id = UUID(); let url: URL }

/// The exporter only copies. Dismissing or canceling it never removes the retained download.
struct DownloadExporter: UIViewControllerRepresentable {
    let file: URL
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(dismiss: { dismiss() }) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let dismiss: () -> Void
        init(dismiss: @escaping () -> Void) { self.dismiss = dismiss }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { dismiss() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { dismiss() }
    }
}


struct DownloadMenuAction: View {
    @ObservedObject var manager: BrowserDownloads
    let action: () -> Void
    var body: some View {
        Button(manager.activeCount == 0 ? "Downloads" : "Downloads (\(manager.activeCount) active)",
               systemImage: "arrow.down.circle", action: action)
    }
}

struct DownloadPageOptionsSymbol: View {
    @ObservedObject var manager: BrowserDownloads
    var body: some View {
        Image(systemName: "line.3.horizontal.decrease").frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                if manager.activeCount > 0 || manager.hasUnseenDownloads {
                    Image(systemName: "arrow.down.circle.fill").font(.caption2).foregroundStyle(.tint)
                        .padding(3).accessibilityHidden(true)
                }
            }
    }
}
