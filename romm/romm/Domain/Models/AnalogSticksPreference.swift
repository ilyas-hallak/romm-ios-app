import Foundation

/// Whether PlayStation games get the pad with two analog sticks.
///
/// Only PlayStation offers the choice: the sticks need the core to emulate a
/// DualShock, and some older titles behave differently once one is plugged in.
/// The plain pad stays the default, so nothing changes for a player who never
/// touches the switch.
protocol PAnalogSticksPreference: AnyObject {
    var isEnabled: Bool { get set }
}
