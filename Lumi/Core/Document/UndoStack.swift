import Foundation

/// Snapshot undo for value-type state. `commit` ignores no-op changes and clears redo.
struct UndoStack<State: Equatable> {
    private(set) var current: State
    private var past: [State] = []
    private var future: [State] = []

    init(_ initial: State) { current = initial }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func commit(_ new: State) {
        guard new != current else { return }
        past.append(current); current = new; future.removeAll()
    }
    mutating func undo() { guard let p = past.popLast() else { return }; future.append(current); current = p }
    mutating func redo() { guard let f = future.popLast() else { return }; past.append(current); current = f }
}
