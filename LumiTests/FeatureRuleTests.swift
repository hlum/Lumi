import CoreGraphics
import Foundation
import Testing
@testable import Lumi

struct FeatureRuleTests {
    let face = FaceReshapeTests.face()
    func strokes(_ k: FeatureShape.Key, _ v: Double) -> [BrushStroke] { var p = FeatureShape(); p[k] = v; return FeatureRules.strokes(for: face, p) }

    @Test func identityMakesNothingAndEverySliderMakesSomething() {
        #expect(FeatureRules.strokes(for: face, FeatureShape()).isEmpty)
        for k in FeatureShape.Key.allCases {
            // the synthetic face has no eyebrows, so brow sliders have nothing to move on it
            if [.browSpacing, .browPeak, .browLift, .forehead].contains(k) { continue }
            #expect(!strokes(k, 1).isEmpty, "\(k)")
            #expect(strokes(k, 0).isEmpty)
        }
    }

    @Test func oppositeValuesPushOpposingWays() {
        for k in [FeatureShape.Key.eyeDistance, .eyeHeight, .mouthSmile, .noseLength, .vShape, .mouthWidth, .eyeLids] {
            let up = strokes(k, 1), down = strokes(k, -1)
            #expect(up.count == down.count, "\(k)")
            for (u, d) in zip(up, down) { #expect(abs(u.dirX + d.dirX) < 1e-6 && abs(u.dirY + d.dirY) < 1e-6, "\(k)") }
        }
    }

    @Test func eyeDistanceMovesTheEyesApartAndHeightMovesThemUp() {
        let apart = strokes(.eyeDistance, 1)
        #expect(apart.count == 2)
        let left = apart.min { $0.x < $1.x }!, right = apart.max { $0.x < $1.x }!
        #expect(left.dirX < 0 && right.dirX > 0)
        #expect(strokes(.eyeHeight, 1).allSatisfy { $0.dirY < 0 })
    }

    @Test func smileLiftsTheCornersAndWidthStretchesThem() {
        let smile = strokes(.mouthSmile, 1)
        #expect(smile.count == 2 && smile.allSatisfy { $0.dirY < 0 })
        let wide = strokes(.mouthWidth, 1)
        let l = wide.min { $0.x < $1.x }!, r = wide.max { $0.x < $1.x }!
        #expect(l.dirX < 0 && r.dirX > 0)
    }

    @Test func fullnessAndPoutAreBloatsAndTheyFlipToPinches() {
        #expect(strokes(.mouthFullness, 1).allSatisfy { $0.kind == .bloat } && strokes(.mouthFullness, -1).allSatisfy { $0.kind == .pinch })
        #expect(strokes(.noseTip, 1).allSatisfy { $0.kind == .pinch })       // + slims the tip
    }

    @Test func noseWingsPinchTowardTheCenter() {
        let w = strokes(.noseWings, 1)
        let l = w.min { $0.x < $1.x }!, r = w.max { $0.x < $1.x }!
        #expect(l.dirX > 0 && r.dirX < 0)
    }

    @Test func vShapeNarrowsOnlyTheLowerFaceTowardTheMiddle() {
        let v = strokes(.vShape, 1)
        let contour = FaceReshape.points(face, "faceContour"), hi = contour.map(\.y).min()!, lo = contour.map(\.y).max()!
        #expect(!v.isEmpty && v.allSatisfy { CGFloat($0.y) - hi >= (lo - hi) * 0.5 - 1e-6 })
        #expect(v.allSatisfy { ($0.x < 0.5 && $0.dirX > 0) || ($0.x >= 0.5 && $0.dirX < 0) })
    }

    @Test func valuesAreClampedAndDraftsRoundTrip() throws {
        var p = FeatureShape(); p[.eyeTilt] = 7; #expect(p.eyeTilt == 1)
        p[.noseBridge] = -0.4
        #expect(try JSONDecoder().decode(FeatureShape.self, from: JSONEncoder().encode(p)) == p)
        #expect(try JSONDecoder().decode(FeatureShape.self, from: Data("{}".utf8)).isIdentity)
        var f = FaceRetouch(); f.shape.mouthPout = 0.5
        let back = try JSONDecoder().decode(FaceRetouch.self, from: JSONEncoder().encode(f))
        #expect(!f.isIdentity && back == f)
        #expect(try JSONDecoder().decode(FaceRetouch.self, from: Data("{}".utf8)).shape.isIdentity)
    }
}
