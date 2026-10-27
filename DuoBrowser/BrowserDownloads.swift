import UIKit
import WebKit

/// App-owned staging files are temporary, including in normal mode. Files export is explicit.
@MainActor
final class BrowserDownloads: NSObject, WKDownloadDelegate, UIDocumentPickerDelegate {
    private weak var browser: BrowserModel?
    private var active: [ObjectIdentifier: (WKDownload, URL?)] = [:]
    private var ready: [URL] = []
    private var exporting: URL?
    private weak var picker: UIDocumentPickerViewController?
    private let root: URL
    init(browser: BrowserModel) {
        self.browser = browser
        root = Self.stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
    static var stagingRoot: URL { FileManager.default.temporaryDirectory.appendingPathComponent("BrowserDownloads", isDirectory: true) }
    static func cleanPreviousSession() { try? FileManager.default.removeItem(at: stagingRoot) }
    var hasWork: Bool { !active.isEmpty || !ready.isEmpty || exporting != nil }
    func add(_ download: WKDownload) {
        guard active.count + ready.count + (exporting == nil ? 0 : 1) < 5 else {
            download.cancel { _ in }
            browser?.errorMessage = "Save or cancel an existing download before starting another."
            return
        }
        active[ObjectIdentifier(download)] = (download, nil)
        download.delegate = self
        browser?.activeDownloads = active.count
    }
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping @MainActor (URL?) -> Void) {
        guard active[ObjectIdentifier(download)] != nil else { completionHandler(nil); return }
        do {
            let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            let name = Self.safeFilename(suggestedFilename)
            let file = directory.appendingPathComponent(name)
            active[ObjectIdentifier(download)] = (download, file)
            completionHandler(file)
        } catch { completionHandler(nil); browser?.errorMessage = "The download could not be saved temporarily." }
    }
    static func safeFilename(_ input: String) -> String {
        let name = String(input.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last ?? "Download")
        let clean = String(name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }.map(String.init).joined().prefix(180))
        return clean.isEmpty || clean == "." || clean == ".." || clean.hasPrefix(".") ? "Download" : clean
    }
    func downloadDidFinish(_ download: WKDownload) {
        guard let entry = active.removeValue(forKey: ObjectIdentifier(download)), let file = entry.1 else { return }
        ready.append(file)
        browser?.activeDownloads = active.count
        browser?.availableDownloads = ready.count
        exportNext()
    }
    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let file = active.removeValue(forKey: ObjectIdentifier(download))?.1 { remove(file) }
        browser?.activeDownloads = active.count
        browser?.errorMessage = "Download failed. Try the link again."
    }
    func exportNext() {
        guard exporting == nil, !ready.isEmpty, let presenter = browser?.presentation.presenter,
              presenter.presentedViewController == nil, !(presenter is UIAlertController),
              !(presenter is UIDocumentPickerViewController) else { return }
        let file = ready.removeFirst()
        exporting = file
        browser?.availableDownloads = ready.count
        let picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
        picker.delegate = self
        self.picker = picker
        presenter.present(picker, animated: true)
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { finishedExport() }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { finishedExport() }
    private func finishedExport() {
        if let exporting { remove(exporting) }
        exporting = nil
        picker = nil
        // Any additional completed download can be exported from Page options.
    }
    private func remove(_ file: URL) { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    func cancelAll() {
        let downloads = active.values.map(\.0)
        active.removeAll()
        browser?.activeDownloads = 0
        browser?.availableDownloads = 0
        for download in downloads { download.delegate = nil; download.cancel { _ in } }
        ready.removeAll()
        exporting = nil
        picker?.dismiss(animated: false)
        picker = nil
        try? FileManager.default.removeItem(at: root)
    }
}
