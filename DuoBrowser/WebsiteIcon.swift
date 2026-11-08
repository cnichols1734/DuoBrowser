import SwiftUI
import ImageIO

struct WebsiteIcon: View {
    let address: String
    let title: String
    var size: CGFloat = 32
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else {
                Text(String((title.isEmpty ? URL(string: address)?.host ?? "?" : title).prefix(1)).uppercased())
                    .font(.system(size: size * 0.52, weight: .regular)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
        .task(id: address) { image = await WebsiteIconLoader.shared.icon(for: address) }
    }
}

/// Direct website requests only: no favicon aggregator, cookies, credentials or persistent network cache.
@MainActor
final class WebsiteIconLoader {
    static let shared = WebsiteIconLoader()
    private let cache = NSCache<NSString, UIImage>()
    private var failed = Set<String>()
    private init() { cache.countLimit = 100; cache.totalCostLimit = 6 * 1024 * 1024 }
    func icon(for address: String) async -> UIImage? {
        guard let url = WebAddress.valid(URL(string: address)), url.scheme == "https", let host = url.host else { return nil }
        if let cached = cache.object(forKey: host as NSString) { return cached }
        guard !failed.contains(host) else { return nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 3; configuration.timeoutIntervalForResource = 4
        let session = URLSession(configuration: configuration, delegate: SearchSuggestionClient(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var candidates: [URL] = []
        // Public, high-resolution site-owned icons for sites whose root favicon is only 16px.
        let known = [
            "www.youtube.com": "https://www.youtube.com/s/desktop/4e57be2c/img/favicon_144x144.png",
            "google.com": "https://www.google.com/images/branding/googleg/2x/googleg_standard_color_120dp.png",
            "www.google.com": "https://www.google.com/images/branding/googleg/2x/googleg_standard_color_120dp.png",
            "mail.google.com": "https://ssl.gstatic.com/ui/v1/icons/mail/rfr/gmail.ico",
            "www.reddit.com": "https://www.redditstatic.com/desktop2x/img/favicon/apple-icon-180x180.png",
            "chatgpt.com": "https://chatgpt.com/cdn/assets/favicon-180x180.9e0103ce69.png",
            "gemini.google.com": "https://www.gstatic.com/lamda/images/gemini_sparkle_4g_512_lt_f94943af3be039176192d.png"
        ]
        if let address = known[host], let target = URL(string: address) { candidates.append(target) }
        // Read only the bounded document head to discover this site's declared icon; never execute it.
        var origin = URLComponents(); origin.scheme = "https"; origin.host = host; origin.port = url.port
        if known[host] == nil, let home = origin.url, let bytes = try? await read(home, session: session, limit: 131_072),
           !bytes.isEmpty {
            let html = String(decoding: bytes, as: UTF8.self)
            let regex = try? NSRegularExpression(pattern: "<link\\b[^>]{0,4096}>", options: .caseInsensitive)
            let links = regex?.matches(in: html, range: NSRange(html.startIndex..., in: html)) ?? []
            var declared: [(URL, Int)] = []
            for link in links.prefix(100) {
                let tag = String(html[Range(link.range, in: html)!])
                guard let rel = attribute("rel", in: tag)?.lowercased(), rel.contains("icon"),
                      let href = attribute("href", in: tag), let target = URL(string: href, relativeTo: home)?.absoluteURL,
                      WebAddress.valid(target) != nil, target.scheme == "https", target.pathExtension.lowercased() != "svg",
                      target.host == host || (host == "gemini.google.com" && target.host == "www.gstatic.com") else { continue }
                let size = Int((attribute("sizes", in: tag) ?? "0").split(separator: "x").first ?? "0") ?? 0
                declared.append((target, rel.contains("apple-touch") ? max(size, 180) : size))
            }
            candidates += declared.sorted { $0.1 > $1.1 }.prefix(2).map(\.0)
        }
        for path in ["/apple-touch-icon.png", "/favicon.ico"] {
            origin.path = path
            if let target = origin.url { candidates.append(target) }
        }
        for target in candidates {
            guard !Task.isCancelled else { return nil }
            do {
                let data = try await read(target, session: session, limit: 262_144)
                guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { continue }
                let best = (0..<min(20, CGImageSourceGetCount(source))).max { left, right in
                    func width(_ index: Int) -> Int {
                        (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any])?[kCGImagePropertyPixelWidth] as? Int ?? 0
                    }
                    return width(left) < width(right)
                } ?? 0
                guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, best, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceThumbnailMaxPixelSize: 216,
                    kCGImageSourceCreateThumbnailWithTransform: true
                ] as CFDictionary) else { continue }
                let image = UIImage(cgImage: thumbnail)
                cache.setObject(image, forKey: host as NSString, cost: thumbnail.bytesPerRow * thumbnail.height)
                return image
            } catch { if Task.isCancelled { return nil } }
        }
        if failed.count < 500 { failed.insert(host) }
        return nil
    }
    nonisolated private func read(_ url: URL, session: URLSession, limit: Int) async throws -> Data {
        let (bytes, response) = try await session.bytes(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < limit else { break }
            data.append(byte)
        }
        return data
    }
    private func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\s" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for index in 1...2 { if let range = Range(match.range(at: index), in: tag) { return String(tag[range]).replacingOccurrences(of: "&amp;", with: "&") } }
        return nil
    }

}
