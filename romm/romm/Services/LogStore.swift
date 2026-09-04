//
//  LogStore.swift
//  romm
//
//  Created by Ilyas Hallak on 13.08.25.
//

import Foundation
import Compression

// MARK: - Log Entry

struct LogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let level: LogLevel
    let category: LogCategory
    let message: String
    let file: String
    let function: String
    let line: Int

    var fileName: String {
        URL(fileURLWithPath: file).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
    }

    var formattedTimestamp: String {
        DateFormatter.logTimestamp.string(from: timestamp)
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        file: String,
        function: String,
        line: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.file = file
        self.function = function
        self.line = line
    }
}

// MARK: - Log Store

actor LogStore {
    static let shared = LogStore()

    private var entries: [LogEntry] = []
    private let maxEntries: Int

    private init(maxEntries: Int = 1000) {
        self.maxEntries = maxEntries
    }

    func addEntry(_ entry: LogEntry) {
        // Redact sensitive data before it ever reaches the in-memory store or export.
        let redactedEntry = LogEntry(
            id: entry.id,
            timestamp: entry.timestamp,
            level: entry.level,
            category: entry.category,
            message: LogStore.redact(entry.message),
            file: entry.file,
            function: entry.function,
            line: entry.line
        )
        entries.append(redactedEntry)

        // Keep only the most recent entries
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    // MARK: - Redaction

    /// Masks sensitive patterns (bearer tokens, long token-like strings, server hosts)
    /// so credentials and private hostnames never end up in the log store or an export.
    /// Internal rather than private so the redaction rules can be tested directly;
    /// a leak here is silent and only shows up in an exported log.
    static func redact(_ message: String) -> String {
        var result = message

        let patterns: [(pattern: String, template: String)] = [
            // Bearer tokens: "Bearer <token>" -> "Bearer <redacted>"
            ("(?i)(Bearer)\\s+[A-Za-z0-9._-]+", "$1 <redacted>"),
            // Credentials in query strings: "?sspassword=hunter2&..." -> "?sspassword=<redacted>&..."
            //
            // Has to run before the host is masked, and cannot be left to the
            // length rule below: passwords and API keys are routinely shorter
            // than 20 characters, so metadata scraper URLs were reaching the
            // export with the user's password in plain text.
            ("(?i)([?&][^=&\\s]*(?:pass(?:word)?|secret|token|api_?key|auth|credential|sig)[^=&\\s]*=)[^&\\s]+",
             "$1<redacted>"),
            // URLs: keep scheme and path, mask the host
            ("(?i)(https?://)[^/\\s]+", "$1<redacted-host>"),
            // Long token-like strings (>= 20 chars) -> "<redacted>"
            ("[A-Za-z0-9._-]{20,}", "<redacted>")
        ]

        for (pattern, template) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: template
            )
        }

        return result
    }

    func getEntries() -> [LogEntry] {
        return entries
    }

    func getEntries(
        level: LogLevel? = nil,
        category: LogCategory? = nil,
        searchText: String? = nil
    ) -> [LogEntry] {
        var filtered = entries

        if let level = level {
            filtered = filtered.filter { $0.level == level }
        }

        if let category = category {
            filtered = filtered.filter { $0.category == category }
        }

        if let searchText = searchText, !searchText.isEmpty {
            filtered = filtered.filter {
                $0.message.localizedCaseInsensitiveContains(searchText) ||
                $0.fileName.localizedCaseInsensitiveContains(searchText) ||
                $0.function.localizedCaseInsensitiveContains(searchText)
            }
        }

        return filtered
    }

    func clear() {
        entries.removeAll()
    }

    func exportAsText() -> String {
        var text = "RomM Debug Logs\n"
        text += "Generated: \(DateFormatter.exportTimestamp.string(from: Date()))\n"
        text += "Total Entries: \(entries.count)\n"
        text += String(repeating: "=", count: 80) + "\n\n"

        for entry in entries {
            text += "[\(entry.formattedTimestamp)] "
            text += "[\(entry.level.emoji) \(levelName(for: entry.level))] "
            text += "[\(entry.category.rawValue)] "
            text += "\(entry.fileName):\(entry.line) "
            text += "\(entry.function)\n"
            text += "  \(entry.message)\n\n"
        }

        return text
    }

    func exportAsZippedData() throws -> (data: Data, filename: String) {
        // Generate log text
        let logText = exportAsText()
        guard let logData = logText.data(using: .utf8) else {
            throw NSError(domain: "LogStore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert logs to UTF-8"])
        }

        // Create filename with timestamp
        let timestamp = DateFormatter.filenameTimestamp.string(from: Date())
        let filename = "romm-logs-\(timestamp).zip"
        let logFilename = "romm-logs-\(timestamp).txt"

        // Create ZIP archive
        let zipData = try createZipArchive(filename: logFilename, data: logData)

        return (zipData, filename)
    }

    private func createZipArchive(filename: String, data: Data) throws -> Data {
        // Create a simple ZIP file structure
        // ZIP file format: https://en.wikipedia.org/wiki/ZIP_(file_format)

        let crc32 = calculateCRC32(data: data)
        let compressedData = try compressData(data)

        var zipData = Data()

        // Local file header
        zipData.append(contentsOf: [0x50, 0x4B, 0x03, 0x04]) // Local file header signature
        zipData.append(contentsOf: [0x14, 0x00]) // Version needed to extract (2.0)
        zipData.append(contentsOf: [0x00, 0x00]) // General purpose bit flag
        zipData.append(contentsOf: [0x08, 0x00]) // Compression method (deflate)
        zipData.append(contentsOf: [0x00, 0x00]) // File last modification time
        zipData.append(contentsOf: [0x00, 0x00]) // File last modification date
        zipData.append(contentsOf: UInt32(crc32).littleEndianBytes) // CRC-32
        zipData.append(contentsOf: UInt32(compressedData.count).littleEndianBytes) // Compressed size
        zipData.append(contentsOf: UInt32(data.count).littleEndianBytes) // Uncompressed size
        zipData.append(contentsOf: UInt16(filename.utf8.count).littleEndianBytes) // File name length
        zipData.append(contentsOf: [0x00, 0x00]) // Extra field length
        zipData.append(contentsOf: filename.utf8) // File name
        zipData.append(compressedData) // Compressed data

        let localHeaderSize = zipData.count

        // Central directory header
        let centralDirStart = zipData.count
        zipData.append(contentsOf: [0x50, 0x4B, 0x01, 0x02]) // Central directory file header signature
        zipData.append(contentsOf: [0x14, 0x00]) // Version made by
        zipData.append(contentsOf: [0x14, 0x00]) // Version needed to extract
        zipData.append(contentsOf: [0x00, 0x00]) // General purpose bit flag
        zipData.append(contentsOf: [0x08, 0x00]) // Compression method
        zipData.append(contentsOf: [0x00, 0x00]) // File last modification time
        zipData.append(contentsOf: [0x00, 0x00]) // File last modification date
        zipData.append(contentsOf: UInt32(crc32).littleEndianBytes) // CRC-32
        zipData.append(contentsOf: UInt32(compressedData.count).littleEndianBytes) // Compressed size
        zipData.append(contentsOf: UInt32(data.count).littleEndianBytes) // Uncompressed size
        zipData.append(contentsOf: UInt16(filename.utf8.count).littleEndianBytes) // File name length
        zipData.append(contentsOf: [0x00, 0x00]) // Extra field length
        zipData.append(contentsOf: [0x00, 0x00]) // File comment length
        zipData.append(contentsOf: [0x00, 0x00]) // Disk number start
        zipData.append(contentsOf: [0x00, 0x00]) // Internal file attributes
        zipData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // External file attributes
        zipData.append(contentsOf: [0x00, 0x00, 0x00, 0x00]) // Relative offset of local header
        zipData.append(contentsOf: filename.utf8) // File name

        let centralDirSize = zipData.count - centralDirStart

        // End of central directory record
        zipData.append(contentsOf: [0x50, 0x4B, 0x05, 0x06]) // End of central directory signature
        zipData.append(contentsOf: [0x00, 0x00]) // Number of this disk
        zipData.append(contentsOf: [0x00, 0x00]) // Disk where central directory starts
        zipData.append(contentsOf: [0x01, 0x00]) // Number of central directory records on this disk
        zipData.append(contentsOf: [0x01, 0x00]) // Total number of central directory records
        zipData.append(contentsOf: UInt32(centralDirSize).littleEndianBytes) // Size of central directory
        zipData.append(contentsOf: UInt32(centralDirStart).littleEndianBytes) // Offset of start of central directory
        zipData.append(contentsOf: [0x00, 0x00]) // Comment length

        return zipData
    }

    private func compressData(_ data: Data) throws -> Data {
        var compressedData = Data()
        let bufferSize = 4096

        try data.withUnsafeBytes { (sourceBytes: UnsafeRawBufferPointer) in
            guard let sourcePointer = sourceBytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                throw NSError(domain: "LogStore", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to get source pointer"])
            }

            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { destinationBuffer.deallocate() }

            let streamPtr = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
            defer { streamPtr.deallocate() }

            var stream = streamPtr.pointee
            var status = compression_stream_init(&stream, COMPRESSION_STREAM_ENCODE, COMPRESSION_ZLIB)
            guard status == COMPRESSION_STATUS_OK else {
                throw NSError(domain: "LogStore", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize compression stream"])
            }
            defer { compression_stream_destroy(&stream) }

            stream.src_ptr = sourcePointer
            stream.src_size = data.count
            stream.dst_ptr = destinationBuffer
            stream.dst_size = bufferSize

            while status == COMPRESSION_STATUS_OK {
                status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))

                switch status {
                case COMPRESSION_STATUS_OK, COMPRESSION_STATUS_END:
                    let bytesWritten = bufferSize - stream.dst_size
                    compressedData.append(destinationBuffer, count: bytesWritten)
                    stream.dst_ptr = destinationBuffer
                    stream.dst_size = bufferSize
                case COMPRESSION_STATUS_ERROR:
                    throw NSError(domain: "LogStore", code: 4, userInfo: [NSLocalizedDescriptionKey: "Compression failed"])
                default:
                    break
                }
            }
        }

        return compressedData
    }

    private func calculateCRC32(data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF

        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = (crc >> 8) ^ crc32Table[index]
        }

        return crc ^ 0xFFFFFFFF
    }

    // CRC-32 lookup table
    private var crc32Table: [UInt32] {
        return (0..<256).map { i -> UInt32 in
            var crc = UInt32(i)
            for _ in 0..<8 {
                crc = (crc & 1 == 1) ? ((crc >> 1) ^ 0xEDB88320) : (crc >> 1)
            }
            return crc
        }
    }

    private func levelName(for level: LogLevel) -> String {
        switch level.rawValue {
        case 0: return "DEBUG"
        case 1: return "INFO"
        case 2: return "NOTICE"
        case 3: return "WARNING"
        case 4: return "ERROR"
        case 5: return "CRITICAL"
        default: return "UNKNOWN"
        }
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    static let exportTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    static let filenameTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

// MARK: - Helper Extensions for ZIP

extension UInt32 {
    var littleEndianBytes: [UInt8] {
        return [
            UInt8(self & 0xFF),
            UInt8((self >> 8) & 0xFF),
            UInt8((self >> 16) & 0xFF),
            UInt8((self >> 24) & 0xFF)
        ]
    }
}

extension UInt16 {
    var littleEndianBytes: [UInt8] {
        return [
            UInt8(self & 0xFF),
            UInt8((self >> 8) & 0xFF)
        ]
    }
}
