//
//  Data+Multipart.swift
//  romm
//
//  Created by Ilyas Hallak on 31.08.26.
//

import Foundation

// MARK: - Multipart Helper

extension Data {
    /// Appends one `multipart/form-data` text field. The caller still writes the
    /// closing `--boundary--` line itself.
    mutating func appendFormField(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
