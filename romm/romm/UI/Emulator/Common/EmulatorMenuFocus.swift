import SwiftUI

/// Controller focus for the in-game menu: which entry is selected, and what a
/// menu command does to it.
///
/// The menu is laid out as rows of entries. Up and down move between rows,
/// left and right within one. Entries listed as adjustable take left and right
/// as a value change instead, for controls like a slot picker.
///
/// The focus starts hidden so touch players never see it. The first command
/// only reveals it, without acting, because the player cannot know yet what is
/// selected. Back is the exception and closes right away.
struct EmulatorMenuFocus<Item: Hashable> {

    enum Outcome: Equatable {
        case none
        case activate(Item)
        case adjust(Item, by: Int)
        case dismiss
    }

    private let rows: [[Item]]
    private let adjustableItems: Set<Item>
    private(set) var focused: Item
    private(set) var isVisible = false

    init(rows: [[Item]], initial: Item, adjustableItems: Set<Item> = []) {
        precondition(rows.contains { $0.contains(initial) }, "initial must be one of the rows")
        self.rows = rows
        self.adjustableItems = adjustableItems
        self.focused = initial
    }

    func isFocused(_ item: Item) -> Bool {
        isVisible && focused == item
    }

    mutating func handle(_ command: EmulatorMenuCommand) -> Outcome {
        if command == .back { return .dismiss }
        guard isVisible else {
            isVisible = true
            return .none
        }
        switch command {
        case .confirm:
            return .activate(focused)
        case .left, .right:
            let step = command == .left ? -1 : 1
            if adjustableItems.contains(focused) {
                return .adjust(focused, by: step)
            }
            moveWithinRow(by: step)
        case .up:
            moveToRow(by: -1)
        case .down:
            moveToRow(by: 1)
        case .back:
            break
        }
        return .none
    }

    private var position: (row: Int, column: Int) {
        for (rowIndex, row) in rows.enumerated() {
            if let column = row.firstIndex(of: focused) {
                return (rowIndex, column)
            }
        }
        preconditionFailure("focused item is always one of the rows")
    }

    private mutating func moveWithinRow(by step: Int) {
        let (row, column) = position
        let target = column + step
        guard rows[row].indices.contains(target) else { return }
        focused = rows[row][target]
    }

    /// Keeps the column where the next row has one, otherwise lands on its last
    /// entry, so moving down from a wide row into a single entry and back is
    /// predictable.
    private mutating func moveToRow(by step: Int) {
        let (row, column) = position
        let target = row + step
        guard rows.indices.contains(target), !rows[target].isEmpty else { return }
        focused = rows[target][min(column, rows[target].count - 1)]
    }
}

extension View {

    /// Outlines the entry the controller focus is on.
    func emulatorMenuFocusRing(_ isFocused: Bool, cornerRadius: CGFloat = 12) -> some View {
        overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.accentColor, lineWidth: 2)
            }
        }
    }
}
