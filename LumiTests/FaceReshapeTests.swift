import CoreGraphics
import Foundation
import Testing
@testable import Lumi

struct FaceReshapeTests {
    /// A synthetic face filling a 0.4x0.5 box. Landmarks are box-relative (Vision convention, y up).
    static func face() -> FaceInfo {
        var contour: [CGPoint] = []
        for i in 0..<9 {
            let t = Double(i) / 8 * Double.pi          // left ear, around the chin, right ear
            contour.append(CGPoint(x: 0.5 - 0.5 * cos(t), y: 0.8 - 0.8 * sin(t)))   // chin at y = 0 (bottom)
        }
        func ring(_ cx: Double, _ cy: Double, _ r: Double) -> [CGPoint] { (0..<6).map { CGPoint(x: cx + r * cos(Double($0)), y: cy + r * sin(Double($0))) } }
        return FaceInfo(box: CGRect(x: 0.3, y: 0.25, width: 0.4, height: 0.5), landmarks: [
            "faceContour": contour, "leftEye": ring(0.3, 0.6, 0.06), "rightEye": ring(0.7, 0.6, 0.06),
            "nose": ring(0.5, 0.45, 0.07), "outerLips": ring(0.5, 0.25, 0.1),
        ])
    }

    @Test func identityParamsMakeNoStrokes() { #expect(FaceReshape.strokes(for: Self.face(), params: FaceReshapeParams()).isEmpty) }

    @Test func pointsAreConvertedToImageSpaceYDown() {
        let p = FaceReshape.points(Self.face(), "leftEye")
        let c = FaceReshape.center(p)!
        #expect(abs(c.x - (0.3 + 0.3 * 0.4)) < 0.01)                    // 0.3 of the box width
        #expect(abs(c.y - (1 - (0.25 + 0.6 * 0.5))) < 0.01)              // flipped to y-down
        #expect(FaceReshape.points(Self.face(), "nothing").isEmpty && FaceReshape.center([]) == nil && FaceReshape.width([]) == 0)
    }

    @Test func jawSlimPushesLowerContourTowardTheMidline() {
        var prm = FaceReshapeParams(); prm.jawSlim = 1
        let s = FaceReshape.strokes(for: Self.face(), params: prm)
        #expect(!s.isEmpty && s.allSatisfy { $0.kind == .push && $0.dirY == 0 })
        #expect(s.contains { $0.x < 0.5 && $0.dirX > 0 } && s.contains { $0.x > 0.5 && $0.dirX < 0 })
        // upper face is left alone: no stroke above the face's mid-height
        let boxTopY = 1 - (0.25 + 0.5 * 0.8)
        #expect(s.allSatisfy { Double($0.y) > boxTopY })
    }

    @Test func negativeJawSlimWidensInstead() {
        var a = FaceReshapeParams(), b = FaceReshapeParams(); a.jawSlim = 0.5; b.jawSlim = -0.5
        let sa = FaceReshape.strokes(for: Self.face(), params: a), sb = FaceReshape.strokes(for: Self.face(), params: b)
        #expect(zip(sa, sb).allSatisfy { $0.dirX == -$1.dirX })
    }

    @Test func strengthScalesWithTheSlider() {
        var a = FaceReshapeParams(), b = FaceReshapeParams(); a.jawSlim = 0.25; b.jawSlim = 0.5
        let da = FaceReshape.strokes(for: Self.face(), params: a)[0].dirX, db = FaceReshape.strokes(for: Self.face(), params: b)[0].dirX
        #expect(abs(db / da - 2) < 1e-4)
    }

    @Test func valuesAreClamped() {
        var wild = FaceReshapeParams(); wild.jawSlim = 50
        var one = FaceReshapeParams(); one.jawSlim = 1
        #expect(FaceReshape.strokes(for: Self.face(), params: wild) == FaceReshape.strokes(for: Self.face(), params: one))
    }

    @Test func eyeSizeBloatsBothEyes() {
        var p = FaceReshapeParams(); p.eyeSize = 0.8
        let s = FaceReshape.strokes(for: Self.face(), params: p)
        #expect(s.count == 2 && s.allSatisfy { $0.kind == .bloat && $0.strength > 0 })
        #expect(s[0].x < 0.5 && s[1].x > 0.5)
        p.eyeSize = -0.8
        #expect(FaceReshape.strokes(for: Self.face(), params: p).allSatisfy { $0.kind == .pinch })
    }

    @Test func chinLengthPushesVertically() {
        var p = FaceReshapeParams(); p.chinLength = 1
        let s = FaceReshape.strokes(for: Self.face(), params: p)
        #expect(s.count == 1 && s[0].dirY > 0 && s[0].dirX == 0)
        p.chinLength = -1
        #expect(FaceReshape.strokes(for: Self.face(), params: p)[0].dirY < 0)
    }

    @Test func noseAndMouthUseTheirOwnRegions() {
        var p = FaceReshapeParams(); p.noseSlim = 1
        let n = FaceReshape.strokes(for: Self.face(), params: p)
        #expect(n.count == 1 && n[0].kind == .pinch)
        p = FaceReshapeParams(); p.mouthSize = 1
        let m = FaceReshape.strokes(for: Self.face(), params: p)
        #expect(m.count == 1 && m[0].kind == .bloat && m[0].y > n[0].y)     // mouth sits below the nose (y-down)
    }

    @Test func missingLandmarksAreSkippedNotCrashed() {
        var p = FaceReshapeParams(); p.eyeSize = 1; p.noseSlim = 1; p.mouthSize = 1; p.jawSlim = 1; p.chinLength = 1; p.faceWidth = 1
        #expect(FaceReshape.strokes(for: FaceInfo(box: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), landmarks: [:]), params: p).isEmpty)
    }

    @Test func multipleFacesAllGetStrokes() {
        var p = FaceReshapeParams(); p.eyeSize = 1
        #expect(FaceReshape.strokes(for: [Self.face(), Self.face()], params: p).count == 4)
        #expect(FaceReshape.strokes(for: [], params: p).isEmpty)
    }

    @Test func strokesActuallyWarpTheImage() {
        var p = FaceReshapeParams(); p.eyeSize = 1
        var w = WarpEdit()
        FaceReshape.strokes(for: Self.face(), params: p).forEach { w.add($0) }
        #expect(!w.field.isIdentity)
        let img = MeshWarpRendererTests.ramp()
        #expect(MeshWarpRenderer.apply(w.field, to: img).extent == img.extent)
    }

    @Test func paramsRoundTripThroughJSON() throws {
        var p = FaceReshapeParams(); p.eyeSize = 0.3; p.jawSlim = -0.2
        #expect(try JSONDecoder().decode(FaceReshapeParams.self, from: JSONEncoder().encode(p)) == p)
    }
}
