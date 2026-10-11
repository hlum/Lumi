import Testing
@testable import Lumi

struct UndoStackTests {
    @Test func startsWithNothingToUndoOrRedo() {
        let s = UndoStack(0)
        #expect(!s.canUndo && !s.canRedo && s.current == 0)
    }

    @Test func undoAndRedoOnEmptyAreNoOps() {
        var s = UndoStack(5)
        s.undo(); s.redo()
        #expect(s.current == 5)
    }

    @Test func commitUndoRedo() {
        var s = UndoStack(0)
        s.commit(1); s.commit(2)
        s.undo(); #expect(s.current == 1)
        s.undo(); #expect(s.current == 0 && !s.canUndo)
        s.redo(); s.redo(); #expect(s.current == 2 && !s.canRedo)
    }

    @Test func identicalCommitIsIgnored() {
        var s = UndoStack(1)
        s.commit(1)
        #expect(!s.canUndo)
    }

    @Test func commitClearsRedo() {
        var s = UndoStack(0)
        s.commit(1); s.undo(); s.commit(9)
        #expect(!s.canRedo && s.current == 9)
        s.undo(); #expect(s.current == 0)
    }

    @Test func worksForDocuments() {
        var s = UndoStack(EditDocument())
        var d = EditDocument(); d.exposure = 1
        s.commit(d); s.undo()
        #expect(s.current == EditDocument())
    }
}
