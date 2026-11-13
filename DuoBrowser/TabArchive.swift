import Foundation

struct TabRecord: Codable, Identifiable {
    let id: UUID
    var address: String?
    var fixture: Bool
    var scrollY: Double? = nil
    var workspaceID: UUID? = nil
    var pinned: Bool? = nil
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

/// URL-only recovery. Page contents, credentials and private tabs never enter this record.
struct ClosedTabRecord: Codable, Identifiable {
    static let limit = 20
    var id = UUID()
    var address: String
    var title: String
    var scrollY: Double?
    var workspaceID: UUID
    var pinned: Bool
    var closedAt = Date()

    /// Accessibility notices stay available until explicitly dismissed; ordinary notices use the original close time.
    func noticeRemaining(at now: Date = Date(), persistent: Bool) -> TimeInterval? {
        if persistent { return nil }
        let remaining = 8 - now.timeIntervalSince(closedAt)
        return remaining.isFinite ? min(8, max(0, remaining)) : 0
    }

    static func validated(_ records: [ClosedTabRecord]) -> [ClosedTabRecord] {
        var seen = Set<UUID>()
        return Array(records.filter { record in
            guard seen.insert(record.id).inserted,
                  WebAddress.valid(URL(string: record.address)) != nil else { return false }
            return true
        }.prefix(limit)).map { record in
            var record = record
            record.title = String(record.title.prefix(512))
            if let y = record.scrollY, !y.isFinite || y < 0 || y > 10_000_000 { record.scrollY = nil }
            return record
        }
    }
}
