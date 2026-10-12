import CoreGraphics
import CoreImage
import Testing
@testable import Lumi

struct MLSWarpTests {
    static func offset(_ f: DisplacementField, _ x: Double, _ y: Double) -> (Double, Double) { let o = f.offset(x: Float(x), y: Float(y)); return (Double(o.0), Double(o.1)) }

    @Test func pinsOnlyGiveNoMovement() {
        #expect(MLSWarp.field(MLSWarp.border() + [.pin(CGPoint(x: 0.5, y: 0.5))], aspect: 1, cols: 33).isIdentity)
    }

    @Test func aHandleLandsOnItsTarget() {
        // move the picture at (0.5, 0.5) to (0.55, 0.5): the output at (0.55, 0.5) must sample the source at (0.5, 0.5)
        let f = MLSWarp.field(MLSWarp.border() + [WarpHandle(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.55, y: 0.5))], aspect: 1, cols: 101)
        let o = Self.offset(f, 0.55, 0.5)
        #expect(abs(o.0 + 0.05) < 0.003 && abs(o.1) < 0.003, "\(o)")
    }

    @Test func aGroupOfHandlesMovesRigidlyAndPinsHoldTheRest() {
        let cluster = [CGPoint(x: 0.45, y: 0.45), CGPoint(x: 0.55, y: 0.45), CGPoint(x: 0.5, y: 0.55)]
        let moved = cluster.map { WarpHandle(from: $0, to: CGPoint(x: $0.x, y: $0.y - 0.04)) }
        let f = MLSWarp.field(moved + MLSWarp.ring(around: CGPoint(x: 0.5, y: 0.5), radius: 0.3, aspect: 1) + MLSWarp.border(), aspect: 1, cols: 97)
        let inside = Self.offset(f, 0.5, 0.46)
        #expect(abs(inside.1 - 0.04) < 0.006 && abs(inside.0) < 0.004, "inside \(inside)")      // shifted up as a block
        let outside = Self.offset(f, 0.1, 0.1)
        #expect(abs(outside.0) < 0.003 && abs(outside.1) < 0.003, "outside \(outside)")          // beyond the pins: still
    }

    @Test func distancesAreMeasuredInPixels() {
        // on a wide picture a pin at the same normalized x-distance is far in pixels, so it holds less
        let h = [WarpHandle(from: CGPoint(x: 0.5, y: 0.5), to: CGPoint(x: 0.5, y: 0.52))] + MLSWarp.border()
        let wide = MLSWarp.field(h, aspect: 2, cols: 97), square = MLSWarp.field(h, aspect: 1, cols: 97)
        #expect(wide.rows < square.rows)
    }

    @Test func fieldsAdd() {
        var a = DisplacementField(cols: 3, rows: 3), b = a
        a.dx[4] = 0.1; b.dx[4] = 0.05; b.dy[0] = 0.02
        let c = a.adding(b)
        #expect(abs(c.dx[4] - 0.15) < 1e-6 && c.dy[0] == 0.02)
    }

    @Test func solvesAPreviewGridQuickly() {
        var hs = MLSWarp.border() + MLSWarp.ring(around: CGPoint(x: 0.5, y: 0.5), radius: 0.35, aspect: 0.75)
        for i in 0..<60 { let t = Double(i) / 60 * .pi; hs.append(WarpHandle(from: CGPoint(x: 0.5 + 0.2 * cos(t), y: 0.5 + 0.25 * sin(t)), to: CGPoint(x: 0.5 + 0.18 * cos(t), y: 0.5 + 0.25 * sin(t)))) }
        let t0 = Date()
        _ = MLSWarp.field(hs, aspect: 0.75)
        #expect(Date().timeIntervalSince(t0) < 0.25, "took \(Date().timeIntervalSince(t0))")
    }
}

struct FaceHandleTests {
    @Test func jawPullsTheLowerOutlineInAndPinsTheFeatures() {
        var r = FaceReshapeParams(); r.jawSlim = 1
        let face = FaceReshapeTests.face()
        let hs = FaceHandles.handles(for: face, reshape: r, shape: FeatureShape(), ratio: FaceRatio(), aspect: 1)
        let contour = FaceReshape.points(face, "faceContour")
        let mid = (contour.map(\.x).min()! + contour.map(\.x).max()!) / 2
        let lowest = contour.max { $0.y < $1.y }!
        let moving = hs.filter { $0.from != $0.to }
        #expect(!moving.isEmpty && moving.allSatisfy { abs($0.to.x - mid) <= abs($0.from.x - mid) + 1e-9 })   // only ever toward the middle
        #expect(hs.contains { $0.from == lowest })
        for p in FaceReshape.points(face, "outerLips") { #expect(hs.contains { $0.from == p && $0.to == p }) }      // lips held
    }

    @Test func eyeSizeScalesTheEyeAboutItsCentre() {
        var r = FaceReshapeParams(); r.eyeSize = 1
        let face = FaceReshapeTests.face()
        let eye = FaceReshape.points(face, "leftEye"), c = FaceReshape.center(eye)!
        let hs = FaceHandles.handles(for: face, reshape: r, shape: FeatureShape(), ratio: FaceRatio(), aspect: 1)
        for p in eye { let h = hs.first { $0.from == p }!; #expect(hypot(h.to.x - c.x, h.to.y - c.y) > hypot(p.x - c.x, p.y - c.y)) }
    }

    @Test func nothingSetMeansNoHandles() {
        #expect(FaceHandles.handles(for: FaceReshapeTests.face(), reshape: FaceReshapeParams(), shape: FeatureShape(), ratio: FaceRatio(), aspect: 1).isEmpty)
    }
}
