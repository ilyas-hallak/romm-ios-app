//
//  SuggestPlatformForFileUseCase.swift
//  romm
//

import Foundation

/// Pure matching, no dependencies: given a file name and the server's
/// platforms, picks the first platform whose slug matches one of the file
/// extension's candidate slugs.
class SuggestPlatformForFileUseCase {
    func execute(fileName: String, platforms: [Platform]) -> Platform? {
        let candidates = RomFileExtensionPlatformHint.candidateSlugs(forFileName: fileName)
        guard !candidates.isEmpty else { return nil }

        for candidate in candidates {
            if let match = platforms.first(where: { $0.slug.caseInsensitiveCompare(candidate) == .orderedSame }) {
                return match
            }
        }
        return nil
    }
}
