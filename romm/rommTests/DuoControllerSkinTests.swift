#if !APP_STORE
import Testing
import UIKit
import DeltaCore
import MelonDSDeltaCore
import GBADeltaCore

/// These tests use the frameworks' bundled archives so missing Git LFS assets
/// fail here even when the core source itself compiles successfully.
@MainActor
struct DuoControllerSkinTests {
    @Test(arguments: ["inner", "outer"], ["portrait", "landscape"])
    func dsDuoRepresentationsLoadBothScreens(display: String, orientation: String) throws {
        let skin = try dsSkin()
        let traits = try duoTraits(display: display, orientation: orientation)

        // A Duo layout must use its own artwork rather than silently falling
        // back to a conventional phone or tablet representation.
        #expect(skin.supports(traits))
        #expect(skin.supportedTraits(for: traits) == traits)
        try expectImageLoads(skin.image(for: traits, preferredSize: .large))

        let screens = try #require(skin.screens(for: traits))
        try expectDSScreenInputs(screens)
        #expect(screens.map(\.isTouchScreen) == [false, true])

        let upperFrame = try #require(screens.first?.outputFrame)
        let lowerFrame = try #require(screens.last?.outputFrame)
        #expect(!upperFrame.isEmpty)
        #expect(!lowerFrame.isEmpty)
        #expect(!upperFrame.intersects(lowerFrame))
        #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(upperFrame))
        #expect(CGRect(x: 0, y: 0, width: 1, height: 1).contains(lowerFrame))
    }

    @Test(arguments: ["inner", "outer"], ["portrait", "landscape"])
    func dsTouchHitRegionTracksTheLowerScreen(display: String, orientation: String) throws {
        let skin = try dsSkin()
        let traits = try duoTraits(display: display, orientation: orientation)
        let screens = try #require(skin.screens(for: traits))
        try expectDSScreenInputs(screens)
        let lowerFrame = try #require(screens.last?.outputFrame)
        let upperFrame = try #require(screens.first?.outputFrame)
        let touchItems = try #require(skin.items(for: traits)).filter { $0.kind == .touchScreen }
        #expect(touchItems.count == 1)
        let touchItem = try #require(touchItems.first)

        #expect(touchItem.placement == .controller)
        #expect(touchItem.frame == lowerFrame)
        #expect(touchItem.extendedFrame == lowerFrame)

        let size = try #require(skin.aspectRatio(for: traits))
        let controller = ControllerView(frame: CGRect(origin: .zero, size: size))
        controller.overrideControllerSkinTraits = traits
        controller.overrideControllerSkinSize = .large
        controller.controllerSkin = skin
        controller.setNeedsLayout()
        controller.layoutIfNeeded()
        // The first ControllerView layout installs the delayed skin update
        // and returns. Its newly created touch views receive their frames on
        // the next UIKit layout pass, just as they do after app presentation.
        controller.setNeedsLayout()
        controller.layoutIfNeeded()

        // Use DeltaCore's actual hit test, not a second implementation of its
        // touch-selection policy. Test inset corners as well as the centre.
        let lowerDisplayFrame = scaled(lowerFrame, to: size)
        let centre = CGPoint(x: lowerDisplayFrame.midX, y: lowerDisplayFrame.midY)
        let touchView = try #require(controller.hitTest(centre, with: nil))
        expectFramesMatch(
            touchView.convert(touchView.bounds, to: controller),
            lowerDisplayFrame,
            accuracy: 1 / max(1, controller.contentScaleFactor)
        )

        for x in [CGFloat(0.05), 0.5, 0.95] {
            for y in [CGFloat(0.05), 0.5, 0.95] {
                let point = CGPoint(
                    x: lowerDisplayFrame.minX + lowerDisplayFrame.width * x,
                    y: lowerDisplayFrame.minY + lowerDisplayFrame.height * y
                )
                #expect(controller.hitTest(point, with: nil) === touchView)
            }
        }
        let upperDisplayFrame = scaled(upperFrame, to: size)
        let upperCentre = CGPoint(x: upperDisplayFrame.midX, y: upperDisplayFrame.midY)
        #expect(controller.hitTest(upperCentre, with: nil) !== touchView)

        guard case .touch(let x, let y) = touchItem.inputs else {
            Issue.record("The lower DS screen must provide touch coordinate inputs.")
            return
        }
        #expect(controller.defaultInputMapping?.input(forControllerInput: x) as? MelonDSGameInput == .touchScreenX)
        #expect(controller.defaultInputMapping?.input(forControllerInput: y) as? MelonDSGameInput == .touchScreenY)
    }

