//
//  ChangelogEntry.swift
//  romm
//
//  Created by Ilyas Hallak on 23.08.25.
//

import Foundation

struct ChangelogEntry: Identifiable, Equatable, Sendable {
    /// The build number, or 0 for a section that summarises several builds and
    /// therefore has no single number ("Builds 40 to 46", "Earlier builds").
    /// Only entries with a build > 0 take part in the "what's new" comparison.
    let build: Int
    let version: String
    /// "2026-08-23", or a looser label like "June to August 2026", or nil.
    let date: String?
    /// Markdown body of the section, without its heading line.
    let body: String
    /// Heading shown above the entry, e.g. "Build 49" or "Builds 40 to 46".
    let title: String
    /// Position in the file. Entries keep source order, so the changelog has to
    /// be authored newest-first.
    let order: Int

    var id: String { "\(order)-\(title)" }

    init(
        build: Int,
        version: String,
        date: String?,
        body: String,
        title: String? = nil,
        order: Int = 0
    ) {
        self.build = build
        self.version = version
        self.date = date
        self.body = body
        self.title = title ?? (build > 0 ? "Build \(build)" : "Earlier builds")
        self.order = order
    }
}
