import SwiftUI
import ImageIO

struct WebsiteIcon: View {
    let address: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().interpolation(.high).scaledToFit().frame(width: 48, height: 48)
                    .padding(6).background(.white, in: RoundedRectangle(cornerRadius: 12))
            } else {
                let host = URL(string: address)?.host?.replacingOccurrences(of: "www.", with: "") ?? ""
                Text(String(host.prefix(1)).uppercased()).font(.largeTitle.weight(.semibold))
            }
        }
        .frame(width: 64, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .accessibilityHidden(true)
        .task(id: address) {
            image = nil
            let loaded = await WebsiteIconStore.shared.image(for: address)
            guard !Task.isCancelled else { return }
            image = loaded
        }
    }
}

/// Normal start-page icons only. No browsing paths, cookies, credentials or third-party icon service.
@MainActor
final class WebsiteIconStore {
    static let shared = WebsiteIconStore()
    private let images = NSCache<NSURL, UIImage>()
    private let misses = NSCache<NSURL, NSDate>()
    private var pending: [URL: Task<UIImage?, Never>] = [:]
    private var generation = UUID()

    init() {
        images.countLimit = 64
        images.totalCostLimit = 4 * 1024 * 1024
        misses.countLimit = 64
    }

    func image(for address: String) async -> UIImage? {
        guard let url = WebsiteIconLoader.url(for: address) else { return nil }
        if let image = images.object(forKey: url as NSURL) { return image }
        if let until = misses.object(forKey: url as NSURL), until.timeIntervalSinceNow > 0 { return nil }
        if let task = pending[url] {
            let current = generation
            let image = await task.value
            return generation == current ? image : nil
        }
        guard pending.count < 16 else { return nil }
        let current = generation
        let task = Task { await WebsiteIconLoader.fetch(url) }
        pending[url] = task
        let image = await task.value
        guard generation == current else { return nil }
        pending[url] = nil
        if let image, let cg = image.cgImage {
            images.setObject(image, forKey: url as NSURL, cost: cg.bytesPerRow * cg.height)
        } else if !task.isCancelled {
            misses.setObject(Date().addingTimeInterval(300) as NSDate, forKey: url as NSURL)
        }
        return image
    }

    func clear() {
        generation = UUID()
        pending.values.forEach { $0.cancel() }
        pending.removeAll()
        images.removeAllObjects()
        misses.removeAllObjects()
    }
}

enum WebsiteIconLoader {
    static let maximumBytes = 1_048_576

    static func url(for address: String) -> URL? {
        guard let valid = WebAddress.valid(URL(string: address)),
              var parts = URLComponents(url: valid, resolvingAgainstBaseURL: false) else { return nil }
        parts.path = "/favicon.ico"
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }

    static func redirectAllowed(_ url: URL?) -> Bool {
        guard let url = WebAddress.valid(url) else { return false }
        return url.scheme == "https"
    }

