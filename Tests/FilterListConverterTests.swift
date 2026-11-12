import Foundation

@main struct FilterListConverterTests {
    static func main() throws {
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) {
            guard condition() else { fatalError(label) }; checks += 1
        }
        let rules = try FilterListConverter.convert("""
        [Adblock Plus 2.0]
        ||ads.example^$third-party,script
        @@||ads.example/needed.js$script
        /tracker.gif$image,domain=example.com
        ||unsupported.example^$redirect=noopjs
        ||mixed.example^$domain=example.com|~login.example.com
        ||disabled.example^
        ||disabled.example^$badfilter
        ##.advert
        example.com#@#.advert
        example.com##.sponsor
        example.com#@#.sponsor
        ##.danger:style(display:none)
        @@||consent.example^$elemhide
        """)
        check(rules.network.count == 2, "only exactly supported network conditions compile")
        check(rules.exceptions.count == 1, "network exception retained")
        check(rules.cosmetic.count == 1, "selector exclusions cannot become global hiding")
        check(rules.cosmeticExceptions.count == 1, "element-hiding exception isolated from network rules")
        let trigger = rules.network[0]["trigger"] as! [String: Any]
        check(trigger["load-type"] as? [String] == ["third-party"], "third-party restriction preserved")
        check(trigger["resource-type"] as? [String] == ["script"], "resource restriction preserved")
        let cosmetic = rules.cosmetic[0]["trigger"] as! [String: Any]
        check(cosmetic["unless-domain"] as? [String] == ["*example.com"], "cosmetic domain exception retained")
        let chunks = try rules.chunks(limit: 2)
        check(chunks.count == 3, "bounded chunks split network and cosmetic rules")
        for data in chunks {
            let array = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
            check(array.count <= 2, "chunk honors bound")
            check((array.last?["action"] as? [String: String])?["type"] == "ignore-previous-rules", "exceptions replicated after blocks in each chunk")
        }
        let regex = FilterListConverter.urlFilter("||ads.example^")!
        let expression = try NSRegularExpression(pattern: regex)
        func matches(_ url: String) -> Bool { expression.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil }
        check(matches("https://ads.example/x"), "root domain matches")
        check(matches("https://sub.ads.example/x"), "subdomain matches")
        check(!matches("https://notads.example/x"), "sibling domain does not match")
        check(!matches("https://ads.example.evil/x"), "host suffix attack does not match")
        check(FilterListConverter.urlFilter("/look(?=ahead)/") == nil, "untranslated regex rejected")
        check(FilterListConverter.urlFilter("*") == nil, "blanket wildcard rejected")
        let negative = try FilterListConverter.convert("[Adblock Plus 2.0]\n||ads.example^$~image\n")
        check(!((negative.network[0]["trigger"] as! [String: Any])["resource-type"] as! [String]).contains("image"), "negative resource type preserved")
        let blank = try FilterListConverter.convert("[Adblock Plus 2.0]\n##.ad\n@@$generichide,domain=example.com")
        check(blank.cosmeticExceptions.count == 1, "empty-pattern scoped cosmetic exception retained")
        let first = "[Adblock Plus 2.0]\n||ad.example^$script\n##.ad"
        let second = "[Adblock Plus 2.0]\n@@||ad.example^$script\nexample.com#@#.ad"
        let combined = try FilterListConverter.convert(first + "\n" + second, combined: true)
        check(combined.exceptions.count == 1, "exceptions cross enabled source boundaries")
        check((combined.cosmetic[0]["trigger"] as! [String: Any])["unless-domain"] as? [String] == ["*example.com"], "selector exceptions cross source boundaries")
        let typed = try FilterListConverter.convert("[Adblock Plus 2.0]\n||a.example^$subdocument\n||b.example^$other\n||c.example^$xmlhttprequest")
        let types = typed.network.map { ($0["trigger"] as! [String: Any])["resource-type"] as! [String] }
        check(types == [["child-document"], ["other"], ["fetch"]], "resource types never widen to raw or top-level documents")
        let document = try FilterListConverter.convert("[Adblock Plus 2.0]\n||ads.example^\n@@||trusted.example^$document")
        let exemption = document.exceptions[0]["trigger"] as! [String: Any]
        check(exemption["url-filter"] as? String == ".*" && exemption["if-top-url"] != nil, "document exception scopes all resources to the permitted top page")
        let badfilter = try FilterListConverter.convert("""
        [Adblock Plus 2.0]
        ||example.com/badfilter.js
        ||example.com/path?badfilter=yes
        ||example.com/first$script
        ||example.com/first$badfilter,script
        ||example.com/middle$script,image
        ||example.com/middle$script,badfilter,image
        ||example.com/last$image
        ||example.com/last$image,badfilter
        """)
        check(badfilter.network.count == 2, "only actual badfilter options disable their corresponding rules")
        check((badfilter.network[0]["trigger"] as! [String: Any])["url-filter"] as? String == FilterListConverter.urlFilter("||example.com/badfilter.js"), "badfilter substring in URL remains an ordinary blocking rule")
        let frame = rules.network[1]["trigger"] as! [String: Any]
        check(frame["if-domain"] == nil && frame["if-frame-url"] as? [String] == [FilterListConverter.urlFilter("||example.com^")!], "network domain restriction matches requesting frame instead of top page")
        let excludedFrame = try FilterListConverter.convert("[Adblock Plus 2.0]\n||ads.example^$domain=~example.com")
        check((excludedFrame.network[0]["trigger"] as! [String: Any])["unless-frame-url"] as? [String] == [FilterListConverter.urlFilter("||example.com^")!], "negative network domain restriction remains frame-scoped")
        let split = try FilterListConverter.convert("[Adblock Plus 2.0]\n||jokerly.com^$subdocument\n@@||jokerly.com^$document,subdocument")
        check(split.exceptions.count == 2 && split.cosmeticExceptions.count == 1, "document plus subdocument emits separate allowlist alternatives")
        let frameException = split.exceptions[1]["trigger"] as! [String: Any]
        check(frameException["url-filter"] as? String == FilterListConverter.urlFilter("||jokerly.com^") && frameException["if-top-url"] == nil && frameException["resource-type"] as? [String] == ["child-document"], "subdocument exception retains original resource URL without top-page restriction")
        let scopedDocument = try FilterListConverter.convert("[Adblock Plus 2.0]\n||jokerly.com^\n@@||jokerly.com^$document,subdocument,domain=example.com")
        check(scopedDocument.exceptions.count == 1 && scopedDocument.cosmeticExceptions.isEmpty && scopedDocument.skipped == 1, "unrepresentable domain-scoped document allowlist is skipped without discarding subdocument alternative")
        let scopedTrigger = scopedDocument.exceptions[0]["trigger"] as! [String: Any]
        check(scopedTrigger["if-frame-url"] != nil && scopedTrigger["if-top-url"] == nil, "remaining scoped alternative keeps only the exact requesting-frame condition")
        check(matches("ws://ads.example/socket"), "domain anchor matches websocket scheme")
        check(matches("wss://sub.ads.example/socket"), "domain anchor matches secure websocket subdomain")
        check(!matches("wss://notads.example/socket") && !matches("wss://ads.example.evil/socket"), "websocket matching preserves hostname boundaries")
        let sockets = try FilterListConverter.convert("[Adblock Plus 2.0]\n||ads.example^$websocket\n@@||ads.example/allowed$websocket")
        check((sockets.network[0]["trigger"] as! [String: Any])["resource-type"] as? [String] == ["websocket"] && (sockets.exceptions[0]["trigger"] as! [String: Any])["resource-type"] as? [String] == ["websocket"], "websocket block and exception preserve their resource type")
        for source in ["<html>error</html>", "[Adblock Plus 2.0]\n! empty", "[Adblock Plus 2.0]\n" + String(repeating: "x", count: 5_000_001)] {
            do { _ = try FilterListConverter.convert(source); fatalError("invalid source accepted") }
            catch { checks += 1 }
        }
        print("\(checks) filter conversion checks passed")
    }
}
