//
//  AlternativeServerURLViewModel.swift
//  romm
//

import Foundation
import Observation

@Observable
@MainActor
final class AlternativeServerURLViewModel {
    var url: String {
        didSet { errorMessage = nil }
    }
    private(set) var errorMessage: String?
    private(set) var isSaving = false
    let primaryURL: String

    private let savedURL: String
    private let saveAlternativeServerURLUseCase: PSaveAlternativeServerURLUseCase
    private let resolveServerEndpointUseCase: PResolveServerEndpointUseCase

    init(factory: PDependencyFactory = DefaultDependencyFactory.shared) {
        self.saveAlternativeServerURLUseCase = factory.makeSaveAlternativeServerURLUseCase()
        self.resolveServerEndpointUseCase = factory.makeResolveServerEndpointUseCase()
        let connection = factory.makeGetServerConnectionUseCase().execute()
        self.primaryURL = connection?.primaryURL ?? ""
        self.savedURL = connection?.alternativeURL ?? ""
        self.url = savedURL
    }

    var hasChanges: Bool {
        url.trimmingCharacters(in: .whitespacesAndNewlines) != savedURL
    }

    /// Returns true once the address is stored and the app picked the address
    /// it talks to from now on.
    func save() async -> Bool {
        errorMessage = nil
        do {
            try saveAlternativeServerURLUseCase.execute(url)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }

        isSaving = true
        await resolveServerEndpointUseCase.execute()
        isSaving = false
        return true
    }
}
