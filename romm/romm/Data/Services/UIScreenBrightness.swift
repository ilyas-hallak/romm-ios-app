import UIKit

final class UIScreenBrightness: PScreenBrightness {
    var level: Double {
        get { MainActor.assumeIsolated { Double(UIScreen.main.brightness) } }
        set { MainActor.assumeIsolated { UIScreen.main.brightness = CGFloat(newValue) } }
    }
}
