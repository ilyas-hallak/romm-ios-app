//
//  ChangelogStore.swift
//  romm
//
//  Created by Ilyas Hallak on 23.08.25.
//

import Foundation
import Observation

@Observable
final class ChangelogStore {
    static let shared = ChangelogStore()

    let entries: [ChangelogEntry]
    let currentBuild: Int

    private static let lastSeenKey = "lastSeenChangelogBuild"
    private let logger = Logger.ui

    private init() {
        // Resolve current build number from bundle
        let buildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
        currentBuild = Int(buildString) ?? 0

        // Load and parse CHANGELOG.md from the app bundle
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md") else {
            logger.warning("CHANGELOG.md not found in app bundle")
            entries = []
            return
        }

        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            entries = ChangelogParser.parse(markdown)
        } catch {
            logger.warning("Failed to read CHANGELOG.md: \(error.localizedDescription)")
            entries = []
        }
    }

    // MARK: - Last seen persistence

    /// Mirrored into an observed property so SwiftUI re-evaluates `shouldShowWhatsNew`
    /// after `markSeen()`. `integer(forKey:)` returns 0 for an absent key, which we
    /// treat as "never seen".
    private var lastSeenBuild: Int? = {
        let stored = UserDefaults.standard.integer(forKey: "lastSeenChangelogBuild")
        return stored > 0 ? stored : nil
    }()

    // MARK: - Derived state

    var unseenEntries: [ChangelogEntry] {
        guard currentBuild > 0 else { return [] }

        if let last = lastSeenBuild {
            // Return entries newer than last seen, capped at 5
            return Array(entries.filter { $0.build > last }.prefix(5))
        } else {
            // Fresh install: only show the entry for the current build
            if let current = entries.first(where: { $0.build == currentBuild }) {
                return [current]
            }
            return []
        }
    }

    var shouldShowWhatsNew: Bool {
        !unseenEntries.isEmpty
    }

    // MARK: - Mark seen

    func markSeen() {
        guard currentBuild > 0 else { return }
        UserDefaults.standard.set(currentBuild, forKey: Self.lastSeenKey)
        lastSeenBuild = currentBuild
    }
}
