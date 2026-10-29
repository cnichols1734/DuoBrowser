import WebKit

/// Small, auditable bundled baseline. No remote lists, request logging, or browsing-derived rules.
@MainActor
enum ContentBlocking {
    private static var compilation: Task<WKContentRuleList?, Never>?
    #if DEBUG
    private static var testRules: String?
    static func useTestRules(_ json: String?) { testRules = json; compilation = nil }
    #endif
    static func rules() async -> WKContentRuleList? {
        if let compilation { return await compilation.value }
        let task = Task<WKContentRuleList?, Never> { @MainActor in
            guard let url = Bundle.main.url(forResource: "BlockingRules", withExtension: "json"),
                  let json = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            #if DEBUG
            let source = testRules ?? json
            let identifier = testRules == nil ? "DuoBrowser.Basic.v1" : "DuoBrowser.Synthetic.v1"
            #else
            let source = json
            let identifier = "DuoBrowser.Basic.v1"
            #endif
            return try? await WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: identifier, encodedContentRuleList: source)
        }
        compilation = task
        return await task.value
    }
}
