//
//  RommAPIClientQueryTests.swift
//  rommTests
//
//  `withQuery` is a plain, network-free instance method, so it's tested
//  directly rather than through a stubbed HTTP round trip.
//

import Testing
import Foundation
@testable import romm

struct RommAPIClientQueryTests {

    private func makeClient() -> RommAPIClient {
        RommAPIClient(tokenProvider: SaveSyncStubTokenProvider(serverURL: "https://romm.test"))
    }

    @Test func singleParameterIsAppended() {
        let result = makeClient().withQuery("api/saves", [("rom_id", "1")])
        #expect(result == "api/saves?rom_id=1")
    }

    @Test func multipleParametersAreJoinedWithAmpersand() {
        let result = makeClient().withQuery("api/saves", [
            ("rom_id", "1"),
            ("emulator", "mgba"),
            ("slot", "0")
        ])
        #expect(result == "api/saves?rom_id=1&emulator=mgba&slot=0")
    }

    @Test func nilParameterIsOmittedEntirely() {
        let result = makeClient().withQuery("api/saves", [
            ("rom_id", "1"),
            ("session_id", nil)
        ])
        #expect(result == "api/saves?rom_id=1")
        #expect(!result.contains("session_id"))
        #expect(!result.contains("nil"))
    }

    @Test func onlyNilParametersLeavePathUnchanged() {
        let result = makeClient().withQuery("api/saves", [
            ("device_id", nil),
            ("session_id", nil)
        ])
        #expect(result == "api/saves")
    }

    @Test func emptyParameterListLeavesPathUnchanged() {
        let result = makeClient().withQuery("api/saves", [])
        #expect(result == "api/saves")
    }

    @Test func autocleanupTrueIsSerialized() {
        let result = makeClient().withQuery("api/saves", [("autocleanup", "true")])
        #expect(result == "api/saves?autocleanup=true")
    }

    @Test func autocleanupFalseIsSerialized() {
        let result = makeClient().withQuery("api/saves", [("autocleanup", "false")])
        #expect(result == "api/saves?autocleanup=false")
    }

    @Test func spacesArePercentEncoded() {
        let result = makeClient().withQuery("api/saves", [("slot", "slot 1")])
        #expect(result == "api/saves?slot=slot%201")
    }

    @Test func romNameStyleParenthesesSurviveUnescaped() {
        // "()" are sub-delims in RFC 3986 and stay legal, unencoded characters
        // in a query value, `.urlQueryAllowed` does not escape them.
        let result = makeClient().withQuery("api/saves", [("emulator", "Super Mario (USA)")])
        #expect(result == "api/saves?emulator=Super%20Mario%20(USA)")
    }

    @Test func unicodeValueIsPercentEncoded() {
        let result = makeClient().withQuery("api/saves", [("slot", "über")])
        #expect(result == "api/saves?slot=%C3%BCber")
    }

    @Test func deviceIdAndSessionIdBothPresent() {
        let result = makeClient().withQuery("api/saves", [
            ("device_id", "device-abc"),
            ("session_id", "session-xyz")
        ])
        #expect(result == "api/saves?device_id=device-abc&session_id=session-xyz")
    }

    // MARK: - Structural characters in values

    @Test func ampersandInValueIsEscaped() {
        let result = makeClient().withQuery("api/roms", [("search_term", "Sonic & Knuckles")])
        #expect(result == "api/roms?search_term=Sonic%20%26%20Knuckles")
        #expect(!result.contains("&K"))
    }

    @Test func plusInValueIsEscaped() {
        // Unescaped "+" is read as a space by many servers, so a literal "+"
        // in a value has to be percent-encoded rather than passed through.
        let result = makeClient().withQuery("api/roms", [("search_term", "C++")])
        #expect(result == "api/roms?search_term=C%2B%2B")
    }

    @Test func equalsInValueIsEscaped() {
        let result = makeClient().withQuery("api/roms", [("search_term", "a=b")])
        #expect(result == "api/roms?search_term=a%3Db")
    }

    @Test func questionMarkInValueIsEscaped() {
        let result = makeClient().withQuery("api/roms", [("search_term", "what?")])
        #expect(result == "api/roms?search_term=what%3F")
    }

    @Test func hashInValueIsEscaped() {
        let result = makeClient().withQuery("api/roms", [("search_term", "Level #1")])
        #expect(result == "api/roms?search_term=Level%20%231")
    }

    @Test func searchTermCombiningStructuralCharactersIsEscaped() {
        let result = makeClient().withQuery("api/roms", [("search_term", "Sonic & Knuckles + Chaos? #2")])
        #expect(result == "api/roms?search_term=Sonic%20%26%20Knuckles%20%2B%20Chaos%3F%20%232")
    }

    @Test func harmlessValueIsNotOverEscaped() {
        // Regression guard: the fix must not start escaping characters that
        // were already fine, only the structural ones.
        let result = makeClient().withQuery("api/saves", [("emulator", "mgba-2024")])
        #expect(result == "api/saves?emulator=mgba-2024")
    }

    // MARK: - Round trip through URLComponents

    private func decodedQueryValue(_ path: String, key: String) -> String? {
        let url = URL(string: "https://romm.test/\(path)")!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        return components?.queryItems?.first(where: { $0.name == key })?.value
    }

    @Test func ampersandValueRoundTripsThroughURLComponents() {
        let path = makeClient().withQuery("api/roms", [("search_term", "Sonic & Knuckles")])
        #expect(decodedQueryValue(path, key: "search_term") == "Sonic & Knuckles")
    }

    @Test func plusValueRoundTripsThroughURLComponents() {
        let path = makeClient().withQuery("api/roms", [("search_term", "C++")])
        #expect(decodedQueryValue(path, key: "search_term") == "C++")
    }

    @Test func equalsValueRoundTripsThroughURLComponents() {
        let path = makeClient().withQuery("api/roms", [("search_term", "a=b")])
        #expect(decodedQueryValue(path, key: "search_term") == "a=b")
    }

    @Test func combinedStructuralCharactersRoundTripThroughURLComponents() {
        let searchTerm = "Sonic & Knuckles + Chaos? #2"
        let path = makeClient().withQuery("api/roms", [("search_term", searchTerm)])
        #expect(decodedQueryValue(path, key: "search_term") == searchTerm)
    }

    @Test func trailingParameterAfterStructuralValueIsNotSwallowed() {
        // Before the fix, an unescaped "&" in the first value would make the
        // second parameter look like a third query parameter instead of part
        // of the first value.
        let path = makeClient().withQuery("api/roms", [
            ("search_term", "Sonic & Knuckles"),
            ("limit", "50")
        ])
        #expect(decodedQueryValue(path, key: "search_term") == "Sonic & Knuckles")
        #expect(decodedQueryValue(path, key: "limit") == "50")
    }

    @Test func parenthesesStillRoundTripThroughURLComponents() {
        let path = makeClient().withQuery("api/saves", [("emulator", "Super Mario (USA)")])
        #expect(decodedQueryValue(path, key: "emulator") == "Super Mario (USA)")
    }
}
