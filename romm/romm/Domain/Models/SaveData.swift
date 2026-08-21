import Foundation

enum SaveKind: Equatable {
    case battery
    case state(slot: Int)
}

struct SaveStateEntry: Equatable, Identifiable {
    let slot: Int
    let modifiedAt: Date
    var id: Int { slot }
}

enum SaveStateCaptureError: LocalizedError {
    /// The core never finished writing the state file it was asked for.
    case incomplete

    var errorDescription: String? {
        switch self {
        case .incomplete:
            return "The emulator did not finish writing the save state. Nothing was overwritten."
        }
    }
}
