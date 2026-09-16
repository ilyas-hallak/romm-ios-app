//
//  URLFormValueEncoding.swift
//  romm
//
//  Created by Ilyas Hallak on 16.09.26.
//

import Foundation

extension String {
    /// Percent-encodes this value for safe use as one value inside a `key=value&key=value`
    /// sequence, whether that's a URL query string or an `application/x-www-form-urlencoded`
    /// body. `.urlQueryAllowed` leaves "&", "+", "=", "?" and "#" unescaped, since those
    /// characters are legal *somewhere* in such a sequence, but a value that contains one of
    /// them would then be read as extra parameters, a literal space (in a form body), or the
    /// start of a new query/fragment, so they must always be escaped here.
    func addingURLFormValueEncoding() -> String {
        var allowedCharacters = CharacterSet.urlQueryAllowed
        allowedCharacters.remove(charactersIn: "&+=?#")
        return addingPercentEncoding(withAllowedCharacters: allowedCharacters) ?? self
    }
}
