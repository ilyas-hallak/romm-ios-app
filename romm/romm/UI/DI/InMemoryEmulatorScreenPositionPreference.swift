import Foundation

final class InMemoryEmulatorScreenPositionPreference: PEmulatorScreenPositionPreference {
    var mode: ControllerScreenMode = .off
    var verticalOffset: Double = 0.5
    var heightFraction: Double = 1.0
}
