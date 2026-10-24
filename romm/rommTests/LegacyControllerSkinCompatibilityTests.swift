#if !APP_STORE
import Testing
import UIKit
import DeltaCore
import GBADeltaCore
import GBCDeltaCore
import NESDeltaCore
import SNESDeltaCore
import N64DeltaCore
import GPGXDeltaCore
import MelonDSDeltaCore

/// Exercises the actual bundled skins on conventional iPhone and iPad traits.
/// Core registration and UIKit fixtures stay on the main actor, matching the app.
@MainActor
struct LegacyControllerSkinCompatibilityTests {
    nonisolated private static let configurations = [
        "iphone-standard-portrait", "iphone-standard-landscape",
        "iphone-edgeToEdge-portrait", "iphone-edgeToEdge-landscape",
        "ipad-standard-portrait", "ipad-standard-landscape",
        "ipad-splitView-portrait", "ipad-splitView-landscape"
    ]

    @Test(
        arguments: ["gba", "gbc", "nes", "snes", "n64", "genesis", "ds"],
        configurations
    )
    func builtInSkinsKeepConventionalLayouts(core name: String, configuration: String) throws {
        let core = try registeredCore(named: name)
        let skin = try #require(ControllerSkin.standardControllerSkin(for: core.gameType))
        let traits = try traits(for: configuration)
        let supported = try #require(skin.supportedTraits(for: traits))

        #expect(skin.gameType == core.gameType)
        #expect(supported == traits)
        try expectImageLoads(skin.image(for: traits, preferredSize: .small))
        let size = try #require(skin.aspectRatio(for: traits))
        #expect(size.width > 0 && size.height > 0)

        let items = try #require(skin.items(for: traits))
        #expect(!items.isEmpty)
        // All seven systems need these controls. Checking their core mappings
        // catches a readable archive that nevertheless cannot drive its core.
        let controller = ControllerView(frame: .zero)
        controller.overrideControllerSkinTraits = traits
        controller.controllerSkin = skin
        for requiredInput in ["a", "b", "start"] {
            let input = try #require(items.flatMap(\.inputs.allInputs).first {
                $0.stringValue == requiredInput
            })
            let mapped = try #require(controller.defaultInputMapping?.input(forControllerInput: input))
            #expect(mapped.type == .game(core.gameType))
            #expect(mapped.stringValue == requiredInput)
        }
        #expect(items.contains { $0.inputs.allInputs.contains { $0.stringValue == "menu" } })

        if let screens = skin.screens(for: traits) {
            #expect(!screens.isEmpty)
            for screen in screens {
                if let input = screen.inputFrame {
                    #expect(input.width > 0 && input.height > 0)
                }
                if let output = screen.outputFrame {
                    expectNormalizedFrame(output)
                } else {
                    // App-owned screens can be positioned by GameViewController
                    // instead of declaring a controller-relative output frame.
                    #expect(screen.placement == .app)
                }
            }
        } else {
            // Single-screen systems may leave screen placement entirely to the
            // app. The DS must retain its explicit upper/lower input crops.
            #expect(name != "ds")
        }
    }

    @Test(arguments: configurations)
    func dsLegacyLayoutsKeepTheLowerTouchScreen(configuration: String) throws {
        let core = try registeredCore(named: "ds")
        let skin = try #require(ControllerSkin.standardControllerSkin(for: core.gameType))
        let traits = try traits(for: configuration)
        let screens = try #require(skin.screens(for: traits))
        #expect(screens.count == 2)
        let upper = try #require(screens.first)
        let lower = try #require(screens.last)
        #expect(upper.inputFrame == CGRect(x: 0, y: 0, width: 256, height: 192))
        #expect(lower.inputFrame == CGRect(x: 0, y: 192, width: 256, height: 192))
        #expect(!upper.isTouchScreen)
        #expect(lower.isTouchScreen)

        let lowerOutput = try #require(lower.outputFrame)
        let touchItems = try #require(skin.items(for: traits)).filter { $0.kind == .touchScreen }
        #expect(touchItems.count == 1)
        let touch = try #require(touchItems.first)
        #expect(touch.placement == lower.placement)
        #expect(touch.frame == lowerOutput)
        #expect(touch.extendedFrame.contains(lowerOutput))

        // Split view can put the lower screen and its touch input in the app
        // or in DeltaCore's separate keyboard controller. Its placement contract
        // is checked above; full-screen skins can also exercise real hit tests.
        if traits.displayType != .splitView {
            let size = try #require(skin.aspectRatio(for: traits))
            let controller = ControllerView(frame: CGRect(origin: .zero, size: size))
            controller.overrideControllerSkinTraits = traits
            controller.overrideControllerSkinSize = .small
            controller.controllerSkin = skin
            // DeltaCore installs delayed skin children on the first pass and
            // positions their hit regions on the second pass.
            controller.setNeedsLayout()
            controller.layoutIfNeeded()
            controller.setNeedsLayout()
            controller.layoutIfNeeded()

            let frame = lowerOutput.applying(CGAffineTransform(scaleX: size.width, y: size.height))
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            let touchView = try #require(controller.hitTest(centre, with: nil))
            expectFramesMatch(touchView.convert(touchView.bounds, to: controller), frame)
            for x in [CGFloat(0.05), 0.5, 0.95] {
                for y in [CGFloat(0.05), 0.5, 0.95] {
                    let point = CGPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
                    #expect(controller.hitTest(point, with: nil) === touchView)
                }
            }
            if let output = upper.outputFrame {
                let upperCentre = CGPoint(x: output.midX * size.width, y: output.midY * size.height)
                #expect(controller.hitTest(upperCentre, with: nil) !== touchView)
            }
        }
    }

    @Test(arguments: ["phone", "pad"])
    func windowDefaultsFollowTheWindowIdiom(idiom: String) throws {
        let window = UIWindow(frame: .zero)
        window.traitOverrides.userInterfaceIdiom = idiom == "pad" ? .pad : .phone
        window.traitOverrides.horizontalSizeClass = idiom == "pad" ? .regular : .compact
        window.frame = window.screen.bounds
        let defaults = ControllerSkin.Traits.defaults(for: window)

        #expect(defaults.device == (idiom == "pad" ? .ipad : .iphone))
        #expect(defaults.orientation == (window.bounds.width > window.bounds.height ? .landscape : .portrait))
        if idiom == "pad" {
            #expect(defaults.displayType == .standard)
        }
        #expect(defaults.displayType != .cover)
        #expect(defaults.displayType != .splitView)

        // Phone defaults use conventional display traits on ordinary phones,
        // and Duo traits on Duo hardware. Both must resolve a usable DS skin.
        let core = try registeredCore(named: "ds")
        let skin = try #require(ControllerSkin.standardControllerSkin(for: core.gameType))
        #expect(skin.supportedTraits(for: defaults) != nil)
        try expectImageLoads(skin.image(for: defaults, preferredSize: .small))
    }

    @Test func narrowerTabletWindowKeepsTheExistingSplitViewDefaults() throws {
        let window = UIWindow(frame: .zero)
        window.traitOverrides.userInterfaceIdiom = .pad
        let screen = window.screen.bounds
        window.frame = CGRect(x: 0, y: 0, width: screen.width * 0.6, height: screen.height)
        let defaults = ControllerSkin.Traits.defaults(for: window)

        #expect(defaults.device == .ipad)
        #expect(defaults.displayType == .splitView)
        // Split view uses the full display orientation, even for a narrow
        // portrait-shaped window on a landscape display.
        #expect(defaults.orientation == (screen.width > screen.height ? .landscape : .portrait))
    }

    private func registeredCore(named name: String) throws -> any DeltaCoreProtocol {
        let cores: [String: any DeltaCoreProtocol] = [
            "gba": GBA.core, "gbc": GBC.core, "nes": NES.core,
            "snes": SNES.core, "n64": N64.core, "genesis": GPGX.core,
            "ds": MelonDS.core
        ]
        let core = try #require(cores[name])
        Delta.register(core)
        return core
    }

    private func traits(for configuration: String) throws -> ControllerSkin.Traits {
        let parts = configuration.split(separator: "-").map(String.init)
        try #require(parts.count == 3)
        return ControllerSkin.Traits(
            device: try #require(ControllerSkin.Device(rawValue: parts[0])),
            displayType: try #require(ControllerSkin.DisplayType(rawValue: parts[1])),
            orientation: try #require(ControllerSkin.Orientation(rawValue: parts[2]))
        )
    }

    private func expectImageLoads(_ image: UIImage?) throws {
        let image = try #require(image)
        #expect(image.size.width > 0 && image.size.height > 0)
        #expect(image.cgImage != nil)
    }

    private func expectNormalizedFrame(_ frame: CGRect) {
        #expect(frame.width > 0 && frame.height > 0)
        #expect(frame.minX >= 0 && frame.minY >= 0)
        #expect(frame.maxX <= 1 && frame.maxY <= 1)
    }

    private func expectFramesMatch(_ actual: CGRect, _ expected: CGRect) {
        #expect(abs(actual.minX - expected.minX) < 0.001)
        #expect(abs(actual.minY - expected.minY) < 0.001)
        #expect(abs(actual.width - expected.width) < 0.001)
        #expect(abs(actual.height - expected.height) < 0.001)
    }
}
#endif
