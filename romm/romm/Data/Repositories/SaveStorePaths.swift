import Foundation

enum SaveStorePaths {
    static func defaultRootDirectory() -> URL {
        let docs = try! FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        return docs.appendingPathComponent("Saves", isDirectory: true)
    }

    static func romDir(root: URL, romId: Int) -> URL {
        root.appendingPathComponent("\(romId)", isDirectory: true)
    }

    static func statesDir(root: URL, romId: Int) -> URL {
        romDir(root: root, romId: romId).appendingPathComponent("states", isDirectory: true)
    }

    static func batteryURL(root: URL, romId: Int) -> URL {
        romDir(root: root, romId: romId).appendingPathComponent("battery.sav")
    }

    static func stateURL(root: URL, romId: Int, slot: Int) -> URL {
        statesDir(root: root, romId: romId).appendingPathComponent("\(slot).dltastate")
    }

    static func thumbURL(root: URL, romId: Int, slot: Int) -> URL {
        statesDir(root: root, romId: romId).appendingPathComponent("\(slot).png")
    }

    static func stateBaselineURL(root: URL, romId: Int, slot: Int) -> URL {
        statesDir(root: root, romId: romId).appendingPathComponent("\(slot).baseline.json")
    }

    static func undoSaveStateURL(root: URL, romId: Int, slot: Int) -> URL {
        statesDir(root: root, romId: romId).appendingPathComponent("\(slot).dltastate.undo")
    }

    static func undoSaveThumbURL(root: URL, romId: Int, slot: Int) -> URL {
        statesDir(root: root, romId: romId).appendingPathComponent("\(slot).png.undo")
    }

    static func undoLoadStateURL(root: URL, romId: Int) -> URL {
        statesDir(root: root, romId: romId).appendingPathComponent("undo-load.dltastate")
    }

    static func undoLoadThumbURL(root: URL, romId: Int) -> URL {
        statesDir(root: root, romId: romId).appendingPathComponent("undo-load.png")
    }

    static let stateFileExtension = "dltastate"
}
