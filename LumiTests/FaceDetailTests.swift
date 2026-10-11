import CoreImage
import Foundation
import Testing
@testable import Lumi

struct FaceDetailTests {
    static let size = CGSize(width: 400, height: 400)
    static var extent: CGRect { CGRect(origin: .zero, size: size) }

    /// Landmarks are image-relative here: a 0.5-wide face box centered in the picture.
    static func face() -> FaceInfo {
        var f = MakeupPlacementTests.face()
        f.box = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6)
        return f
    }
    static func skinTone() -> CIImage { CIImage(color: CIColor(red: 0.75, green: 0.55, blue: 0.45)).cropped(to: extent) }
    static func px(_ i: CIImage, _ p: CGPoint) -> [UInt8] { GeometryTests.rgb(i, x: Int(p.x * 400), y: Int((1 - p.y) * 400)) }
    static func lum(_ c: [UInt8]) -> Int { (Int(c[0]) * 3 + Int(c[1]) * 6 + Int(c[2])) / 10 }

    @Test func identityParamsLeaveTheImage() {
        #expect(FaceDetailParams().isIdentity)
        #expect(GeometryTests.near(Self.px(FaceDetailOps.apply(FaceDetailParams(), to: Self.skinTone(), face: Self.face()), CGPoint(x: 0.5, y: 0.5)), Self.px(Self.skinTone(), CGPoint(x: 0.5, y: 0.5))))
    }

    @Test func flashBrightensTheFaceButNotTheBackground() {
        var p = FaceDetailParams(); p.flash = 1
        let out = FaceDetailOps.apply(p, to: Self.skinTone(), face: Self.face())
        let base = Self.skinTone()
        let cheek = CGPoint(x: 0.5, y: 0.45)          // inside the face, away from features? use the forehead-ish area
        #expect(Self.lum(Self.px(out, CGPoint(x: 0.5, y: 0.7))) > Self.lum(Self.px(base, CGPoint(x: 0.5, y: 0.7))) + 8 || Self.lum(Self.px(out, cheek)) > Self.lum(Self.px(base, cheek)) + 8)
        #expect(GeometryTests.near(GeometryTests.rgb(out, x: 5, y: 5), GeometryTests.rgb(base, x: 5, y: 5)))             // far corner unchanged
    }

    @Test func flashStrengthScales() {
        var a = FaceDetailParams(), b = FaceDetailParams(); a.flash = 0.3; b.flash = 1
        let pt = CGPoint(x: 0.5, y: 0.7)
        #expect(Self.lum(Self.px(FaceDetailOps.apply(b, to: Self.skinTone(), face: Self.face()), pt)) > Self.lum(Self.px(FaceDetailOps.apply(a, to: Self.skinTone(), face: Self.face()), pt)))
    }

    @Test func underEyeMaskSitsBelowTheEyesOnly() throws {
        let m = try #require(FaceDetailOps.underEyeMask(Self.face(), size: Self.size))
        let eye = try #require(FaceReshape.center(FaceReshape.points(Self.face(), "leftEye")))
        let w = FaceReshape.width(FaceReshape.points(Self.face(), "leftEye"))
        #expect(GeometryTests.rgb(m, x: Int(eye.x * 400), y: Int((1 - (eye.y + w * 0.4)) * 400))[0] > 120)         // under the eye (y-down +)
        #expect(GeometryTests.rgb(m, x: Int(eye.x * 400), y: Int((1 - (eye.y - w * 1.5)) * 400))[0] < 40)          // well above it
    }

    @Test func underEyeLightensOnlyThatRegion() {
        var p = FaceDetailParams(); p.underEye = 1
        let base = CIImage(color: CIColor(red: 0.45, green: 0.35, blue: 0.3)).cropped(to: Self.extent)
        let out = FaceDetailOps.apply(p, to: base, face: Self.face())
        let eye = FaceReshape.center(FaceReshape.points(Self.face(), "leftEye"))!, w = FaceReshape.width(FaceReshape.points(Self.face(), "leftEye"))
        let under = CGPoint(x: eye.x, y: eye.y + w * 0.4)
        #expect(Self.lum(Self.px(out, under)) > Self.lum(Self.px(base, under)) + 6)
        #expect(GeometryTests.near(GeometryTests.rgb(out, x: 5, y: 5), GeometryTests.rgb(base, x: 5, y: 5)))
    }

    @Test func teethWhiteningDesaturatesInsideTheMouthOpeningOnly() throws {
        let yellowish = CIImage(color: CIColor(red: 0.9, green: 0.8, blue: 0.5)).cropped(to: Self.extent)
        var p = FaceDetailParams(); p.teethWhiten = 1
        let out = FaceDetailOps.apply(p, to: yellowish, face: Self.face())
        let mouth = try #require(FaceReshape.center(FaceReshape.points(Self.face(), "innerLips")))
        let inside = Self.px(out, mouth), before = Self.px(yellowish, mouth)
        #expect(Int(inside[0]) - Int(inside[2]) < Int(before[0]) - Int(before[2]) - 20)                      // less yellow
        #expect(GeometryTests.near(GeometryTests.rgb(out, x: 5, y: 5), GeometryTests.rgb(yellowish, x: 5, y: 5)))
    }

    @Test func teethMaskNeedsAMouthOpening() {
        var f = Self.face(); f.landmarks["innerLips"] = nil
        #expect(FaceDetailOps.teethMask(f, size: Self.size) == nil)
        var p = FaceDetailParams(); p.teethWhiten = 1
        #expect(FaceDetailOps.apply(p, to: Self.skinTone(), face: f).extent == Self.extent)                    // no crash, nothing to whiten
    }

    @Test func eyeBrightenAndWrinkleSoftenKeepTheExtent() {
        var p = FaceDetailParams(); p.eyeBright = 1; p.wrinkles = 1
        let noisy = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: Self.extent)
        let out = FaceDetailOps.apply(p, to: noisy, face: Self.face())
        #expect(out.extent == Self.extent)
        #expect(FaceDetailOps.wrinkleMask(Self.face(), size: Self.size) != nil && FaceDetailOps.eyeMask(Self.face(), size: Self.size) != nil)
    }

    @Test func facesWithoutLandmarksAreSafe() {
        var p = FaceDetailParams(); p.flash = 1; p.underEye = 1; p.wrinkles = 1; p.teethWhiten = 1; p.eyeBright = 1
        let bare = FaceInfo(box: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5), landmarks: [:])
        #expect(FaceDetailOps.apply(p, to: Self.skinTone(), face: bare).extent == Self.extent)
    }

    @Test func paramsRoundTrip() throws {
        var p = FaceDetailParams(); p.flash = 0.4; p.teethWhiten = 0.7
        #expect(try JSONDecoder().decode(FaceDetailParams.self, from: JSONEncoder().encode(p)) == p)
    }
}
