//
//  FileValidationService.swift
//  romm
//
//  Created by Ilyas Hallak on 26.08.25.
//

import Foundation

protocol PFileValidationService {
    func validateFile(at path: String, expectedSize: Int64?, expectedChecksum: String?) -> FileValidationResult
    func calculateChecksum(at path: String) throws -> String
    func getFileSize(at path: String) throws -> Int64
}

class FileValidationService: PFileValidationService {
    
    func validateFile(at path: String, expectedSize: Int64? = nil, expectedChecksum: String? = nil) -> FileValidationResult {
        do {
            let actualSize = try getFileSize(at: path)
            let actualChecksum = try calculateChecksum(at: path)
            
            var isValid = true
            var errorMessage: String? = nil
            
            // Validate file size
            if let expectedSize = expectedSize {
                if actualSize != expectedSize {
                    isValid = false
                    let actualSizeStr = ByteCountFormatter.string(fromByteCount: actualSize, countStyle: .file)
                    let expectedSizeStr = ByteCountFormatter.string(fromByteCount: expectedSize, countStyle: .file)
                    errorMessage = "File size mismatch: got \(actualSizeStr), expected \(expectedSizeStr)"
                }
            }
            
            // Validate checksum if provided
            if let expectedChecksum = expectedChecksum {
                if actualChecksum.lowercased() != expectedChecksum.lowercased() {
                    isValid = false
                    let checksumError = "Checksum mismatch: got \(actualChecksum), expected \(expectedChecksum)"
                    errorMessage = errorMessage != nil ? "\(errorMessage!); \(checksumError)" : checksumError
                }
            }
            
            return FileValidationResult(
                isValid: isValid,
                actualSize: actualSize,
                expectedSize: expectedSize,
                actualChecksum: actualChecksum,
                expectedChecksum: expectedChecksum,
                errorMessage: errorMessage
            )
            
        } catch {
            return FileValidationResult(
                isValid: false,
                actualSize: 0,
                expectedSize: expectedSize,
                actualChecksum: "",
                expectedChecksum: expectedChecksum,
                errorMessage: "Failed to validate file: \(error.localizedDescription)"
            )
        }
    }
    
    func calculateChecksum(at path: String) throws -> String {
        try FileHashing.sha256(ofFileAt: URL(fileURLWithPath: path))
    }
    
    func getFileSize(at path: String) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw FileValidationError.cannotReadFileSize
        }
        return fileSize.int64Value
    }
}

enum FileValidationError: Error, LocalizedError {
    case cannotReadFileSize
    case cannotCalculateChecksum
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .cannotReadFileSize:
            return "Cannot read file size"
        case .cannotCalculateChecksum:
            return "Cannot calculate file checksum"
        case .fileNotFound:
            return "File not found"
        }
    }
}
