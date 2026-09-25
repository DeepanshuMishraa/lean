import Foundation

// A failed main-frame navigation, worth a page instead of a blank tab:
// what broke, where, and (via `url`) how to retry it.

/// Semantic classification of navigation errors for targeted UI presentation.
enum PageErrorKind: String, Equatable, Sendable {
    case hostNotFound
    case connectionRefused
    case offline
    case timedOut
    case connectionLost
    case insecure
    case unsupported
    case fileNotFound
    case generic

    var icon: LeanIcon {
        switch self {
        case .hostNotFound:
            return .compass
        case .connectionRefused:
            return .lightning
        case .offline:
            return .cloud
        case .timedOut:
            return .clock
        case .connectionLost:
            return .arrowsCounterClockwise
        case .insecure:
            return .shield
        case .fileNotFound:
            return .fileText
        case .unsupported:
            return .code
        case .generic:
            return .warning
        }
    }

    var badgeText: String {
        switch self {
        case .hostNotFound:
            return "Server Not Found"
        case .connectionRefused:
            return "Connection Refused"
        case .offline:
            return "Network Offline"
        case .timedOut:
            return "Timed Out"
        case .connectionLost:
            return "Connection Reset"
        case .insecure:
            return "Security Warning"
        case .fileNotFound:
            return "File Missing"
        case .unsupported:
            return "Unsupported URL"
        case .generic:
            return "Navigation Error"
        }
    }

    var errorCodeString: String {
        switch self {
        case .hostNotFound:
            return "DNS_PROBE_FINISHED_NXDOMAIN"
        case .connectionRefused:
            return "ERR_CONNECTION_REFUSED"
        case .offline:
            return "ERR_INTERNET_DISCONNECTED"
        case .timedOut:
            return "ERR_CONNECTION_TIMED_OUT"
        case .connectionLost:
            return "ERR_CONNECTION_RESET"
        case .insecure:
            return "ERR_CERT_AUTHORITY_INVALID"
        case .fileNotFound:
            return "ERR_FILE_NOT_FOUND"
        case .unsupported:
            return "ERR_UNKNOWN_URL_SCHEME"
        case .generic:
            return "ERR_FAILED"
        }
    }
}

struct PageLoadError: Equatable, Sendable {
    /// The address that failed. Reloading it retries the navigation.
    let url: URL?
    let title: String
    let message: String
    let kind: PageErrorKind
    let errorCode: Int?
    let errorDomain: String?
    let localizedDescription: String?

    init(
        url: URL?,
        title: String,
        message: String,
        kind: PageErrorKind = .generic,
        errorCode: Int? = nil,
        errorDomain: String? = nil,
        localizedDescription: String? = nil
    ) {
        self.url = url
        self.title = title
        self.message = message
        self.kind = kind
        self.errorCode = errorCode
        self.errorDomain = errorDomain
        self.localizedDescription = localizedDescription
    }

    var isDevServer: Bool {
        guard let url else { return false }
        return AddressResolver.isLoopbackURL(url)
    }

    /// Map a navigation failure to an error page, or nil for failures that
    /// must stay silent: user cancellations and loads WebKit itself
    /// interrupted (policy changes, a download taking over the navigation).
    static func from(_ error: Error, for url: URL?) -> PageLoadError? {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return nil }
        // WebKit yanked the load itself (e.g. a link with `download`, a
        // redirect it handles): not a failure, never a page.
        if ns.domain == "WebKitErrorDomain", ns.code == 102 { return nil }
        let failing = ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? url
        let host = failing?.host ?? url?.host
        let name = host.map { "“\($0)”" } ?? "This page"
        let devHint = (failing.map { AddressResolver.isLoopbackURL($0) } ?? false)
            ? "\n\nIf this is a dev server, make sure it's running, then reload."
            : ""
        switch ns.code {
        case NSURLErrorCannotFindHost:
            return PageLoadError(
                url: failing,
                title: "Server not found",
                message: "\(name) couldn't be found. Check the address and try again.\(devHint)",
                kind: .hostNotFound,
                errorCode: ns.code,
                errorDomain: ns.domain,
                localizedDescription: ns.localizedDescription
            )
        case NSURLErrorCannotConnectToHost:
            return PageLoadError(
                url: failing,
                title: "Couldn't connect to the server",
                message: "\(name) isn't responding.\(devHint.isEmpty ? " Check the address and try again." : devHint)",
                kind: .connectionRefused,
                errorCode: ns.code,
                errorDomain: ns.domain,
                localizedDescription: ns.localizedDescription
            )
        case NSURLErrorNotConnectedToInternet:
            return PageLoadError(
                url: failing,
                title: "You're offline",
                message: "Check your internet connection and try again.",
                kind: .offline,
                errorCode: ns.code,
                errorDomain: ns.domain,
                localizedDescription: ns.localizedDescription
            )
        case NSURLErrorTimedOut:
            return PageLoadError(
                url: failing,
                title: "The server took too long",
                message: "\(name) is taking too long to respond.",
                kind: .timedOut,
                errorCode: ns.code,
                errorDomain: ns.domain,
                localizedDescription: ns.localizedDescription
            )
        case NSURLErrorNetworkConnectionLost:
            return PageLoadError(
                url: failing,
                title: "The connection dropped",
                message: "The connection to \(name) was lost before the page arrived.",
                kind: .connectionLost,
                errorCode: ns.code,
                errorDomain: ns.domain,
                localizedDescription: ns.localizedDescription
            )
        case NSURLErrorSecureConnectionFailed,
             NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid:
            return PageLoadError(
                url: failing,
                title: "This connection isn't private",
                message: ns.localizedDescription,
                kind: .insecure,
                errorCode: ns.code,
                errorDomain: ns.domain,
                localizedDescription: ns.localizedDescription
            )
        case NSURLErrorUnsupportedURL:
            return PageLoadError(
                url: failing,
                title: "Can't open this address",
                message: "Lean doesn't know how to open this kind of link.",
                kind: .unsupported,
                errorCode: ns.code,
                errorDomain: ns.domain,
                localizedDescription: ns.localizedDescription
            )
        case NSURLErrorFileDoesNotExist:
            return PageLoadError(
                url: failing,
                title: "File not found",
                message: "\(name) doesn't exist at that path.",
                kind: .fileNotFound,
                errorCode: ns.code,
                errorDomain: ns.domain,
                localizedDescription: ns.localizedDescription
            )
        default:
            return PageLoadError(
                url: failing,
                title: "Couldn't load this page",
                message: ns.localizedDescription,
                kind: .generic,
                errorCode: ns.code,
                errorDomain: ns.domain,
                localizedDescription: ns.localizedDescription
            )
        }
    }
}
