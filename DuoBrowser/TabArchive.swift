import Foundation

struct TabRecord: Codable, Identifiable {
    let id: UUID
    var address: String?
    var fixture: Bool
    var scrollY: Double? = nil
}

struct TabArchive: Codable {
    var tabs: [TabRecord]
    var selectedID: UUID

    /// Ignore malformed, duplicate, or non-web destinations when restoring local state.
    func validated() -> TabArchive? {
        var seen = Set<UUID>()
        let valid = Array(tabs.prefix(200)).filter { record in
            guard seen.insert(record.id).inserted else { return false }
            guard let address = record.address else { return true }
            guard let parts = URLComponents(string: address),
                  ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
                  let host = parts.host, !host.isEmpty,
                  parts.user == nil, parts.password == nil else { return false }
            return parts.url != nil
        }
        guard let first = valid.first else { return nil }
        let sanitized = valid.map { record in
            var record = record
            if let y = record.scrollY, !y.isFinite || y < 0 || y > 10_000_000 { record.scrollY = nil }
            return record
        }
        return TabArchive(tabs: sanitized, selectedID: valid.contains { $0.id == selectedID } ? selectedID : first.id)
    }
}
