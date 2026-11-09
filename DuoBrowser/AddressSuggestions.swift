import Foundation

/// Bundled destinations work on the first launch and offline. This is a curated list, not live popularity data.
enum AddressSuggestions {
    static let websites: [(String, String)] = [
        ("Google", "google.com"), ("Apple", "apple.com"), ("Amazon", "amazon.com"),
        ("YouTube", "youtube.com"), ("Wikipedia", "wikipedia.org"), ("Reddit", "reddit.com"),
        ("Facebook", "facebook.com"), ("Instagram", "instagram.com"), ("Netflix", "netflix.com"),
        ("Gmail", "gmail.com"), ("Google Maps", "maps.google.com"), ("Microsoft", "microsoft.com"),
        ("GitHub", "github.com"), ("Yahoo", "yahoo.com"),
        ("Bing", "bing.com"), ("eBay", "ebay.com"), ("Walmart", "walmart.com"),
        ("Target", "target.com"), ("ESPN", "espn.com"), ("New England Patriots", "patriots.com"),
        ("Patagonia", "patagonia.com"), ("Patreon", "patreon.com"), ("Pinterest", "pinterest.com"),
        ("PayPal", "paypal.com"), ("Spotify", "spotify.com"), ("Twitch", "twitch.tv"),
        ("TikTok", "tiktok.com"), ("LinkedIn", "linkedin.com"), ("OpenAI", "openai.com"),
        ("ChatGPT", "chatgpt.com"), ("BBC", "bbc.com"), ("CNN", "cnn.com")
    ]

    static func websites(for input: String) -> [SearchResult] {
        var prefix = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for scheme in ["https://", "http://"] where prefix.hasPrefix(scheme) { prefix.removeFirst(scheme.count) }
        if prefix.hasPrefix("www.") { prefix.removeFirst(4) }
        guard !prefix.isEmpty else { return [] }
        return websites.filter { $0.1.hasPrefix(prefix) || $0.0.lowercased().hasPrefix(prefix) }.prefix(3).map {
            SearchResult(id: "website:" + $0.1, title: $0.0, address: "https://" + $0.1, kind: .website)
        }
    }

    /// Complete only a known domain prefix, keeping the typed keyword separate for predictions.
    static func inlineCompletion(_ input: String) -> (text: String, selectionStart: Int)? {
        let lower = input.lowercased()
        guard !lower.isEmpty, !lower.contains(where: \.isWhitespace) else { return nil }
        let prefix = lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
        guard !prefix.isEmpty, let host = websites.first(where: { $0.1.hasPrefix(prefix) })?.1,
              prefix.count < host.count else { return nil }
        let addedPrefix = host.split(separator: ".").count == 2 ? "www." : ""
        guard !lower.hasPrefix("www.") || !addedPrefix.isEmpty else { return nil }
        let display = addedPrefix + host
        return (display, addedPrefix.utf16.count + prefix.utf16.count)
    }

    static func results(_ query: String, local: [SearchResult]) -> [SearchResult] {
        let popular = websites(for: query).map { website in
            local.first { $0.kind == .tab && URL(string: $0.address)?.host == URL(string: website.address)?.host &&
                ["", "/"].contains(URL(string: $0.address)?.path ?? "") && URL(string: $0.address)?.query == nil } ?? website
        }
        var destinations = Set<String>()
        var tabIDs = Set<String>()
        return (popular + local).filter { result in
            var url = URLComponents(string: result.address)
            url?.fragment = nil
            if url?.path == "/" { url?.path = "" }
            let key = url?.string ?? result.address
            if result.kind == .tab {
                // Two tabs at the same address can have different forms, navigation and workspaces.
                destinations.insert(key)
                return tabIDs.insert(result.id).inserted
            }
            return destinations.insert(key).inserted
        }
    }

    /// Only plain search terms go to the provider; never URLs, email, paths, or likely pasted tokens.
    static func remoteQuery(_ input: String, isPrivate: Bool, enabled: Bool, composing: Bool) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard enabled, !isPrivate, !composing, (1...100).contains(value.count),
              value.unicodeScalars.allSatisfy({ CharacterSet.letters.union(.decimalDigits)
                .union(CharacterSet(charactersIn: " '-")).contains($0) }),
              !value.lowercased().hasPrefix("localhost"),
              !value.split(separator: " ").contains(where: { $0.count > 30 }),
              value.rangeOfCharacter(from: .letters) != nil else { return nil }
        return value
    }

    static func decode(_ data: Data, query: String) -> [String] {
        guard data.count <= 32_768,
              let root = try? JSONSerialization.jsonObject(with: data) as? [Any], root.count >= 2,
              let echoed = root[0] as? String, echoed == query,
              let phrases = root[1] as? [String] else { return [] }
        var seen = Set([query.lowercased()])
        return Array(phrases.prefix(20).filter {
            !$0.isEmpty && $0.count <= 100 && $0 == $0.trimmingCharacters(in: .whitespacesAndNewlines) &&
            !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
            seen.insert($0.lowercased()).inserted
        }.prefix(5))
    }

    static func searchURL(_ phrase: String) -> URL {
        WebAddress.searchURL(phrase)
    }
}

/// No shared cookies, persistent cache, credentials, redirects or page context.
final class SearchSuggestionClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    static func requestURL(_ query: String) -> URL {
        var url = URLComponents(string: "https://www.google.com/complete/search")!
        url.queryItems = [URLQueryItem(name: "output", value: "chrome"), URLQueryItem(name: "q", value: query),
                          URLQueryItem(name: "ie", value: "UTF-8"), URLQueryItem(name: "oe", value: "UTF-8")]
        return url.url!
    }

    func fetch(_ query: String) async throws -> [String] {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 4
        configuration.timeoutIntervalForResource = 5
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: Self.requestURL(query))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return [] }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 32_768 else { return [] }
            data.append(byte)
        }
        return AddressSuggestions.decode(data, query: query)
    }
}