    @Test(arguments: ["portrait", "landscape"])
    func dsSplitViewPreservesBothScreensAndLoadsFallbackArtwork(orientation: String) throws {
        let skin = try dsSkin()
        let requested = try duoTraits(display: "splitView", orientation: orientation)
        let supported = try #require(skin.supportedTraits(for: requested))

        #expect(supported.displayType == .splitView)
        #expect(supported.orientation == requested.orientation)
        // Delta 2.0 provides a Duo landscape keyboard skin; portrait keeps the
        // established iPad split-view representation as its supported fallback.
        #expect(supported.device == (orientation == "portrait" ? .ipad : .iphone))
        try expectImageLoads(skin.image(for: requested, preferredSize: .large))
        let screens = try #require(skin.screens(for: requested))
        try expectDSScreenInputs(screens)
        #expect(skin.items(for: requested)?.contains { $0.kind == .touchScreen } == true)
    }

    @Test func dsLandscapeCoverLoadsNormalAndChargingArtworkWithoutGameControls() throws {
        let skin = try dsSkin()
        // The cover view deliberately requests landscape, including when the
        // outer display is portrait. A portrait cover asset is not required.
        let traits = try duoTraits(display: "cover", orientation: "landscape")
        #expect(skin.supports(traits))
        try expectImageLoads(skin.image(for: traits, preferredSize: .large))
        try expectImageLoads(skin.pressedImage(for: traits, preferredSize: .large))
        #expect(skin.items(for: traits)?.isEmpty == true)
        #expect(skin.screens(for: traits)?.isEmpty != false)
    }

    @Test(arguments: ["inner", "outer"], ["portrait", "landscape"])
    func gbaLegacySkinsRemainUsableOnDuo(display: String, orientation: String) throws {
        Delta.register(GBA.core)
        let skin = try #require(ControllerSkin.standardControllerSkin(for: .gba))
        let requested = try duoTraits(display: display, orientation: orientation)
        let supported = try #require(skin.supportedTraits(for: requested))

        #expect(!skin.supports(requested))
        #expect(supported.device == (display == "inner" ? .ipad : .iphone))
        #expect(supported.displayType == .standard)
        #expect(supported.orientation == requested.orientation)
        try expectImageLoads(skin.image(for: requested, preferredSize: .large))

        let items = try #require(skin.items(for: requested))
        #expect(items.contains { $0.inputs.allInputs.contains { $0.stringValue == "a" } })
        #expect(items.contains { $0.inputs.allInputs.contains { $0.stringValue == "b" } })
        let size = try #require(skin.aspectRatio(for: requested))
        #expect(size.width > 0 && size.height > 0)
    }

    private func dsSkin() throws -> ControllerSkin {
        Delta.register(MelonDS.core)
        return try #require(ControllerSkin.standardControllerSkin(for: .ds))
    }

    private func duoTraits(display: String, orientation: String) throws -> ControllerSkin.Traits {
        ControllerSkin.Traits(
            device: .iphone,
            displayType: try #require(ControllerSkin.DisplayType(rawValue: display)),
            orientation: try #require(ControllerSkin.Orientation(rawValue: orientation))
        )
    }

    private func expectImageLoads(_ image: UIImage?) throws {
        let image = try #require(image)
        #expect(image.size.width > 0 && image.size.height > 0)
        #expect(image.cgImage != nil)
    }

    private func expectDSScreenInputs(_ screens: [ControllerSkin.Screen]) throws {
        #expect(screens.count == 2)
        let upper = try #require(screens.first)
        let lower = try #require(screens.last)
        #expect(upper.inputFrame == CGRect(x: 0, y: 0, width: 256, height: 192))
        #expect(lower.inputFrame == CGRect(x: 0, y: 192, width: 256, height: 192))
    }

    private func scaled(_ frame: CGRect, to size: CGSize) -> CGRect {
        frame.applying(CGAffineTransform(scaleX: size.width, y: size.height))
    }

    private func expectFramesMatch(_ actual: CGRect, _ expected: CGRect, accuracy: CGFloat) {
        // Normalizing the skin's pixels and laying them out in UIKit can
        // introduce floating-point or display-pixel rounding differences.
        #expect(abs(actual.minX - expected.minX) <= accuracy)
        #expect(abs(actual.minY - expected.minY) <= accuracy)
        #expect(abs(actual.width - expected.width) <= accuracy)
        #expect(abs(actual.height - expected.height) <= accuracy)
    }
}
#endif
