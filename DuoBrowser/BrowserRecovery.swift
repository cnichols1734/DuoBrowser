import Foundation

/// A local, document-scoped failure. It contains no page content and is never archived.
struct BrowserLoadFailure: Identifiable, Equatable {
    enum Kind: Equatable { case offline, timeout, secureConnection, unavailable, processTerminated }
    let id = UUID()
    let documentID: UUID
    let kind: Kind
    let targetURL: URL?
    let allowsRetry: Bool

    init(kind: Kind, url: URL?, method: String, documentID: UUID) {
        self.kind = kind
        self.documentID = documentID
        targetURL = url.flatMap { WebAddress.valid($0) }
        allowsRetry = targetURL != nil && ["GET", "HEAD"].contains(method.uppercased())
    }

    var title: String {
        switch kind {
        case .offline: return "You’re Offline"
        case .timeout: return "The Page Took Too Long"
        case .secureConnection: return "Couldn’t Connect Securely"
        case .unavailable: return "Couldn’t Open Page"
        case .processTerminated: return "Page Stopped Responding"
        }
    }

    var message: String {
        switch kind {
        case .offline: return "Connect to the internet, then try again."
        case .timeout: return "The website didn’t respond. Try again in a moment."
        case .secureConnection: return "A secure connection could not be verified. This page was not opened."
        case .unavailable: return "Check the website address and try again."
        case .processTerminated: return "This page stopped responding. Reload to recover it; unsent changes may be lost."
        }
    }

    var symbol: String {
        switch kind {
        case .offline: return "wifi.slash"
        case .timeout: return "clock"
        case .secureConnection: return "lock.trianglebadge.exclamationmark"
        case .unavailable: return "globe"
        case .processTerminated: return "arrow.clockwise"
        }
    }

    var retryLabel: String { kind == .processTerminated ? "Reload" : "Try Again" }

    static func navigation(_ error: NSError, url: URL?, method: String, documentID: UUID) -> Self? {
        if error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled { return nil }
        let kind: Kind
        if error.domain == NSURLErrorDomain {
            switch error.code {
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                 NSURLErrorInternationalRoamingOff, NSURLErrorDataNotAllowed:
                kind = .offline
            case NSURLErrorTimedOut: kind = .timeout
            case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorSecureConnectionFailed, NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired:
                kind = .secureConnection
            default: kind = .unavailable
            }
        } else { kind = .unavailable }
        return Self(kind: kind, url: url, method: method, documentID: documentID)
    }
}
