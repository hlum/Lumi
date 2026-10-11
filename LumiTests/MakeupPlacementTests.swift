import CoreImage
import Foundation
import Testing
@testable import Lumi

struct MakeupPlacementTests {
    static func face() -> FaceInfo {
        let f = FaceReshapeTests.face()
        var lm = f.landmarks
        lm["innerLips"] = (0..<6).map { CGPoint(x: 0.5 + 0.04 * cos(Double($0)), y: 0.25 + 0.03 * sin(Double($0))) }
        return FaceInfo(box: f.box, landmarks: lm)
    }

    @Test func blushSitsUnderEachEyeInsideTheFace() {
        let f = Self.face(), box = MakeupRenderer.faceBox(f)
        let spots = MakeupRenderer.blushSpots(f, style: .round)
        #expect(spots.count == 2)
        let left = FaceReshape.center(FaceReshape.points(f, "leftEye"))!, right = FaceReshape.center(FaceReshape.points(f, "rightEye"))!
        #expect(spots[0].center.y > left.y && spots[1].center.y > right.y)     // below the eyes (y-down)
        #expect(spots[0].center.x < left.x && spots[1].center.x > right.x)     // nudged toward the ears
        #expect(spots.allSatisfy { box.contains($0.center) })
    }

    @Test func blushIsSymmetric() {
        let s = MakeupRenderer.blushSpots(Self.face(), style: .oval)
        #expect(abs((s[0].center.x + s[1].center.x) / 2 - 0.5) < 0.02)
        #expect(abs(s[0].center.y - s[1].center.y) < 0.01 && s[0].radius == s[1].radius)
    }

    @Test func stylesDifferInShape() {
        let r = MakeupRenderer.blushSpots(Self.face(), style: .round)[0], o = MakeupRenderer.blushSpots(Self.face(), style: .oval)[0], w = MakeupRenderer.blushSpots(Self.face(), style: .wide)[0]
        #expect(r.squash == 1 && o.squash < 1 && w.radius > o.radius)
    }

    @Test func noEyesMeansNoBlush() {
        #expect(MakeupRenderer.blushSpots(FaceInfo(box: CGRect(x: 0.2, y: 0.2, width: 0.3, height: 0.3), landmarks: [:]), style: .round).isEmpty)
    }

    @Test func lipMaskExcludesTheOpenMouth() throws {
        let m = try #require(MakeupRenderer.lipMask(Self.face(), size: CGSize(width: 400, height: 400)))
        let c = FaceReshape.center(FaceReshape.points(Self.face(), "outerLips"))!
        let lipX = Int((c.x + 0.8 * 0.1 * 0.4) * 400), lipY = Int((1 - c.y) * 400)
        let inner = GeometryTests.rgb(m, x: Int(c.x * 400), y: lipY)[0]
        #expect(inner < 60)                                                  // inside the inner polygon: not painted
        #expect(GeometryTests.rgb(m, x: 5, y: 5)[0] < 20)
        _ = lipX
    }

    @Test func lipMaskNeedsLandmarks() {
        #expect(MakeupRenderer.lipMask(FaceInfo(box: .zero, landmarks: [:]), size: CGSize(width: 10, height: 10)) == nil)
        #expect(MakeupRenderer.lipMask(Self.face(), size: .zero) == nil)
    }

    @Test func lipstickTintsLipsRedderAndLeavesBackgroundAlone() {
        let img = RendererTests.solid(0.5, size: 400)
        var p = MakeupParams(); p.lipOpacity = 1; p.lipFinish = .matte
        let out = MakeupRenderer.apply(p, to: img, face: Self.face())
        let outer = FaceReshape.points(Self.face(), "outerLips")
        // a point on the lip ring, outside the inner polygon
        let ring = outer[0]
        let px = GeometryTests.rgb(out, x: Int(ring.x * 400), y: Int((1 - ring.y) * 400))
        #expect(px[0] > px[2])
        #expect(GeometryTests.rgb(out, x: 5, y: 5) == GeometryTests.rgb(img, x: 5, y: 5))
    }

    @Test func blushChangesCheeksOnly() {
        let img = RendererTests.solid(0.5, size: 400)
        var p = MakeupParams(); p.blushOpacity = 1
        let out = MakeupRenderer.apply(p, to: img, face: Self.face())
        let s = MakeupRenderer.blushSpots(Self.face(), style: .round)[0]
        let at = GeometryTests.rgb(out, x: Int(s.center.x * 400), y: Int((1 - s.center.y) * 400))
        #expect(at != GeometryTests.rgb(img, x: 0, y: 0) && at[0] > at[2])
        #expect(GeometryTests.rgb(out, x: 395, y: 395) == GeometryTests.rgb(img, x: 395, y: 395))
    }

    @Test func zeroOpacityIsIdentity() {
        let img = RendererTests.solid(0.5, size: 64)
        #expect(MakeupParams().isIdentity)
        #expect(RendererTests.pixel(MakeupRenderer.apply(MakeupParams(), to: img, face: Self.face())) == RendererTests.pixel(img))
    }

    @Test func allFinishesAndOmbreKeepExtent() {
        let img = RendererTests.solid(0.5, size: 128)
        for f in [MakeupParams.Finish.matte, .satin, .gloss] { for o in [0.0, 0.7] {
            var p = MakeupParams(); p.lipOpacity = 0.8; p.lipFinish = f; p.ombre = o; p.blushOpacity = 0.5
            #expect(MakeupRenderer.apply(p, to: img, face: Self.face()).extent == img.extent)
        } }
    }

    @Test func paramsRoundTrip() throws {
        var p = MakeupParams(); p.lipOpacity = 0.4; p.blushStyle = .wide
        #expect(try JSONDecoder().decode(MakeupParams.self, from: JSONEncoder().encode(p)) == p)
    }
}
