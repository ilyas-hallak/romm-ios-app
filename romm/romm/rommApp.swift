//
//  rommApp.swift
//  romm
//
//  Created by Ilyas Hallak on 06.08.25.
//

import SwiftUI

@main
struct rommApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        _ = KingfisherCacheManager.shared
        KingfisherCacheManager.shared.configureAuth(tokenProvider: TokenProvider())
    }

    var body: some Scene {
        WindowGroup {
            AppView()
                .onOpenURL { url in
                    IncomingURLRouter.shared.handle(url)
                }
        }
    }
}
