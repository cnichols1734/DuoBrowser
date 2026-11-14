#if DEBUG
import Foundation
import WebKit

extension NativeCheckRunner {
    /// Opt-in probes of synthetic stores only. This receipt never contains records, cookies, or URLs.
    func websiteDataDiagnostics(_ store: WKWebsiteDataStore) async {
        let receipt = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WebsiteDataDiagnostics.txt")
        let clock = ContinuousClock()
        let started = clock.now
        var stages = ["START website-data diagnostics"]
        func write() {
            try? (stages.joined(separator: "\n") + "\n").write(to: receipt, atomically: true, encoding: .utf8)
        }
        func elapsed(since beginning: ContinuousClock.Instant) -> String {
            let duration = beginning.duration(to: clock.now).components
            let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            return String(format: "%.3f s", seconds)
        }
        func probe(_ label: String, store candidate: WKWebsiteDataStore, types: Set<String>) async {
            stages.append("START " + label)
            write()
            let beginning = clock.now
            let deadline = beginning.advanced(by: .seconds(10))
            var completed = false
            candidate.fetchDataRecords(ofTypes: types) { _ in completed = true }
            // A task-group race would still await a WebKit call that ignores cancellation.
            // The callback owns only its completion flag; the bounded observer can finish independently.
            while !completed, clock.now < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
            }
            stages.append((completed ? "FINISHED " : "TIMEOUT ") + label + " · " + elapsed(since: beginning))
            write()
        }

        write()
        let empty = WKWebsiteDataStore(forIdentifier: UUID())
        let probes: [(String, Set<String>)] = [
            ("cookies", [WKWebsiteDataTypeCookies]),
            ("fetch-cache", [WKWebsiteDataTypeFetchCache]),
            ("managed", BrowsingDataSelection.managedTypes)
        ]
        for (label, types) in probes {
            await probe("synthetic " + label, store: store, types: types)
        }
        for (label, types) in probes {
            await probe("empty " + label, store: empty, types: types)
        }
        stages.append("FINISHED website-data diagnostics · " + elapsed(since: started))
        write()
    }
}
#endif
