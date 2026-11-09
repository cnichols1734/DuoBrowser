import Foundation

@main
struct AddressSuggestionsTests {
    static func main() {
        var checks = 0
        func check(_ condition: Bool, _ message: String) {
            precondition(condition, message); checks += 1
        }
        for (input, host) in [("g", "google.com"), ("GO", "google.com"), ("a", "apple.com"),
                              ("AP", "apple.com"), ("pat", "patriots.com"), ("https://www.ap", "apple.com")] {
            check(AddressSuggestions.websites(for: input).first?.address == "https://" + host, input)
        }
        for value in ["", " ", "apple.com/login", "patriots schedule", "unknowninvalid"] {
            check(AddressSuggestions.websites(for: value).isEmpty, "No spurious destination: " + value)
        }
        func eligible(_ text: String, privateMode: Bool = false, enabled: Bool = true, composing: Bool = false) -> Bool {
            AddressSuggestions.remoteQuery(text, isPrivate: privateMode, enabled: enabled, composing: composing) != nil
        }
        check(eligible("g"), "single-letter keyword predictions")
        check(eligible("pat"), "plain query")
        check(eligible("日本"), "unicode query")
        for value in ["https://example.com/token", "example.com", "user@example.com", "localhost", "/Users/name", "a?token=secret", "12345", "line\nbreak", String(repeating: "a", count: 101)] {
            check(!eligible(value), "Private or invalid query excluded")
        }
        check(!eligible("pat", privateMode: true), "Private requests disabled")
        check(!eligible("pat", enabled: false), "Preference respected")
        check(!eligible("pat", composing: true), "Composition not transmitted")
        check(AddressSuggestions.inlineCompletion("G")?.text == "www.google.com", "Case-insensitive inline Google completion")
        check(AddressSuggestions.inlineCompletion("go")?.selectionStart == 6, "Completion selects only the remaining suffix")
        check(AddressSuggestions.inlineCompletion("www.ap")?.text == "www.apple.com", "Typed www prefix is retained once")
        check(AddressSuggestions.inlineCompletion("maps")?.text == "maps.google.com", "Subdomain completion does not invent www host")
        for value in ["google news", "google.com", "example.invalid", "https://google.com/path", ""] {
            check(AddressSuggestions.inlineCompletion(value) == nil, "No intrusive completion for queries or complete addresses")
        }
        let response = Data(#"["pat",["pat", "patriots schedule", "PATRIOTS SCHEDULE", "patagonia", "bad\ntext"]]"#.utf8)
        check(AddressSuggestions.decode(response, query: "pat") == ["patriots schedule", "patagonia"], "Validate and deduplicate")
        check(AddressSuggestions.decode(response, query: "apple").isEmpty, "Stale response excluded")
        check(AddressSuggestions.decode(Data("{}".utf8), query: "pat").isEmpty, "Malformed response")
        check(AddressSuggestions.decode(Data(repeating: 32, count: 32769), query: "pat").isEmpty, "Bounded response")
        let search = AddressSuggestions.searchURL("example.com & news")
        check(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "example.com & news", "Prediction always searches, safely encoded")
        check(search.host == "www.google.com" && search.path == "/search", "Predictions use Google search")
        check(WebAddress.resolve("example query") == AddressSuggestions.searchURL("example query"), "Typed and predicted searches share the provider")
        let unicode = "café + tea & 日本?"
        let queryItems = URLComponents(url: WebAddress.searchURL(unicode), resolvingAgainstBaseURL: false)?.queryItems
        check(queryItems == [URLQueryItem(name: "q", value: unicode)], "Unicode and punctuation remain one search term")
        check(WebAddress.searchURL(unicode).absoluteString.contains("%2B"), "Literal plus is not interpreted as a space by Google")
        let request = SearchSuggestionClient.requestURL("日本")
        let requestParts = URLComponents(url: request, resolvingAgainstBaseURL: false)!
        check(request.scheme == "https" && request.host == "www.google.com" && request.path == "/complete/search", "Predictions contact only Google")
        check(requestParts.queryItems?.first(where: { $0.name == "q" })?.value == "日本", "Prediction request preserves unicode")
        check(AddressSuggestions.decode(Data(#"["日本",["日本 天気"],[],{"google:suggesttype":["QUERY"]}]"#.utf8), query: "日本") == ["日本 天気"], "Google response metadata does not alter suggestions")
        let firstTab = SearchResult(id: "one", title: "Apple", address: "https://apple.com/", kind: .tab, tabID: UUID())
        let secondTab = SearchResult(id: "two", title: "Apple", address: "https://apple.com/", kind: .tab, tabID: UUID(), detail: "Work")
        let bookmark = SearchResult(id: "bookmark", title: "Apple", address: "https://apple.com/#top", kind: .bookmark)
        let merged = AddressSuggestions.results("ap", local: [firstTab, secondTab, bookmark])
        check(merged.map(\.id) == ["one", "two"], "Keep distinct tab identities; suppress promoted tab and bookmark duplicates")
        let blank = SearchResult(id: "blank", title: "Start Page", address: "", kind: .tab, tabID: UUID())
        check(AddressSuggestions.results("Start Page", local: [blank]).first?.tabID == blank.tabID, "Blank tabs remain valid switch targets")
        print("Address suggestions: \(checks) checks passed")
    }
}
