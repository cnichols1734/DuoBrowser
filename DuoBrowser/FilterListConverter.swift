import Foundation

/// Declarative-only subset of ABP syntax. Unsupported blocking conditions are skipped, never widened.
/// Filter data retains its upstream license; this converter is project-owned MIT code.
enum FilterListConverter {
    struct Result {
        let network: [[String: Any]]
        let cosmetic: [[String: Any]]
        let exceptions: [[String: Any]]
        let cosmeticExceptions: [[String: Any]]
        let skipped: Int
        var count: Int { network.count + cosmetic.count + exceptions.count + cosmeticExceptions.count }
        func chunks(limit: Int = 20_000) throws -> [Data] {
            var output: [Data] = []
            for (rules, exemptions) in [(network, exceptions), (cosmetic, cosmeticExceptions)] {
                guard exemptions.count < limit else { throw Failure.tooLarge }
                let size = limit - exemptions.count
                for start in stride(from: 0, to: rules.count, by: size) {
                    output.append(try JSONSerialization.data(withJSONObject: Array(rules[start..<min(start + size, rules.count)]) + exemptions, options: [.sortedKeys]))
                }
            }
            return output
        }
    }
    enum Failure: Error { case invalidList, tooLarge }
    private static let resources = ["script", "image", "style-sheet", "font", "media", "fetch", "other", "svg-document", "ping", "websocket", "popup", "child-document"]
    private static let resourceMap = ["script": "script", "image": "image", "stylesheet": "style-sheet", "font": "font", "media": "media", "xmlhttprequest": "fetch", "other": "other", "ping": "ping", "websocket": "websocket", "subdocument": "child-document", "document": "top-document", "popup": "popup"]

    static func convert(_ text: String, combined: Bool = false) throws -> Result {
        guard text.utf8.count <= (combined ? 15_000_000 : 5_000_000), text.hasPrefix("[Adblock Plus"), !text.contains("\u{0}") else { throw Failure.invalidList }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count <= (combined ? 450_000 : 150_000) else { throw Failure.tooLarge }
        var disabled = Set<String>()
        for line in lines {
            if let target = badfilterTarget(line) { disabled.insert(target) }
        }
        var network: [[String: Any]] = [], cosmetic: [[String: Any]] = []
        var exceptions: [[String: Any]] = [], cosmeticExceptions: [[String: Any]] = []
        var excludedSelectors: [String: Set<String>] = [:]
        var skipped = 0
        // Selector exceptions must be applied before generating any hide rule.
        for line in lines {
            if let range = line.range(of: "#@#") {
                let selector = String(line[range.upperBound...])
                let scope = String(line[..<range.lowerBound])
                if scope.isEmpty { excludedSelectors[selector, default: []].insert("*") }
                else {
                    let domains = scope.split(separator: ",").map(String.init)
                    if domains.allSatisfy(validDomain) { excludedSelectors[selector, default: []].formUnion(domains) }
                    else { excludedSelectors[selector, default: []].insert("*") }
                }
            }
        }
        for line in lines {
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") || disabled.contains(line) || line.contains("#@#") { continue }
            guard line.utf8.count < 8192 else { skipped += 1; continue }
            if let range = line.range(of: "##") {
                let selector = String(line[range.upperBound...])
                let scope = String(line[..<range.lowerBound])
                guard !selector.contains(":style("), !selector.contains("+js("), !selector.contains(":has-text("), !selector.contains(":remove("), !selector.contains("-abp-"), !selector.contains("{"), !selector.contains("}"), !selector.contains("\\"), selector.utf8.count <= 2048 else { skipped += 1; continue }
                let omitted = excludedSelectors[selector] ?? []
                if omitted.contains("*") { continue }
                guard var trigger = domainTrigger(scope, separator: ",", extraExcluded: omitted) else { skipped += 1; continue }
                trigger["url-filter"] = ".*"
                cosmetic.append(["trigger": trigger, "action": ["type": "css-display-none", "selector": selector]])
                continue
            }
            if line.contains("#?#") || line.contains("#$#") || line.contains("#%#") || line.contains("#@") { skipped += 1; continue }
            let isException = line.hasPrefix("@@")
            let input = isException ? String(line.dropFirst(2)) : line
            let pieces = input.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
            guard let pattern = pieces.first else { skipped += 1; continue }
            let patternString = String(pattern)
            guard let regex = (isException && patternString.isEmpty ? ".*" : urlFilter(patternString)) else { skipped += 1; continue }
            let options = pieces.count == 2 ? pieces[1].split(separator: ",").map(String.init) : []
            var trigger: [String: Any] = ["url-filter": regex]
            var included = Set<String>(), excluded = Set<String>()
            var valid = true, cosmeticOnly = false, allResources = false
            var domainScope: String?
            for option in options {
                if option == "third-party" || option == "3p" { trigger["load-type"] = ["third-party"] }
                else if option == "~third-party" || option == "first-party" || option == "1p" { trigger["load-type"] = ["first-party"] }
                else if option == "match-case" { trigger["url-filter-is-case-sensitive"] = true }
                else if option.hasPrefix("domain=") {
                    domainScope = String(option.dropFirst(7))
                    if domainScope?.isEmpty != false { valid = false }
                } else if let type = resourceMap[option] { included.insert(type); if option == "document" { allResources = isException } }
                else if option.hasPrefix("~"), let type = resourceMap[String(option.dropFirst())] { excluded.insert(type) }
                else if isException && ["elemhide", "generichide", "specifichide"].contains(option) { cosmeticOnly = true }
                else if isException && ["genericblock", "important"].contains(option) { /* Conservative allow. */ }
                else { valid = false }
            }
            if let domainScope {
                let domains = cosmeticOnly ? domainTrigger(domainScope, separator: "|") : frameDomainTrigger(domainScope)
                if let domains { trigger.merge(domains) { _, new in new } } else { valid = false }
            }
            if patternString.isEmpty && domainScope == nil { valid = false }
            guard valid else { skipped += 1; continue }
            let types = (included.isEmpty ? Set(resources) : included).subtracting(excluded)
            guard !types.isEmpty else { skipped += 1; continue }
            if allResources, types.contains("top-document") {
                // A document exception and a URL-scoped subresource exception are alternatives.
                // WebKit supports only one URL condition per rule, so a requesting-domain condition
                // cannot also constrain the document-wide top-URL allowlist. Skip that component.
                if domainScope == nil {
                    var documentTrigger = trigger
                    documentTrigger["if-top-url"] = [regex]
                    documentTrigger["url-filter"] = ".*"
                    let documentRule: [String: Any] = ["trigger": documentTrigger, "action": ["type": "ignore-previous-rules"]]
                    exceptions.append(documentRule); cosmeticExceptions.append(documentRule)
                } else { skipped += 1 }
                let remaining = types.subtracting(["top-document"])
                if !remaining.isEmpty {
                    trigger["resource-type"] = remaining.sorted()
                    exceptions.append(["trigger": trigger, "action": ["type": "ignore-previous-rules"]])
                }
                continue
            }
            if !cosmeticOnly { trigger["resource-type"] = types.sorted() }
            let rule: [String: Any] = ["trigger": trigger, "action": ["type": isException ? "ignore-previous-rules" : "block"]]
            if isException {
                if cosmeticOnly { cosmeticExceptions.append(rule) }
                else { exceptions.append(rule) }
            } else { network.append(rule) }
        }
        guard !network.isEmpty || !cosmetic.isEmpty else { throw Failure.invalidList }
        return Result(network: network, cosmetic: cosmetic, exceptions: exceptions, cosmeticExceptions: cosmeticExceptions, skipped: skipped)
    }

