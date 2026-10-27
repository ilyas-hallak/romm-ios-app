//
//  URLFormValueEncodingTests.swift
//  rommTests
//

import Testing
import Foundation
@testable import romm

struct URLFormValueEncodingTests {

    @Test func ampersandIsEscaped() {
        #expect("&".addingURLFormValueEncoding() == "%26")
    }

    @Test func plusIsEscaped() {
        #expect("+".addingURLFormValueEncoding() == "%2B")
    }

    @Test func equalsIsEscaped() {
        #expect("=".addingURLFormValueEncoding() == "%3D")
    }

    @Test func questionMarkIsEscaped() {
        #expect("?".addingURLFormValueEncoding() == "%3F")
    }

    @Test func hashIsEscaped() {
        #expect("#".addingURLFormValueEncoding() == "%23")
    }

    @Test func combinationOfStructuralCharactersIsEscaped() {
        let result = "a&b+c=d?e#f".addingURLFormValueEncoding()
        #expect(result == "a%26b%2Bc%3Dd%3Fe%23f")
    }

    @Test func realisticPasswordWithSpecialCharactersIsEscaped() {
        let result = "p@ss+word=1&2#3".addingURLFormValueEncoding()
        #expect(result == "p@ss%2Bword%3D1%262%233")
    }

    @Test func base64TokenWithPlusAndTrailingEqualsIsEscaped() {
        let token = "abc+DEF/123=="
        let result = token.addingURLFormValueEncoding()
        #expect(result == "abc%2BDEF/123%3D%3D")
    }

    @Test func harmlessValueIsNotOverEscaped() {
        #expect("mgba-2024".addingURLFormValueEncoding() == "mgba-2024")
    }

    @Test func emptyStringStaysEmpty() {
        #expect("".addingURLFormValueEncoding() == "")
    }

    // MARK: - Round trip through a form body

    private func decodedFormValue(_ body: String, key: String) -> String? {
        var components = URLComponents()
        components.percentEncodedQuery = body
        return components.queryItems?.first(where: { $0.name == key })?.value
    }

    @Test func formBodyRoundTripsAndDoesNotSwallowTheNextParameter() {
        let username = "user&name=1"
        let password = "p+w?#2"
        let body = [
            "grant_type=password",
            "username=\(username.addingURLFormValueEncoding())",
            "password=\(password.addingURLFormValueEncoding())",
            "scope="
        ].joined(separator: "&")

        #expect(decodedFormValue(body, key: "grant_type") == "password")
        #expect(decodedFormValue(body, key: "username") == username)
        #expect(decodedFormValue(body, key: "password") == password)
        #expect(decodedFormValue(body, key: "scope") == "")
    }
}
