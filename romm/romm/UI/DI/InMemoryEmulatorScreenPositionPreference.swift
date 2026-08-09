import Foundation

final class InMemoryEmulatorScreenPositionPreference: PEmulatorScreenPositionPreference {
    var position: EmulatorScreenPosition = .center
    var heightFraction: Double = 1.0
}
