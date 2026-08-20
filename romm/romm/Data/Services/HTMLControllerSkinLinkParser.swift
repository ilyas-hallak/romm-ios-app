import Foundation

/// Finds `.deltaskin` download links in an HTML page.
///
/// Deliberately generic: catalog sites put the download in whatever attribute
/// they like (delta-skins.github.io uses `data-download`, others use `href`), so
/// every quoted attribute value ending in `.deltaskin` counts, regardless of the
/// attribute name.
final class HTMLControllerSkinLinkParser: PControllerSkinLinkParser {

    /// One alternation instead of two passes, so the results stay in the order
    /// the page lists them even when it mixes quote styles. That order is the
    /// one the page author chose, usually newest first.
    private static let linkPattern = #""([^"]+\.deltaskin)"|'([^']+\.deltaskin)'"#

    /// How far to search for the enclosing tag's boundaries. A link in body text
    /// has no tag around it, and without a limit every such match would scan the
    /// whole document.
    private static let tagSearchWindow = 2_000

    func links(in html: String, pageURL: URL) -> [ControllerSkinLink] {
        guard let regex = try? NSRegularExpression(
            pattern: Self.linkPattern,
            options: .caseInsensitive
        ) else { return [] }

        let nsHTML = html as NSString
        var seen = Set<URL>()
        var results: [ControllerSkinLink] = []

        regex.enumerateMatches(
            in: html,
            range: NSRange(location: 0, length: nsHTML.length)
        ) { match, _, _ in
            guard let match, let value = capturedValue(of: match, in: nsHTML) else { return }

            let decoded = value.replacingOccurrences(of: "&amp;", with: "&")
            guard let url = URL(string: decoded, relativeTo: pageURL)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  seen.insert(url).inserted else { return }

            results.append(
                ControllerSkinLink(name: displayName(for: match, in: nsHTML, url: url), url: url)
            )
        }

        return results
    }

    // MARK: - Private

    /// The pattern has one group per quote style; exactly one of them matched.
    private func capturedValue(of match: NSTextCheckingResult, in html: NSString) -> String? {
        for group in 1..<match.numberOfRanges {
            let range = match.range(at: group)
            if range.location != NSNotFound {
                return html.substring(with: range)
            }
        }
        return nil
    }

    /// Prefers the `alt`/`title` the page shows next to the skin, since that is
    /// the name its author picked. Falls back to the file name.
    private func displayName(for match: NSTextCheckingResult, in html: NSString, url: URL) -> String {
        if let tag = enclosingTag(of: match, in: html),
           let name = attribute("alt", in: tag) ?? attribute("title", in: tag) {
            return name
        }
        return nameFromFileName(url.lastPathComponent)
    }

    /// Text from the `<` before the match to the `>` after it, or `nil` when the
    /// match isn't inside a tag within the search window.
    private func enclosingTag(of match: NSTextCheckingResult, in html: NSString) -> String? {
        let matchStart = match.range.location
        let matchEnd = matchStart + match.range.length

        var start = matchStart
        let lowerBound = max(0, matchStart - Self.tagSearchWindow)
        while start > lowerBound, html.character(at: start - 1) != UInt16(UnicodeScalar("<").value) {
            start -= 1
        }
        guard start > 0, html.character(at: start - 1) == UInt16(UnicodeScalar("<").value) else {
            return nil
        }

        var end = matchEnd
        let upperBound = min(html.length, matchEnd + Self.tagSearchWindow)
        while end < upperBound, html.character(at: end) != UInt16(UnicodeScalar(">").value) {
            end += 1
        }
        guard end < html.length, html.character(at: end) == UInt16(UnicodeScalar(">").value) else {
            return nil
        }

        return html.substring(with: NSRange(location: start, length: end - start))
    }

    /// Requires a boundary before the name so `alt=` doesn't also match inside
    /// something like `data-salt=`.
    private func attribute(_ name: String, in tag: String) -> String? {
        let patterns = [#"(?:^|[\s"'])\#(name)\s*=\s*"([^"]*)""#,
                        #"(?:^|[\s"'])\#(name)\s*=\s*'([^']*)'"#]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                  let range = Range(match.range(at: 1), in: tag) else { continue }
            let value = String(tag[range]).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// Turns `Purple_SNES.deltaskin` or `purple%20snes.deltaskin` into a readable label.
    private func nameFromFileName(_ fileName: String) -> String {
        let decoded = fileName.removingPercentEncoding ?? fileName
        let name = (decoded as NSString).deletingPathExtension
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? fileName : name
    }
}
