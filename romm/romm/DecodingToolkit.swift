//
//  DecodingToolkit.swift
//  romm
//
//  Utilities for resilient decoding against API drift (type mismatches, nulls, lossy arrays)
//

import Foundation

// MARK: - KeyedDecodingContainer Helpers

extension KeyedDecodingContainer {
    /// Decode a value or return a default if decoding fails or value is missing
    func decodeOrDefault<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T) -> T {
        (try? decode(type, forKey: key)) ?? defaultValue()
    }

    /// Decode an optional value or return a default if decoding fails or value is nil/missing
    func decodeIfPresentOrDefault<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T) -> T {
        (try? decodeIfPresent(type, forKey: key)) ?? defaultValue()
    }

    /// Flexible Int decoding: accepts Int, String ("42"), Double (42.0)
    func decodeFlexibleInt(forKey key: Key, default defaultValue: Int = 0) -> Int {
        if let v = try? decode(Int.self, forKey: key) { return v }
        if let s = try? decode(String.self, forKey: key), let v = Int(s) { return v }
        if let d = try? decode(Double.self, forKey: key) { return Int(d) }
        return defaultValue
    }

    /// Flexible Bool decoding: accepts Bool, String ("true"/"1"), Int (1/0)
    func decodeFlexibleBool(forKey key: Key, default defaultValue: Bool = false) -> Bool {
        if let v = try? decode(Bool.self, forKey: key) { return v }
        if let s = try? decode(String.self, forKey: key) {
            let lower = s.lowercased()
            if ["true","1","yes","y"].contains(lower) { return true }
            if ["false","0","no","n"].contains(lower) { return false }
        }
        if let i = try? decode(Int.self, forKey: key) { return i != 0 }
        return defaultValue
    }

    /// Flexible String decoding: accepts String, Int, Double
    func decodeFlexibleString(forKey key: Key, default defaultValue: String = "") -> String {
        if let s = try? decode(String.self, forKey: key) { return s }
        if let i = try? decode(Int.self, forKey: key) { return String(i) }
        if let d = try? decode(Double.self, forKey: key) { return String(d) }
        return defaultValue
    }

    /// Lossy array decoding: skips invalid elements instead of failing the whole decode
    func decodeLossyArray<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T] {
        (try? decode(LossyArray<T>.self, forKey: key))?.elements ?? []
    }
}

// MARK: - Lossy array decoding

/// Decodes a JSON array, skipping elements that fail to decode instead of
/// failing the whole array. Works for bare top-level arrays too.
struct LossyArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var items: [Element] = []
        while !container.isAtEnd {
            if let value = try? container.decode(Element.self) {
                items.append(value)
            } else {
                _ = try? container.decode(DiscardableValue.self) // skip invalid element
            }
        }
        elements = items
    }
}

// MARK: - Helpers to discard unknown/invalid structures

private struct DiscardableValue: Decodable {
    init(from decoder: Decoder) throws {
        if var unkeyed = try? decoder.unkeyedContainer() {
            while !unkeyed.isAtEnd { _ = try? unkeyed.decode(DiscardableValue.self) }
        } else if let keyed = try? decoder.container(keyedBy: AnyCodingKey.self) {
            for key in keyed.allKeys { _ = try? keyed.decode(DiscardableValue.self, forKey: key) }
        } else {
            _ = try? decoder.singleValueContainer() // primitive
        }
    }
}

private struct AnyCodingKey: CodingKey {
    var stringValue: String
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int?
    init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
}
