import Testing
import Foundation
@testable import romm

/// Redaction runs before anything reaches the log store, so these rules decide
/// what ends up in a log the user attaches to a bug report.
struct LogRedactionTests {

    /// The case that motivated the query-string rule: a metadata scraper URL that
    /// carried the user's own account password, short enough to slip past the
    /// "long token" rule and therefore exported in plain text.
    @Test func masksCredentialsInScraperQueryStrings() {
        let message = "Failed to load image from https://example.org/api2/mediaJeu.php"
            + "?devid=someuser&devpassword=xTJwoOFjOQG&softname=romm"
            + "&ssid=account&sspassword=Diggah123&systemeid=57"

        let redacted = LogStore.redact(message)

        #expect(!redacted.contains("xTJwoOFjOQG"))
        #expect(!redacted.contains("Diggah123"))
    }

    /// Short values are the interesting ones; anything over 20 characters was
    /// already covered by the pre-existing token rule.
    @Test(arguments: [
        "https://h/x?password=abc",
        "https://h/x?pass=abc",
        "https://h/x?api_key=abc",
        "https://h/x?apikey=abc",
        "https://h/x?token=abc",
        "https://h/x?secret=abc",
        "https://h/x?auth=abc",
        "https://h/x?sig=abc"
    ])
    func masksShortSensitiveQueryValues(url: String) {
        #expect(!LogStore.redact(url).contains("abc"))
    }

    /// Redacting must not swallow the parameters that make a log useful.
    @Test func keepsHarmlessQueryParameters() {
        let redacted = LogStore.redact("GET https://example.org/api/roms?limit=15&offset=0&order_dir=desc")

        #expect(redacted.contains("limit=15"))
        #expect(redacted.contains("offset=0"))
        #expect(redacted.contains("order_dir=desc"))
    }

    @Test func keepsMaskingBearerTokensAndHosts() {
        let redacted = LogStore.redact("Authorization: Bearer abc123 to https://secret.internal/api/roms")

        #expect(!redacted.contains("abc123"))
        #expect(!redacted.contains("secret.internal"))
        #expect(redacted.contains("/api/roms"))
    }
}
