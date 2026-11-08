import Foundation
import zlib

/// Parses inert bookmark data only. ZIP members are never extracted to the filesystem.
enum SafariBookmarkImport {
    static let maximumFileSize = 20_000_000
    static let maximumHTMLSize = 4_000_000
    struct Item: Identifiable {
        let id = UUID()
        let title: String
        let address: String
        let folder: String
    }
    struct Preview {
        var items: [Item]
        var folders: [String]
        var preferredFolder: String
        func entries(in folder: String) -> [LibraryEntry] {
            items.filter { folder.isEmpty || $0.folder == folder || $0.folder.hasPrefix(folder + " / ") }
                .map { LibraryEntry(id: $0.id, address: $0.address, title: $0.title) }
        }
    }
    enum Failure: LocalizedError {
        case invalid, tooLarge, unsupported, noBookmarks
        var errorDescription: String? {
            switch self {
            case .invalid: return "This file could not be read as Safari bookmarks. Choose a Safari export ZIP or Bookmarks.html file."
            case .tooLarge: return "This export is too large. Export only Bookmarks from Safari, then try again."
            case .unsupported: return "This ZIP format isn’t supported. Open the ZIP in Files, then choose its bookmarks HTML file."
            case .noBookmarks: return "No website bookmarks were found in this file."
            }
        }
    }
    static func read(_ url: URL) throws -> Preview {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= maximumFileSize else { throw Failure.tooLarge }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try parse(data)
    }
    static func parse(_ data: Data) throws -> Preview {
        guard data.count <= maximumFileSize else { throw Failure.tooLarge }
        let documents = data.starts(with: [0x50, 0x4b]) ? try bookmarkDocuments(in: data) : [data]
        var items: [Item] = [], folders: [String] = [], preferred = ""
        for document in documents {
            let result = try parseHTML(document)
            items += result.items
            folders += result.folders.filter { !folders.contains($0) }
            if preferred.isEmpty { preferred = result.preferredFolder }
        }
        guard !items.isEmpty else { throw Failure.noBookmarks }
        return Preview(items: Array(items.prefix(5000)), folders: folders, preferredFolder: preferred)
    }

