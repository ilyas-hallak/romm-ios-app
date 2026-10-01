//
//  URLSessionConfiguration+WithoutCookies.swift
//  romm
//
//  Created by Ilyas Hallak on 25.09.26.
//

import Foundation

extension URLSessionConfiguration {
    // We authenticate by header only. Since RomM 5.3 a romm_session cookie next to
    // that header, e.g. one the web emulator left behind, fails the CSRF check with 403.
    func withoutCookies() -> URLSessionConfiguration {
        httpCookieStorage = nil
        httpShouldSetCookies = false
        httpCookieAcceptPolicy = .never
        return self
    }
}
