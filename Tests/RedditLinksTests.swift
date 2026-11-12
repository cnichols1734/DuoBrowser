import Foundation

@main
enum RedditLinksTests {
    static func main() {
        var count = 0
        func check(_ value: Bool, _ name: String) {
            precondition(value, name)
            count += 1
        }
        func apollo(_ value: String) -> String? { URL(string: value).flatMap(RedditLinks.apolloURL)?.absoluteString }
        let path = "/r/swift/comments/abc123/a_title/def456/?context=3#comment"
        for host in ["reddit.com", "www.reddit.com", "old.reddit.com", "new.reddit.com", "np.reddit.com", "m.reddit.com"] {
            check(apollo("https://" + host + path) == "apollo://reddit.com" + path, "preserves post/comment/query/fragment: " + host)
        }
        for path in ["/r/swift/", "/user/example/", "/gallery/abc123", "/r/swift/s/opaque", "/r/swift/wiki/index", "/"] {
            check(apollo("https://www.reddit.com" + path) == "apollo://reddit.com" + path, "preserves supported destination: " + path)
        }
        check(apollo("https://redd.it/abc123") == "apollo://redd.it/abc123", "short links")
        check(apollo("https://reddit.com") == "apollo://reddit.com", "bare root")
        check(apollo("https://WWW.REDDIT.COM:443/r/swift/") == "apollo://reddit.com/r/swift/", "case and default port")
        check(apollo("https://www.google.com/url?q=https%3A%2F%2Fwww.reddit.com%2Fr%2Fswift%2F&sa=U") == "apollo://reddit.com/r/swift/", "Google result wrapper")
        check(apollo("https://www.google.co.uk/url?url=https%3A%2F%2Fredd.it%2Fabc123") == "apollo://redd.it/abc123", "regional Google wrapper")
        for value in ["https://reddit.com.evil.test/r/swift", "https://reddit.com@evil.test/r/swift", "https://user@reddit.com/r/swift",
                      "https://www.reddit.com:8443/r/swift", "https://i.redd.it/photo.png", "https://v.redd.it/video", "apollo://reddit.com/r/swift",
                      "file:///reddit.com", "javascript:alert(1)", "https://www.google.com.evil.test/url?q=https://reddit.com/r/swift",
                      "https://www.google.com/search?q=https://reddit.com/r/swift", "https://www.google.com/url?q=https://evil.test/",
                      "https://www.google.com/url?q=https://reddit.com/r/swift&url=https://evil.test", "https://www.google.com/url?q=javascript:alert(1)",
                      "https://www.google.com/url?q=https%253A%252F%252Freddit.com", "https://reddit.com/%00", "https://reddit.com/login",
                      "https://reddit.com/api/v1/authorize?client_id=example", "https://reddit.com/settings", "https://reddit.com/" + String(repeating: "x", count: 8200)] {
            check(apollo(value) == nil, "rejects unsafe or unsupported destination: " + String(value.prefix(120)))
        }
        check(RedditLinks.eligible(isLink: true, sourceIsMainFrame: true, targetIsMainFrame: true, method: "GET", download: false), "main-frame tap")
        check(RedditLinks.eligible(isLink: true, sourceIsMainFrame: true, targetIsMainFrame: nil, method: "GET", download: false), "new-window tap")
        for value in [RedditLinks.eligible(isLink: false, sourceIsMainFrame: true, targetIsMainFrame: true, method: "GET", download: false),
                      RedditLinks.eligible(isLink: true, sourceIsMainFrame: false, targetIsMainFrame: true, method: "GET", download: false),
                      RedditLinks.eligible(isLink: true, sourceIsMainFrame: true, targetIsMainFrame: false, method: "GET", download: false),
                      RedditLinks.eligible(isLink: true, sourceIsMainFrame: true, targetIsMainFrame: true, method: "POST", download: false),
                      RedditLinks.eligible(isLink: true, sourceIsMainFrame: true, targetIsMainFrame: true, method: "GET", download: true)] {
            check(!value, "does not hand off redirects, frames, forms, or downloads")
        }
        print("\(count) Reddit link policy checks passed")
    }
}
