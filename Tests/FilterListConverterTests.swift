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
        for source in ["<html>error</html>", "[Adblock Plus 2.0]\n! empty", "[Adblock Plus 2.0]\n" + String(repeating: "x", count: 5_000_001)] {
            do { _ = try FilterListConverter.convert(source); fatalError("invalid source accepted") }
            catch { checks += 1 }
        }
        print("\(checks) filter conversion checks passed")
    }
}
