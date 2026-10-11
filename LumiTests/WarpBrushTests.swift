import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Lumi

@MainActor
struct WarpBrushTests {
    static func line(_ n: Int = 20) -> [CGPoint] { (0...n).map { CGPoint(x: 0.2 + 0.6 * Double($0) / Double(n), y: 0.5) } }

    @Test func emptyPathMakesNoStrokes() { #expect(WarpBrush().strokes(for: []).isEmpty) }

    @Test func pushFollowsTheDragDirectionAndScalesWithStrength() {
        var b = WarpBrush(); b.kind = .push; b.size = 0.1
        let s = b.strokes(for: Self.line())
        #expect(!s.isEmpty && s.allSatisfy { $0.kind == .push && $0.dirX > 0 && abs($0.dirY) < 1e-6 })
        var weak = b; weak.strength = 0.2
        #expect(weak.strokes(for: Self.line())[0].strength < s[0].strength)
    }

    @Test func totalPushDistanceMatchesTheDrag() {
        var b = WarpBrush(); b.kind = .push; b.size = 0.05
        let total = b.strokes(for: Self.line()).reduce(0.0) { $0 + Double($1.dirX) }
        #expect(abs(total - 0.6) < 0.05)
    }

    @Test func spacingKeepsDragsCheap() {
        var b = WarpBrush(); b.size = 0.2
        let dense = (0...1000).map { CGPoint(x: 0.1 + 0.8 * Double($0) / 1000, y: 0.5) }
        #expect(b.strokes(for: dense).count < 40)                                                       // not one stroke per touch sample
    }

    @Test func bloatAndPinchStampAlongThePathWithoutDirection() {
        for k in [BrushStroke.Kind.bloat, .pinch] {
            var b = WarpBrush(); b.kind = k; b.size = 0.1
            let s = b.strokes(for: Self.line())
            #expect(s.count >= 2 && s.allSatisfy { $0.kind == k && $0.dirX == 0 && $0.dirY == 0 })
        }
        var tap = WarpBrush(); tap.kind = .bloat
        #expect(tap.strokes(for: [CGPoint(x: 0.5, y: 0.5)]).count == 1)                                  // a single press still acts
    }

    @Test func sizeAndStrengthAreClamped() {
        var b = WarpBrush(); b.size = 9; b.strength = 9
        let s = b.strokes(for: Self.line())
        #expect(s.allSatisfy { $0.radius <= 0.5 && $0.strength <= 1 })
        b.size = 0; b.strength = -2
        #expect(b.strokes(for: Self.line()).allSatisfy { $0.radius >= 0.02 && $0.strength >= 0 })
    }

    @Test func aDragWarpsTheImageAndUndoStepsBackOneDrag() {
        let m = EditorModel(saver: EditorModelTests.FakeSaver())
        m.load(image: MeshWarpRendererTests.ramp())
        m.warpBrush.kind = .push; m.warpBrush.size = 0.2; m.warpBrush.strength = 1
        var w = WarpEdit(); m.warpBrush.strokes(for: Self.line()).forEach { w.add($0) }
        m.draft.warp = w; m.commit()
        #expect(!m.draft.warp.field.isIdentity && m.canUndo)
        let one = m.draft.warp
        var w2 = one; m.warpBrush.strokes(for: Self.line()).forEach { w2.add($0) }
        m.draft.warp = w2; m.commit()
        m.undo(); #expect(m.draft.warp == one)                                                           // second drag undone, first kept
        m.undo(); #expect(m.draft.warp.field.isIdentity)
    }

    @Test func cheekVolumeAndLiftAddStrokes() {
        let f = FaceReshapeTests.face()
        var vol = FaceReshapeParams(); vol.cheekVolume = 1
        let v = FaceReshape.strokes(for: f, params: vol)
        #expect(v.count == 2 && v.allSatisfy { $0.kind == .bloat })
        vol.cheekVolume = -1
        #expect(FaceReshape.strokes(for: f, params: vol).allSatisfy { $0.kind == .pinch })
        var lift = FaceReshapeParams(); lift.lift = 1
        let l = FaceReshape.strokes(for: f, params: lift)
        #expect(!l.isEmpty && l.allSatisfy { $0.kind == .push && $0.dirY < 0 })
        #expect(l.contains { $0.dirX != 0 })
        #expect(FaceReshape.strokes(for: f, params: FaceReshapeParams()).isEmpty)
    }
}
