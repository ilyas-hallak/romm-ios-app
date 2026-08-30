import Testing
import Foundation

@testable import romm

/// The setup screen is where most support cases start, so the message it shows
/// has to name the actual problem.
@MainActor
struct ConnectionErrorMessageTests {

    /// The regression this guards: the heartbeat wraps the API error, and
    /// without unwrapping it every case fell through to `localizedDescription`,
    /// which for an HTTP error is the whole response body. Users were shown the
    /// raw HTML of a 404 page.
    @Test func unwrapsHeartbeatErrorInsteadOfShowingTheResponseBody() {
        let body = """
        <!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01//EN">
        <html><head><title>404 Not Found</title></head><body>
        <h1>Not Found</h1><address>Apache/2.4.67 (Debian) Server</address>
        </body></html>
        """
        let error = HeartbeatError.networkError(APIClientError.invalidResponse(404, body))

        let (message, details) = SetupViewModel().parseConnectionError(error)

        #expect(!message.contains("<"))
        #expect(!(details ?? "").contains("<"))
        #expect(!message.contains("Apache"))
        #expect(!(details ?? "").contains("Apache"))
    }

    /// A 404 means something answered but it is not RomM, usually the wrong port
    /// or a proxy pointing elsewhere. That is worth saying, since it rules out
    /// the address being unreachable.
    @Test func namesAMissingRommServerOnA404() {
        let error = HeartbeatError.networkError(APIClientError.invalidResponse(404, "not found"))

        let (message, details) = SetupViewModel().parseConnectionError(error)

        #expect(message == "No RomM server at this address")
        #expect(details?.contains("port") == true)
    }

    @Test func reportsOtherStatusCodesWithTheirCode() {
        let error = HeartbeatError.networkError(APIClientError.invalidResponse(502, "bad gateway"))

        let (message, _) = SetupViewModel().parseConnectionError(error)

        #expect(message.contains("502"))
    }

    @Test func recognisesATimeoutThroughBothWrappers() {
        let error = HeartbeatError.networkError(APIClientError.networkError(URLError(.timedOut)))

        let (message, _) = SetupViewModel().parseConnectionError(error)

        #expect(message == "Connection timed out")
    }

    /// Codes, not text: `localizedDescription` follows the phone's language, so
    /// classifying on English substrings left every non-English user with the
    /// same generic message no matter what went wrong.
    @Test(arguments: [
        (URLError.Code.cannotConnectToHost, "Connection failed"),
        (URLError.Code.cannotFindHost, "Server not found"),
        (URLError.Code.dnsLookupFailed, "Server not found"),
        (URLError.Code.notConnectedToInternet, "No connection"),
        (URLError.Code.secureConnectionFailed, "Certificate problem"),
        (URLError.Code.serverCertificateUntrusted, "Certificate problem"),
        (URLError.Code.unsupportedURL, "Invalid address"),
    ])
    func classifiesByCodeNotByLocalizedText(code: URLError.Code, expected: String) {
        let error = HeartbeatError.networkError(APIClientError.networkError(URLError(code)))

        let (message, details) = SetupViewModel().parseConnectionError(error)

        #expect(message == expected)
        #expect(details?.isEmpty == false)
    }

    @Test func keepsRecognisingCloudflare() {
        let error = HeartbeatError.networkError(APIClientError.cloudflareProtection("blocked"))

        let (message, _) = SetupViewModel().parseConnectionError(error)

        #expect(message.contains("Cloudflare"))
    }

    /// Authentication errors have to survive the unwrapping too, otherwise the
    /// most common case of all loses its message.
    @Test func keepsRecognisingAuthenticationFailure() {
        let error = HeartbeatError.networkError(APIClientError.authenticationRequired)

        let (message, _) = SetupViewModel().parseConnectionError(error)

        #expect(message == "Authentication failed")
    }
}
