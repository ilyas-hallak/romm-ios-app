//
//  ServerEndpoint.swift
//  romm
//

import Foundation

/// Which of the two saved addresses of the server the app talks to.
enum ServerEndpoint: String {
    case primary
    case alternative
}

/// Both addresses of the server and the one in use, as the settings show them.
struct ServerConnection: Equatable {
    let primaryURL: String
    let alternativeURL: String?
    let activeEndpoint: ServerEndpoint
}