    private static func parseHTML(_ data: Data) throws -> Preview {
        guard data.count <= maximumHTMLSize else { throw Failure.tooLarge }
        guard let html = String(data: data, encoding: .utf8), html.localizedCaseInsensitiveContains("NETSCAPE-Bookmark-file") else { throw Failure.invalid }
        let tokenPattern = try NSRegularExpression(pattern: "<!--[\\s\\S]*?-->|<[^>]{0,32768}>|[^<]+")
        let tokens = tokenPattern.matches(in: html, range: NSRange(html.startIndex..., in: html))
        guard tokens.count <= 100_000 else { throw Failure.tooLarge }
        var stack: [(String, Bool)] = [], pending: (String, Bool)?, heading = "", headingTag = "", link = "", label = ""
        var readingHeading = false, readingLink = false, hiddenTag = "", preferred = ""
        var items: [Item] = [], folders: [String] = [], seen = Set<String>()
        for token in tokens {
            let text = String(html[Range(token.range, in: html)!]), lower = text.lowercased()
            if lower.hasPrefix("<script") { hiddenTag = "script" }
            if lower.hasPrefix("<style") { hiddenTag = "style" }
            if !hiddenTag.isEmpty { if lower.hasPrefix("</" + hiddenTag) { hiddenTag = "" }; continue }
            if lower.hasPrefix("<!--") { continue }
            if lower.range(of: "^<h3(?:\\s|>)", options: .regularExpression) != nil {
                readingHeading = true; heading = ""; headingTag = text
            } else if lower.hasPrefix("</h3") {
                readingHeading = false
                let title = String(decodeEntities(heading).trimmingCharacters(in: .whitespacesAndNewlines).prefix(128))
                let readingList = headingTag.contains("com.apple.ReadingList")
                pending = (title, readingList)
                if attribute("personal_toolbar_folder", in: headingTag)?.lowercased() == "true" || title.lowercased() == "favorites" || headingTag.contains("com.apple.BookmarksBar") {
                    preferred = (stack.map(\.0).filter { !$0.isEmpty } + [title]).joined(separator: " / ")
                }
            } else if lower.range(of: "^<dl(?:\\s|>)", options: .regularExpression) != nil {
                guard stack.count < 32 else { throw Failure.tooLarge }
                stack.append(pending ?? ("", false)); pending = nil
                let folder = stack.map(\.0).filter { !$0.isEmpty }.joined(separator: " / ")
                if !folder.isEmpty && !folders.contains(folder) && !stack.contains(where: { $0.1 }) { folders.append(folder) }
            } else if lower.hasPrefix("</dl") {
                if !stack.isEmpty { stack.removeLast() }
            } else if lower.range(of: "^<a(?:\\s|>)", options: .regularExpression) != nil {
                readingLink = true; link = attribute("href", in: text) ?? ""; label = ""
            } else if lower.hasPrefix("</a") {
                readingLink = false
                if !stack.contains(where: { $0.1 }), let url = WebAddress.valid(URL(string: decodeEntities(link))), seen.insert(stack.map(\.0).joined(separator: "/") + "|" + url.absoluteString).inserted {
                    let title = String(decodeEntities(label).trimmingCharacters(in: .whitespacesAndNewlines).prefix(512))
                    items.append(Item(title: title.isEmpty ? url.host ?? "Website" : title, address: url.absoluteString,
                                      folder: stack.map(\.0).filter { !$0.isEmpty }.joined(separator: " / ")))
                    guard items.count <= 5000 else { throw Failure.tooLarge }
                }
            } else if !text.hasPrefix("<") {
                if readingHeading { heading += text }
                if readingLink { label += text }
            }
        }
        return Preview(items: items, folders: folders, preferredFolder: preferred)
    }
    private static func attribute(_ name: String, in tag: String) -> String? {
        let regex = try? NSRegularExpression(pattern: "\\b" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))", options: .caseInsensitive)
        guard let match = regex?.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for index in 1...3 { if let range = Range(match.range(at: index), in: tag) { return String(tag[range]) } }
        return nil
    }
    private static func decodeEntities(_ text: String) -> String {
        let names = ["amp": "&", "quot": "\"", "apos": "'", "lt": "<", "gt": ">", "nbsp": " "]
        let regex = try! NSRegularExpression(pattern: "&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);")
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            let key = String(text[Range(match.range(at: 1), in: text)!])
            var replacement = names[key]
            if key.hasPrefix("#") {
                let hex = key.hasPrefix("#x")
                if let value = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10), let scalar = UnicodeScalar(value), !CharacterSet.controlCharacters.contains(scalar) { replacement = String(scalar) }
            }
            if let replacement, let range = Range(match.range, in: result) { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }

    private static func bookmarkDocuments(in data: Data) throws -> [Data] {
        func number(_ offset: Int, _ size: Int) throws -> Int {
            guard offset >= 0, offset <= data.count - size else { throw Failure.invalid }
            return (0..<size).reduce(0) { $0 | Int(data[offset + $1]) << ($1 * 8) }
        }
        guard data.count >= 22 else { throw Failure.invalid }
        var end: Int?
        for offset in stride(from: data.count - 22, through: max(0, data.count - 65_557), by: -1) {
            if try number(offset, 4) == 0x06054b50, try offset + 22 + number(offset + 20, 2) == data.count { end = offset; break }
        }
        guard let end, try number(end + 4, 2) == 0, try number(end + 6, 2) == 0 else { throw Failure.unsupported }
        let count = try number(end + 10, 2)
        guard count <= 1000 else { throw Failure.tooLarge }
        var offset = try number(end + 16, 4), documents: [Data] = [], total = 0
        for _ in 0..<count {
            guard try number(offset, 4) == 0x02014b50 else { throw Failure.invalid }
            let flags = try number(offset + 8, 2), method = try number(offset + 10, 2)
            let crc = try number(offset + 16, 4), compressed = try number(offset + 20, 4), expanded = try number(offset + 24, 4)
            let nameLength = try number(offset + 28, 2), extra = try number(offset + 30, 2), comment = try number(offset + 32, 2)
            let local = try number(offset + 42, 4), next = offset + 46 + nameLength + extra + comment
            guard next <= end, offset + 46 + nameLength <= data.count else { throw Failure.invalid }
            let name = String(decoding: data[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            offset = next
            // Localized bookmark filenames are fine; unrelated export records are never decompressed.
            guard ["html", "htm"].contains((name as NSString).pathExtension.lowercased()) else { continue }
            guard flags & 1 == 0, [0, 8].contains(method) else { throw Failure.unsupported }
            guard expanded <= maximumHTMLSize, compressed <= maximumFileSize, total + expanded <= maximumHTMLSize else { throw Failure.tooLarge }
            guard try number(local, 4) == 0x04034b50 else { throw Failure.invalid }
            let start = try local + 30 + number(local + 26, 2) + number(local + 28, 2)
            guard start <= data.count, compressed <= data.count - start else { throw Failure.invalid }
            let source = Data(data[start..<(start + compressed)])
            let output: Data
            if method == 0 { output = source }
            else {
                var stream = z_stream()
                guard inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { throw Failure.invalid }
                defer { inflateEnd(&stream) }
                var buffer = [UInt8](repeating: 0, count: max(1, expanded))
                let status = source.withUnsafeBytes { input in
                    buffer.withUnsafeMutableBytes { target -> Int32 in
                        stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
                        stream.avail_in = uInt(source.count)
                        stream.next_out = target.bindMemory(to: UInt8.self).baseAddress
                        stream.avail_out = uInt(target.count)
                        return inflate(&stream, Z_FINISH)
                    }
                }
                guard status == Z_STREAM_END, stream.total_out == expanded, stream.total_in == compressed else { throw Failure.invalid }
                output = Data(buffer.prefix(expanded))
            }
            guard output.count == expanded else { throw Failure.invalid }
            let checksum = output.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, uInt(output.count)) }
            guard checksum == crc else { throw Failure.invalid }
            documents.append(output); total += expanded
        }
        guard !documents.isEmpty else { throw Failure.noBookmarks }
        return documents
    }
}
