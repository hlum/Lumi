import CoreGraphics
import CoreImage
import Foundation
import Testing
@testable import Lumi

struct BodyReshapeTests {
    /// A standing figure, Vision convention (y up): shoulders y=0.8, hips y=0.5, knees 0.3, ankles 0.1, neck 0.85.
    static func pose() -> [String: CGPoint] {
        [
            "neck_1_joint": CGPoint(x: 0.5, y: 0.85),
            "left_shoulder_1_joint": CGPoint(x: 0.4, y: 0.8), "right_shoulder_1_joint": CGPoint(x: 0.6, y: 0.8),
            "left_elbow_1_joint": CGPoint(x: 0.35, y: 0.65), "right_elbow_1_joint": CGPoint(x: 0.65, y: 0.65),
            "left_hip_1_joint": CGPoint(x: 0.44, y: 0.5), "right_hip_1_joint": CGPoint(x: 0.56, y: 0.5),
            "left_knee_1_joint": CGPoint(x: 0.44, y: 0.3), "right_knee_1_joint": CGPoint(x: 0.56, y: 0.3),
            "left_ankle_1_joint": CGPoint(x: 0.44, y: 0.1), "right_ankle_1_joint": CGPoint(x: 0.56, y: 0.1),
        ]
    }

    @Test func identityMakesNoStrokes() { #expect(BodyReshape.strokes(pose: Self.pose(), params: BodyReshapeParams()).isEmpty) }

    @Test func jointsAreFlippedToYDown() { #expect(BodyReshape.joints(Self.pose())["neck_1_joint"]?.y == 1 - 0.85) }

    @Test func waistSqueezesBothSidesTowardTheCenter() {
        var p = BodyReshapeParams(); p.waist = 1
        let s = BodyReshape.strokes(pose: Self.pose(), params: p)
        #expect(s.count == 2 && s.allSatisfy { $0.kind == .push })
        let l = s.first { $0.x < 0.5 }!, r = s.first { $0.x > 0.5 }!
        #expect(l.dirX > 0 && r.dirX < 0)                                     // toward the midline
        #expect(l.y > Float(1 - 0.8) && l.y < Float(1 - 0.5))                  // between shoulders and hips
    }

    @Test func negativeWaistWidens() {
        var p = BodyReshapeParams(); p.waist = -1
        let s = BodyReshape.strokes(pose: Self.pose(), params: p)
        #expect(s.first { $0.x < 0.5 }!.dirX < 0)
    }

    @Test func shoulderPositiveWidensOutward() {
        var p = BodyReshapeParams(); p.shoulder = 1
        let s = BodyReshape.strokes(pose: Self.pose(), params: p)
        #expect(s.first { $0.x < 0.5 }!.dirX < 0 && s.first { $0.x > 0.5 }!.dirX > 0)
    }

    @Test func legLengthPushesDownAndScalesWithSlider() {
        var a = BodyReshapeParams(), b = BodyReshapeParams(); a.legLength = 0.25; b.legLength = 0.5
        let sa = BodyReshape.strokes(pose: Self.pose(), params: a), sb = BodyReshape.strokes(pose: Self.pose(), params: b)
        #expect(sa.count == 1 && sa[0].dirY > 0 && sa[0].dirX == 0)
        #expect(abs(sb[0].dirY / sa[0].dirY - 2) < 1e-4)
    }

    @Test func legSlimTouchesBothLegsAtThighAndShin() {
        var p = BodyReshapeParams(); p.legSlim = 1
        #expect(BodyReshape.strokes(pose: Self.pose(), params: p).count == 4)
    }

    @Test func armSlimNeedsElbowsAndPushesTowardTorso() {
        var p = BodyReshapeParams(); p.armSlim = 1
        let s = BodyReshape.strokes(pose: Self.pose(), params: p)
        #expect(s.count == 2)
        #expect(s.first { $0.x < 0.5 }!.dirX > 0 && s.first { $0.x > 0.5 }!.dirX < 0)
    }

    @Test func headSizeUsesBloatOrPinch() {
        var p = BodyReshapeParams(); p.headSize = 1
        #expect(BodyReshape.strokes(pose: Self.pose(), params: p).first?.kind == .bloat)
        p.headSize = -1
        #expect(BodyReshape.strokes(pose: Self.pose(), params: p).first?.kind == .pinch)
    }

    @Test func missingJointsAreSkippedNotCrashed() {
        var p = BodyReshapeParams(); p.waist = 1; p.legLength = 1; p.legSlim = 1; p.armSlim = 1; p.shoulder = 1; p.headSize = 1; p.hips = 1
        #expect(BodyReshape.strokes(pose: [:], params: p).isEmpty)
        #expect(BodyReshape.strokes(pose: ["neck_1_joint": CGPoint(x: 0.5, y: 0.5)], params: p).isEmpty)
    }

    @Test func valuesAreClampedAndMultiplePeopleAllGetStrokes() {
        var wild = BodyReshapeParams(); wild.waist = 50
        var one = BodyReshapeParams(); one.waist = 1
        #expect(BodyReshape.strokes(pose: Self.pose(), params: wild) == BodyReshape.strokes(pose: Self.pose(), params: one))
        #expect(BodyReshape.strokes(poses: [Self.pose(), Self.pose()], params: one).count == 4)
    }

    @Test func strokesWarpAnImage() {
        var p = BodyReshapeParams(); p.waist = 1
        var w = WarpEdit(); BodyReshape.strokes(pose: Self.pose(), params: p).forEach { w.add($0) }
        #expect(!w.field.isIdentity)
    }
}

@Suite(.serialized)
struct ProtectedWarpTests {
    static let size = CGRect(x: 0, y: 0, width: 128, height: 128)
    /// Person = white band in the middle; background = gray. Squeezing it should leave a strip.
    static func scene() -> (image: CIImage, mask: CIImage) {
        let bg = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: size)
        let person = CGRect(x: 0.3, y: 0, width: 0.4, height: 1)
        let mask = MosaicOps.mask(rects: [person], extent: size)
        let img = CIImage(color: CIColor(red: 1, green: 0.2, blue: 0.2)).cropped(to: CGRect(x: 38, y: 0, width: 52, height: 128)).composited(over: bg)
        return (img, mask)
    }

    @Test func identityFieldReturnsTheImage() throws {
        let s = Self.scene()
        #expect(try ProtectedWarp.apply(DisplacementField(cols: 9, rows: 9), to: s.image, personMask: s.mask, inpainter: nil).extent == s.image.extent)
    }

    @Test func backgroundStaysPutAndShrinkingPersonLeavesAStripThatGetsFilled() throws {
        let s = Self.scene()
        var e = WarpEdit(cols: 17, rows: 17)
        // pull content from outside inward on the right edge of the person: it shrinks from the right
        e.add(BrushStroke(kind: .push, x: 0.7, y: 0.5, radius: 0.35, strength: 1, dirX: -0.12, dirY: 0))
        let out = try ProtectedWarp.apply(e.field, to: s.image, personMask: s.mask, inpainter: FakeInpainter())
        #expect(out.extent == s.image.extent)
        func close(_ x: Int) -> Bool { zip(GeometryTests.rgb(out, x: x, y: 64), GeometryTests.rgb(s.image, x: x, y: 64)).allSatisfy { abs(Int($0) - Int($1)) <= 2 } }
        #expect(close(4) && close(120))                                                            // far background untouched
        let hasGreen = (80...100).contains { GeometryTests.rgb(out, x: $0, y: 64)[1] > 200 && GeometryTests.rgb(out, x: $0, y: 64)[0] < 60 }
        #expect(hasGreen)                                                                          // the vacated strip went to the inpainter
    }

    @Test func withoutAnInpainterTheStripKeepsOriginalPixels() throws {
        let s = Self.scene()
        var e = WarpEdit(cols: 17, rows: 17)
        e.add(BrushStroke(kind: .push, x: 0.7, y: 0.5, radius: 0.35, strength: 1, dirX: -0.12, dirY: 0))
        #expect(try ProtectedWarp.apply(e.field, to: s.image, personMask: s.mask, inpainter: nil).extent == s.image.extent)
    }

    @Test func hasContentDetectsEmptyAndFilledMasks() {
        #expect(!ProtectedWarp.hasContent(CIImage(color: .black).cropped(to: Self.size)))
        #expect(ProtectedWarp.hasContent(CIImage(color: .white).cropped(to: Self.size)))
        #expect(!ProtectedWarp.hasContent(CIImage(color: .white).cropped(to: .zero)))
    }
}