    static func decode(_ data: Data) -> UIImage? {
        guard data.count <= maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              (1...32).contains(CGImageSourceGetCount(source)) else { return nil }
        // ICO files commonly contain several sizes; choose the sharpest bounded representation.
        let best = (0..<CGImageSourceGetCount(source)).compactMap { index -> (Int, Int)? in
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  (1...16_384).contains(width), (1...16_384).contains(height) else { return nil }
            return (index, width * height)
        }.max { $0.1 < $1.1 }
        guard let best, let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, best.0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 144,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    /// Parse a bounded, inert HTML head; never instantiate a web view or execute page code.
    static func candidates(in html: String, base: URL) -> [URL] {
        let head = String(html.prefix(262_144)).components(separatedBy: "</head>")[0]
        guard let tags = try? NSRegularExpression(pattern: "<link\\b[^>]{0,4096}>", options: .caseInsensitive),
              let attributes = try? NSRegularExpression(
                pattern: #"([a-zA-Z-]+)\s*=\s*(?:"([^"<>]*)"|'([^'<>]*)'|([^\s>]+))"#) else { return [] }
        var ranked: [(URL, Int)] = []
        let source = head as NSString
        for tag in tags.matches(in: head, range: NSRange(location: 0, length: source.length)).prefix(64) {
            let text = source.substring(with: tag.range), ns = source.substring(with: tag.range) as NSString
            var values: [String: String] = [:]
            for match in attributes.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                guard let valueRange = (2...4).map({ match.range(at: $0) }).first(where: { $0.location != NSNotFound }) else { continue }
                values[ns.substring(with: match.range(at: 1)).lowercased()] = ns.substring(with: valueRange)
            }
            let rel = (values["rel"] ?? "").lowercased().split(whereSeparator: \.isWhitespace)
            guard rel.contains("icon") || rel.contains("apple-touch-icon") || rel.contains("apple-touch-icon-precomposed") || rel.contains("fluid-icon"),
                  values["type"]?.lowercased() != "image/svg+xml",
                  let href = values["href"], href.count <= 2048,
                  let url = WebAddress.valid(URL(string: href.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: base)?.absoluteURL),
                  url.scheme == "https" || (base.scheme == "http" && url.host == base.host),
                  url.pathExtension.lowercased() != "svg" else { continue }
            let size = (values["sizes"] ?? "").lowercased().split(separator: " ").compactMap {
                Int($0.split(separator: "x").first ?? "")
            }.max() ?? (rel.contains("fluid-icon") ? 512 : (rel.contains(where: { $0.hasPrefix("apple-touch-icon") }) ? 180 : 32))
            ranked.append((url, min(size, 4096)))
        }
        var seen = Set<URL>()
        return ranked.sorted { $0.1 > $1.1 }.map(\.0).filter { seen.insert($0).inserted }
    }

    static func fetch(_ url: URL) async -> UIImage? {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 6
        let session = URLSession(configuration: config, delegate: WebsiteIconRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let root = url.deletingLastPathComponent()
        async let fallback = data(from: url, session: session).flatMap(decode)
        let page = await data(from: root, session: session, headOnly: true)
        let html = page.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var urls = Array(candidates(in: html, base: root).prefix(3))
        // Reddit advertises only 64px in its head; its own published Retina asset is 192px.
        if ["reddit.com", "www.reddit.com"].contains(root.host?.lowercased() ?? ""),
           let retina = URL(string: "https://www.redditstatic.com/shreddit/assets/favicon/192x192.png") {
            urls.insert(retina, at: 0)
            urls = Array(urls.prefix(3))
        }
        let touch = root.appendingPathComponent("apple-touch-icon.png")
        if !urls.contains(touch) { urls.append(touch) }
        let best = await withTaskGroup(of: UIImage?.self) { group in
            for candidate in urls { group.addTask { await data(from: candidate, session: session).flatMap(decode) } }
            var best: UIImage?
            for await image in group {
                if let image, pixels(image) > pixels(best) { best = image }
            }
            return best
        }
        let small = await fallback
        guard !Task.isCancelled else { return nil }
        return pixels(best) >= pixels(small) ? best : small
    }

    private static func pixels(_ image: UIImage?) -> Int {
        guard let cg = image?.cgImage else { return 0 }
        return min(cg.width, cg.height)
    }

    private static func data(from url: URL, session: URLSession, headOnly: Bool = false) async -> Data? {
        do {
            var request = URLRequest(url: url)
            if headOnly {
                // Sites commonly advertise Retina touch icons only to mobile browsers.
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            }
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  headOnly || response.expectedContentLength <= maximumBytes else { return nil }
            var data = Data()
            let limit = headOnly ? 262_144 : maximumBytes
            for try await byte in bytes {
                try Task.checkCancellation()
                if data.count >= limit { return headOnly ? data : nil }
                data.append(byte)
            }
            try Task.checkCancellation()
            return data
        } catch { return nil }
    }

}

/// Favicon hosts can redirect to a CDN (for example Gmail); never follow credentials or a downgrade.
private final class WebsiteIconRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var redirects: [Int: Int] = [:] // URLSession's delegate queue is serial.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let count = (redirects[task.taskIdentifier] ?? 0) + 1
        redirects[task.taskIdentifier] = count
        completionHandler(count <= 3 && WebsiteIconLoader.redirectAllowed(request.url) ? request : nil)
    }
}
