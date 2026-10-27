//
//  URLSessionConfigurationWithoutCookiesTests.swift
//  rommTests
//

import Foundation
import Testing
@testable import romm

struct URLSessionConfigurationWithoutCookiesTests {

    @Test func withoutCookiesDisablesCookieStorage() {
        let configuration = URLSessionConfiguration.ephemeral.withoutCookies()
        #expect(configuration.httpCookieStorage == nil)
        #expect(configuration.httpShouldSetCookies == false)
        #expect(configuration.httpCookieAcceptPolicy == .never)
    }

    @Test func defaultClientSessionHasNoCookieStorage() {
        let client = RommAPIClient()
        #expect(client.urlSession.configuration.httpCookieStorage == nil)
        #expect(client.urlSession.configuration.httpShouldSetCookies == false)
    }
}
