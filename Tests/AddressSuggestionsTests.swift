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
        check(eligible("pat"), "plain query")
        check(eligible("日本"), "unicode query")
        for value in ["g", "https://example.com/token", "example.com", "user@example.com", "localhost", "/Users/name", "a?token=secret", "12345", "line\nbreak", String(repeating: "a", count: 101)] {
            check(!eligible(value), "Private or invalid query excluded")
        }
        check(!eligible("pat", privateMode: true), "Private requests disabled")
        check(!eligible("pat", enabled: false), "Preference respected")
        check(!eligible("pat", composing: true), "Composition not transmitted")
        let response = Data(#"["pat",["pat", "patriots schedule", "PATRIOTS SCHEDULE", "patagonia", "bad\ntext"]]"#.utf8)
        check(AddressSuggestions.decode(response, query: "pat") == ["patriots schedule", "patagonia"], "Validate and deduplicate")
        check(AddressSuggestions.decode(response, query: "apple").isEmpty, "Stale response excluded")
        check(AddressSuggestions.decode(Data("{}".utf8), query: "pat").isEmpty, "Malformed response")
        check(AddressSuggestions.decode(Data(repeating: 32, count: 32769), query: "pat").isEmpty, "Bounded response")
        let search = AddressSuggestions.searchURL("example.com & news")
        check(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "example.com & news", "Prediction always searches, safely encoded")
        print("Address suggestions: \(checks) checks passed")
    }
}
