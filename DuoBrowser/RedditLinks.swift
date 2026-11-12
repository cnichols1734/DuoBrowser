import Foundation

enum RedditLinkPreference: String, CaseIterable {
    case chooseOnce, askEveryTime, browser, apollo

    var title: String {
        switch self {
        case .chooseOnce: return "Ask Once"
        case .askEveryTime: return "Ask Every Time"
        case .browser: return "DuoBrowser"
        case .apollo: return "Apollo Reborn"
        }
    }
}

/// Local, bounded URL parsing only. Never resolves links using an extra network request.
enum RedditLinks {
    private static let redditHosts: Set<String> = ["reddit.com", "www.reddit.com", "old.reddit.com",
                                                   "new.reddit.com", "np.reddit.com", "m.reddit.com", "redd.it"]
    private static let googleDomains: Set<String> = ["google.com", "google.co.uk", "google.ca", "google.com.au",
                                                     "google.de", "google.fr", "google.co.in", "google.co.jp"]

    static func destination(_ url: URL) -> URL? {
        guard let parts = webComponents(url), let host = parts.host?.lowercased() else { return nil }
        if redditHosts.contains(host) { return isContent(parts) ? url : nil }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        guard googleDomains.contains(domain), parts.path == "/url" else { return nil }
        let targets = (parts.queryItems ?? []).filter { ["url", "q"].contains($0.name) }
        guard targets.count == 1, let value = targets.first?.value, let target = URL(string: value),
              let targetParts = webComponents(target), let targetHost = targetParts.host?.lowercased(),
              redditHosts.contains(targetHost), isContent(targetParts) else { return nil }
        return target
    }

    static func apolloURL(_ url: URL) -> URL? {
        guard let destination = destination(url), var parts = webComponents(destination) else { return nil }
        parts.scheme = "apollo"
        parts.host = parts.host?.lowercased() == "redd.it" ? "redd.it" : "reddit.com"
        parts.port = nil
        return parts.url
    }

    static func eligible(isLink: Bool, sourceIsMainFrame: Bool, targetIsMainFrame: Bool?, method: String?, download: Bool) -> Bool {
        isLink && sourceIsMainFrame && targetIsMainFrame != false && (method ?? "GET") == "GET" && !download
    }

    private static func isContent(_ parts: URLComponents) -> Bool {
        // Authentication/account-management links remain in their original web session.
        if parts.host?.lowercased() == "redd.it" {
            return parts.path.range(of: #"^/[A-Za-z0-9]+/?$"#, options: .regularExpression) != nil
        }
        if parts.path.isEmpty { return true }
        return parts.path.range(of: #"^/(?:$|r/[A-Za-z0-9_+.-]+/?$|r/[A-Za-z0-9_+.-]+/(?:comments|wiki|s)/.+|(?:u|user)/[A-Za-z0-9_-]+(?:/.*)?|(?:comments|gallery|s)/.+|search/?)$"#,
                                options: .regularExpression) != nil
    }

    private static func webComponents(_ url: URL) -> URLComponents? {
        guard url.absoluteString.utf8.count <= 8192,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil,
              parts.port == nil || (parts.scheme?.lowercased() == "https" ? parts.port == 443 : parts.port == 80),
              !parts.percentEncodedPath.lowercased().contains("%00") else { return nil }
        return parts
    }
}
