//
//  FakeExternalSaveFileRepository.swift
//  rommTests
//
//  Shared test double for PExternalSaveFileRepository.
//

import Foundation
@testable import romm

/// Stands in for the real folder repository: hands back canned contents and
/// records writes, without touching any actual folder or security scope.
final class FakeExternalSaveFileRepository: PExternalSaveFileRepository, @unchecked Sendable {

    var folders: [ExternalEmulatorID] = []
    var contentsByEmulator: [ExternalEmulatorID: ExternalSaveFolderContents] = [:]
    /// What `readSaves` answers with, keyed by the URL a scan reported.
    var savesByURL: [URL: Data] = [:]
    var destinationsByBaseName: [String: ExternalSaveDestination] = [:]
    private(set) var writes: [(data: Data, destination: ExternalSaveDestination, modifiedAt: Date)] = []

    func emulatorsWithFolder() -> [ExternalEmulatorID] { folders }

    func contents(for emulator: ExternalEmulatorID) -> ExternalSaveFolderContents? {
        contentsByEmulator[emulator]
    }

    func readSaves(at urls: [URL], for emulator: ExternalEmulatorID) -> [URL: Data] {
        urls.reduce(into: [URL: Data]()) { result, url in
            if let data = savesByURL[url] { result[url] = data }
        }
    }

    func destination(for emulator: ExternalEmulatorID, baseName: String) -> ExternalSaveDestination? {
        destinationsByBaseName[baseName]
    }

    func write(_ data: Data, to destination: ExternalSaveDestination, modifiedAt: Date) throws {
        writes.append((data, destination, modifiedAt))
    }
}
