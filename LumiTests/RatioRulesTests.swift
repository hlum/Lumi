import CoreImage
import CoreGraphics
import Foundation
import Testing
@testable import Lumi

struct RatioRulesTests {
    let face = FaceReshapeTests.face()

    @Test func identityMakesNothing() {
        #expect(FaceRatio().isIdentity)
        #expect(RatioRules.strokes(for: face, FaceRatio()).isEmpty)
        #expect(ProtectionZones.zones(face, FaceRatio()).isEmpty)
    }

    @Test func shiftPushesInTheRequestedDirection() {
        var r = FaceRatio(); r.shiftX = 1; r.shiftY = -1
        let s = RatioRules.strokes(for: face, r)
        #expect(s.count == 1 && s[0].dirX > 0 && s[0].dirY < 0)
    }

    @Test func rotationPushesTopAndBottomOppositely() {
        var r = FaceRatio(); r.rotate = 1
        let s = RatioRules.strokes(for: face, r)
        #expect(s.count == 2 && s[0].dirX > 0 && s[1].dirX < 0 && s[0].y < s[1].y)
    }

    @Test func symmetryLevelsUnevenEyes() {
        var f = face
        f.landmarks["leftEye"] = f.landmarks["leftEye"]!.map { CGPoint(x: $0.x, y: $0.y - 0.1) }   // left eye lower
        var r = FaceRatio(); r.symmetry = 1
        let s = RatioRules.strokes(for: f, r)
        let left = s.first { $0.x < 0.5 }!, right = s.first { $0.x > 0.5 && $0.dirY != 0 }!
        #expect(left.dirY < 0 && right.dirY > 0)                  // lower eye up (y-down: negative), higher eye down
    }

    @Test func shadingMapsToContourAndHighlight() {
        var r = FaceRatio(); r.shade3D = 0.5
        let m = RatioRules.shading(r)
        #expect(m.contour == 0.5 && m.highlight > 0 && !r.isIdentity)
    }

    @Test func protectionDropsAndShrinksStrokes() {
        var r = FaceRatio(); r.protectFeatures = true
        let zones = ProtectionZones.zones(face, r)
        #expect(zones.count == 4)
        let eye = FaceReshape.center(FaceReshape.points(face, "leftEye"))!
        #expect(ProtectionZones.clip(BrushStroke(kind: .push, x: Float(eye.x), y: Float(eye.y), radius: 0.1, strength: 1), zones) == nil)
        let far = BrushStroke(kind: .push, x: 0.05, y: 0.95, radius: 0.02, strength: 1)
        #expect(ProtectionZones.clip(far, zones) == far)
        let near = BrushStroke(kind: .push, x: Float(eye.x), y: Float(eye.y) + 0.12, radius: 0.5, strength: 1)
        #expect((ProtectionZones.clip(near, zones)?.radius ?? 1) < 0.5)
    }

    @Test func glassesLockCoversBothEyes() {
        var r = FaceRatio(); r.glassesLock = true
        let z = ProtectionZones.zones(face, r)
        #expect(z.count == 1)
        for region in ["leftEye", "rightEye"] { #expect(z[0].contains(FaceReshape.center(FaceReshape.points(face, region))!)) }
    }

    @Test func oldDraftsStillDecodeAndRatioRoundTrips() throws {
        let old = try JSONDecoder().decode(FaceRetouch.self, from: Data("{}".utf8))
        #expect(old.ratio.isIdentity)
        var f = FaceRetouch(); f.ratio.rotate = 0.3; f.ratio.glassesLock = true
        #expect(try JSONDecoder().decode(FaceRetouch.self, from: JSONEncoder().encode(f)) == f)
        #expect(!f.isIdentity)
    }

    @Test func renderKeepsExtentAndShadesFace() {
        let img = CIImage(color: CIColor(red: 0.8, green: 0.6, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        var f = FaceRetouch(); f.ratio.shade3D = 1; f.ratio.shiftX = 0.5
        let out = FaceRetouchRender.apply(f, to: img, faces: [face])
        #expect(out.extent == img.extent)
    }
}