    private static func badfilterTarget(_ line: String) -> String? {
        guard !line.hasPrefix("!"), !line.hasPrefix("["), !line.contains("##"), !line.contains("#@#"),
              let separator = line.firstIndex(of: "$") else { return nil }
        let options = line[line.index(after: separator)...].split(separator: ",").map(String.init)
        guard options.contains("badfilter") else { return nil }
        let remaining = options.filter { $0 != "badfilter" }
        return String(line[..<separator]) + (remaining.isEmpty ? "" : "$" + remaining.joined(separator: ","))
    }
    private static func frameDomainTrigger(_ scope: String) -> [String: Any]? {
        guard let domains = domainTrigger(scope, separator: "|") else { return nil }
        // Apple's frame-URL conditions use the initiating document, unlike top-page if-domain.
        // Reuse the same escaped hostname boundary, including subdomains and explicit ports.
        if let included = domains["if-domain"] as? [String] {
            return ["if-frame-url": included.compactMap { urlFilter("||" + $0.dropFirst() + "^") }]
        }
        if let excluded = domains["unless-domain"] as? [String] {
            return ["unless-frame-url": excluded.compactMap { urlFilter("||" + $0.dropFirst() + "^") }]
        }
        return nil
    }

    private static func validDomain(_ domain: String) -> Bool {
        !domain.isEmpty && domain.utf8.count <= 253 && domain.utf8.allSatisfy { (97...122).contains($0) || (65...90).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 46 } && !domain.hasPrefix(".") && !domain.hasSuffix(".") && !domain.contains("..")
    }
    private static func domainTrigger(_ scope: String, separator: Character, extraExcluded: Set<String> = []) -> [String: Any]? {
        var included: [String] = [], excluded = Array(extraExcluded)
        for entry in scope.split(separator: separator) {
            let negated = entry.hasPrefix("~")
            let domain = String(negated ? entry.dropFirst() : entry[...])
            guard validDomain(domain) else { return nil }
            if negated { excluded.append(domain) } else { included.append(domain) }
        }
        // WebKit cannot combine if-domain and unless-domain. Do not discard exclusions.
        if !included.isEmpty && !excluded.isEmpty { return nil }
        if !included.isEmpty { return ["if-domain": included.map { "*" + $0.lowercased() }.sorted()] }
        if !excluded.isEmpty { return ["unless-domain": excluded.map { "*" + $0.lowercased() }.sorted()] }
        return [:]
    }
    static func urlFilter(_ value: String) -> String? {
        guard !value.isEmpty, value.utf8.count <= 2048, value.utf8.allSatisfy({ $0 >= 32 && $0 < 127 }) else { return nil }
        // Explicit regex rules require a separate audited WebKit-regex translator.
        if value.hasPrefix("/") && value.hasSuffix("/") && value.count > 1 { return nil }
        var pattern = value[...], result = ""
        if pattern.hasPrefix("||") { result = "^[a-z][a-z0-9+.-]*://([^/]+\\.)?"; pattern = pattern.dropFirst(2) }
        else if pattern.hasPrefix("|") { result = "^"; pattern = pattern.dropFirst() }
        let end = pattern.hasSuffix("|")
        if end { pattern = pattern.dropLast() }
        for character in pattern {
            switch character {
            case "*": result += ".*"
            case "^": result += "[^a-zA-Z0-9_.%-]"
            case ".", "?", "+", "[", "]", "(", ")", "{", "}", "\\", "|", "$": result += "\\" + String(character)
            default: result.append(character)
            }
        }
        if end { result += "$" }
        return result.isEmpty || result == ".*" ? nil : result
    }
}
