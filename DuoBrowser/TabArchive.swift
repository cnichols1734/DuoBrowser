import Foundation

struct TabRecord: Codable, Identifiable {
    let id: UUID
    var address: String?
    var fixture: Bool
}

struct TabArchive: Codable {
    var tabs: [TabRecord]
    var selectedID: UUID

    /// Ignore malformed, duplicate, or non-web destinations when restoring local state.
    func validated() -> TabArchive? {
        var seen = Set<UUID>()
        let valid = tabs.filter { record in
            guard seen.insert(record.id).inserted else { return false }
            guard let address = record.address else { return true }
            guard let parts = URLComponents(string: address),
                  ["https", "http"].contains(parts.scheme?.lowercased() ?? ""),
                  let host = parts.host, !host.isEmpty,
                  parts.user == nil, parts.password == nil else { return false }
            return parts.url != nil
        }
        guard let first = valid.first else { return nil }
        return TabArchive(tabs: valid, selectedID: valid.contains { $0.id == selectedID } ? selectedID : first.id)
    }
}
