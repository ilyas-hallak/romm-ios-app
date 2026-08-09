//
//  LaunchEmulatorUseCase.swift
//  romm
//
//  Created by Ilyas Hallak on 21.12.24.
//

import Foundation

enum LaunchDecision: Identifiable {
    case web(rom: Rom)
    case native(rom: Rom, gameType: DeltaGameType)
    case libretro(rom: Rom, core: LibretroCore)

    var id: String {
        switch self {
        case .web(let rom): return "web-\(rom.id)"
        case .native(let rom, _): return "native-\(rom.id)"
        case .libretro(let rom, _): return "libretro-\(rom.id)"
        }
    }
}

enum EmulatorLaunchResult {
    case success(LaunchDecision)
    case failure(EmulatorLaunchError)
}

enum EmulatorLaunchError: LocalizedError {
    case noServerConfigured
    case unsupportedPlatform(String)
    case romNotAvailable
    case serverUnreachable
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .noServerConfigured:
            return "No server configured. Please set up your ROMM server in Settings."
        case .unsupportedPlatform(let platform):
            return "Platform '\(platform)' is not supported for emulation."
        case .romNotAvailable:
            return "ROM file is not available. Please download it first or check your server connection."
        case .serverUnreachable:
            return "Cannot reach ROMM server. Please check your connection."
        case .unknown(let message):
            return message
        }
    }
}

protocol PLaunchEmulatorUseCase {
    func execute(rom: Rom) async -> EmulatorLaunchResult
}

final class LaunchEmulatorUseCase: PLaunchEmulatorUseCase {
    private let tokenProvider: PTokenProvider
    private let checkEmulatorSupport: PCheckEmulatorSupportUseCase
    private let enginePreference: PEmulatorEnginePreference
    private let platformSupport: PPlatformEngineSupport
    private let logger = Logger.viewModel

    init(
        tokenProvider: PTokenProvider,
        checkEmulatorSupport: PCheckEmulatorSupportUseCase,
        enginePreference: PEmulatorEnginePreference,
        platformSupport: PPlatformEngineSupport
    ) {
        self.tokenProvider = tokenProvider
        self.checkEmulatorSupport = checkEmulatorSupport
        self.enginePreference = enginePreference
        self.platformSupport = platformSupport
    }

    func execute(rom: Rom) async -> EmulatorLaunchResult {
        print("[LaunchEmulator] execute called for rom id=\(rom.id) name=\(rom.name) platformSlug=\(rom.platformSlug ?? "nil")")
        guard tokenProvider.getServerURL() != nil else {
            print("[LaunchEmulator] FAIL: no server configured")
            return .failure(.noServerConfigured)
        }
        guard let platformSlug = rom.platformSlug else {
            print("[LaunchEmulator] FAIL: platformSlug nil")
            return .failure(.unsupportedPlatform("Unknown"))
        }
        guard checkEmulatorSupport.execute(platformSlug: platformSlug) else {
            print("[LaunchEmulator] FAIL: platform '\(platformSlug)' not supported")
            return .failure(.unsupportedPlatform(platformSlug))
        }

        let supported = platformSupport.supportedEngines(for: platformSlug)
        let pref = enginePreference.current
        print("[LaunchEmulator] platformSlug='\(platformSlug)', preference=\(pref.rawValue), supported=\(supported.map { $0.rawValue })")
        let chosen: EmulatorEngine = {
            switch pref {
            case .web: return supported.contains(.web) ? .web : .native
            case .native: return supported.contains(.native) ? .native : .web
            case .auto: return platformSupport.preferred(for: platformSlug)
            }
        }()
        print("[LaunchEmulator] chosen engine=\(chosen.rawValue)")

        switch chosen {
        case .web:
            return .success(.web(rom: rom))
        case .native:
            if let gameType = PlatformSlugToGameType.map(platformSlug) {
                return .success(.native(rom: rom, gameType: gameType))
            }
            if let core = PlatformSlugToLibretroCore.map(platformSlug) {
                return .success(.libretro(rom: rom, core: core))
            }
            // No native core for this platform. Only fall back to web when the
            // web engine is actually available in this build.
            if AppFeatures.webEmulatorEnabled {
                return .success(.web(rom: rom))
            }
            return .failure(.unsupportedPlatform(platformSlug))
        case .auto:
            return .success(.web(rom: rom))
        }
    }
}
