import Foundation

/// The device's own screen brightness, 0…1.
///
/// Behind a protocol so the blanking logic can be exercised without a device,
/// and so the UI layer stops reaching for `UIScreen.main` directly. Writing this
/// changes a system wide setting that outlives the app, which is the reason the
/// old value is persisted rather than merely held in memory.
protocol PScreenBrightness: AnyObject {
    var level: Double { get set }
}
