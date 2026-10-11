import Foundation
import Testing
@testable import Lumi

struct MeshWarpTests {
    static func stroke(_ k: BrushStroke.Kind, x: Float = 0.5, y: Float = 0.5, r: Float = 0.3, s: Float = 0.5, dx: Float = 0, dy: Float = 0) -> BrushStroke {
        BrushStroke(kind: k, x: x, y: y, radius: r, strength: s, dirX: dx, dirY: dy)
    }

    @Test func newFieldIsIdentity() {
        let f = DisplacementField(cols: 9, rows: 9)
        #expect(f.isIdentity)
        #expect(f.offset(x: 0.3, y: 0.7) == (0, 0))
    }

    @Test func strokeOutsideRadiusChangesNothing() {
        var f = DisplacementField(cols: 17, rows: 17)
        f.apply(Self.stroke(.bloat, x: 0.1, y: 0.1, r: 0.05))
        #expect(f.offset(x: 0.9, y: 0.9) == (0, 0))
    }

    @Test func zeroRadiusOrStrengthIsNoOp() {
        var f = DisplacementField(cols: 17, rows: 17)
        f.apply(Self.stroke(.pinch, r: 0))
        f.apply(Self.stroke(.pinch, s: 0))
        #expect(f.isIdentity)
    }

    @Test func pinchSamplesAwayFromCenterAndBloatTowardIt() {
        var p = DisplacementField(cols: 33, rows: 33), b = p
        p.apply(Self.stroke(.pinch)); b.apply(Self.stroke(.bloat))
        let po = p.offset(x: 0.6, y: 0.5), bo = b.offset(x: 0.6, y: 0.5)
        #expect(po.0 > 0)      // right of center samples further right: content shrinks inward
        #expect(bo.0 < 0)
        #expect(abs(po.0 + bo.0) < 1e-6)
    }

    @Test func centerOfPinchAndBloatDoesNotMove() {
        var f = DisplacementField(cols: 33, rows: 33)
        f.apply(Self.stroke(.pinch))
        let o = f.offset(x: 0.5, y: 0.5)
        #expect(abs(o.0) < 1e-6 && abs(o.1) < 1e-6)
    }

    @Test func pushMovesContentAlongDrag() {
        var f = DisplacementField(cols: 33, rows: 33)
        f.apply(Self.stroke(.push, s: 1, dx: 0.1, dy: 0))
        let o = f.offset(x: 0.5, y: 0.5)
        #expect(abs(o.0 + 0.1) < 1e-5)  // source is behind the drag direction
        #expect(o.1 == 0)
    }

    @Test func strengthScalesOffsetLinearly() {
        var a = DisplacementField(cols: 33, rows: 33), b = a
        a.apply(Self.stroke(.push, s: 0.25, dx: 0.1)); b.apply(Self.stroke(.push, s: 0.5, dx: 0.1))
        #expect(abs(b.offset(x: 0.5, y: 0.5).0 / a.offset(x: 0.5, y: 0.5).0 - 2) < 1e-4)
    }

    @Test func sampleClampsOutsideUnitSquare() {
        var f = DisplacementField(cols: 9, rows: 9)
        f.apply(Self.stroke(.push, x: 1, y: 1, r: 0.5, s: 1, dx: 0.1))
        #expect(f.offset(x: 5, y: 5) == f.offset(x: 1, y: 1))
        #expect(f.offset(x: -5, y: -5) == f.offset(x: 0, y: 0))
    }

    @Test func samplingAtGridEdgeDoesNotCrash() {
        let f = DisplacementField(cols: 2, rows: 2)
        _ = f.offset(x: 1, y: 1); _ = f.offset(x: 0, y: 0)
    }

    @Test func bilinearInterpolatesBetweenGridPoints() {
        var f = DisplacementField(cols: 3, rows: 3)
        f.apply(Self.stroke(.push, x: 0.5, y: 0.5, r: 0.2, s: 1, dx: 0.2))  // only the center node moves
        let mid = f.offset(x: 0.5, y: 0.5), quarter = f.offset(x: 0.25, y: 0.5)
        #expect(abs(quarter.0 - mid.0 / 2) < 1e-6)
    }

    @Test func strokesAccumulate() {
        var e = WarpEdit()
        e.add(Self.stroke(.push, dx: 0.02)); let one = e.field.offset(x: 0.5, y: 0.5).0
        e.add(Self.stroke(.push, dx: 0.02)); let two = e.field.offset(x: 0.5, y: 0.5).0
        #expect(abs(two - 2 * one) < 1e-6)
    }

    @Test func undoRestoresExactlyAndRedoReapplies() {
        var e = WarpEdit()
        #expect(!e.canUndo && !e.canRedo)
        e.undo(); e.redo()                       // no-ops on empty
        e.add(Self.stroke(.bloat)); let after = e.field
        e.add(Self.stroke(.pinch, x: 0.2))
        e.undo()
        #expect(e.field == after)
        e.undo()
        #expect(e.field.isIdentity && !e.canUndo && e.canRedo)
        e.redo(); e.redo()
        #expect(e.strokes.count == 2 && !e.canRedo)
    }

    @Test func newStrokeClearsRedo() {
        var e = WarpEdit()
        e.add(Self.stroke(.bloat)); e.undo()
        e.add(Self.stroke(.pinch))
        #expect(!e.canRedo)
    }

    @Test func codableRoundTripKeepsFieldAndHistory() throws {
        var e = WarpEdit(cols: 17, rows: 17)
        e.add(Self.stroke(.push, dx: 0.05)); e.add(Self.stroke(.bloat)); e.undo()
        let back = try JSONDecoder().decode(WarpEdit.self, from: JSONEncoder().encode(e))
        #expect(back == e)
        #expect(back.field == e.field)
        #expect(back.canRedo)
    }

    @Test func fieldItselfIsCodable() throws {
        var f = DisplacementField(cols: 5, rows: 5)
        f.apply(Self.stroke(.pinch))
        #expect(try JSONDecoder().decode(DisplacementField.self, from: JSONEncoder().encode(f)) == f)
    }

    @Test func replayIsDeterministic() {
        var e = WarpEdit()
        for i in 0..<20 { e.add(Self.stroke(.push, x: Float(i) / 20, y: 0.5, r: 0.2, s: 0.3, dx: 0.01)) }
        #expect(e.field == e.field)
    }
}
