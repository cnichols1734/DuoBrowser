import Foundation

@main
struct BrowserRecoveryTests {
    static func main() {
        var count = 0
        func check(_ value: @autoclosure () -> Bool, _ name: String) {
            precondition(value(), name)
            count += 1
        }
        let document = UUID()
        let url = URL(string: "https://example.com/path?q=test")!
        func failure(_ code: Int, domain: String = NSURLErrorDomain, method: String = "GET", target: URL? = nil) -> BrowserLoadFailure? {
            BrowserLoadFailure.navigation(NSError(domain: domain, code: code), url: target ?? url, method: method, documentID: document)
        }
        check(failure(NSURLErrorCancelled) == nil, "Cancellation never produces a failure surface")
        check(failure(NSURLErrorNotConnectedToInternet)?.kind == .offline, "Offline has a useful recovery state")
        check(failure(NSURLErrorNetworkConnectionLost)?.kind == .offline, "Lost connection has the same offline recovery")
        check(failure(NSURLErrorTimedOut)?.kind == .timeout, "Timeout is distinguished from no connection")
        for code in [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
                     NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid,
                     NSURLErrorSecureConnectionFailed, NSURLErrorClientCertificateRejected, NSURLErrorClientCertificateRequired] {
            check(failure(code)?.kind == .secureConnection, "Certificate errors never become a generic page error")
        }
        check(failure(NSURLErrorSecureConnectionFailed, domain: "UntrustedWebsite")?.kind == .unavailable,
              "Only actual URL-loading errors can claim a certificate failure")
        check(failure(NSURLErrorTimedOut)?.allowsRetry == true, "Safe GET can be explicitly retried")
        check(failure(NSURLErrorTimedOut, method: "HEAD")?.allowsRetry == true, "Safe HEAD can be reopened as GET")
        for method in ["POST", "PUT", "PATCH", "DELETE", "CONNECT"] {
            check(failure(NSURLErrorTimedOut, method: method)?.allowsRetry == false, "Recovery must not replay a mutating request")
        }
        for address in ["https://user:password@example.com", "javascript:alert(1)", "file:///tmp/private", "data:text/plain,secret"] {
            let rejected = failure(NSURLErrorTimedOut, target: URL(string: address)!)!
            check(rejected.targetURL == nil && !rejected.allowsRetry, "Untrusted failure URLs cannot become recovery navigation")
        }
        let untrusted = NSError(domain: NSURLErrorDomain, code: NSURLErrorUnknown,
                                userInfo: [NSLocalizedDescriptionKey: "UNTRUSTED RESPONSE AND SECRET"])
        let safe = BrowserLoadFailure.navigation(untrusted, url: url, method: "GET", documentID: document)!
        check(!safe.message.contains("UNTRUSTED") && !safe.title.contains("SECRET"), "Failure copy excludes remote error payloads")
        check(safe.documentID == document && safe.targetURL == url, "Recovery retains exact validated navigation scope")
        check(safe.id != failure(NSURLErrorUnknown)?.id, "Every failure has a unique action identity")
        let process = BrowserLoadFailure(kind: .processTerminated, url: url, method: "POST", documentID: document)
        check(!process.allowsRetry && process.message.contains("unsent changes"), "Process recovery cannot silently replay a submitted form")
        print("BrowserRecoveryTests: \(count) checks passed")
    }
}
