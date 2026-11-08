import SwiftUI
import ImageIO

struct WebsiteIcon: View {
    let address: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().frame(width: 32, height: 32)
                    .padding(4).background(.white, in: RoundedRectangle(cornerRadius: 8))
            } else {
                let host = URL(string: address)?.host?.replacingOccurrences(of: "www.", with: "") ?? ""
                Text(String(host.prefix(1)).uppercased()).font(.title2.weight(.semibold))
            }
        }
        .frame(width: 48, height: 48)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
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

    static func fetch(_ url: URL) async -> UIImage? {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 8
        let session = URLSession(configuration: config, delegate: WebsiteIconRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  response.expectedContentLength <= maximumBytes else { return nil }
            var data = Data()
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else { return nil }
                data.append(byte)
            }
            try Task.checkCancellation()
            return decode(data)
        } catch { return nil }
    }
}

/// Favicon hosts can redirect to a CDN (for example Gmail); never follow credentials or a downgrade.
private final class WebsiteIconRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var redirects = 0 // URLSession's delegate queue is serial.
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        redirects += 1
        completionHandler(redirects <= 3 && WebsiteIconLoader.redirectAllowed(request.url) ? request : nil)
    }
}
