import CoreImage
import Foundation
import Testing
@testable import Lumi

struct EyeMakeupTests {
    static let size = CGSize(width: 400, height: 400)
    static func face() -> FaceInfo {
        var f = MakeupPlacementTests.face()
        f.box = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6)
        f.landmarks["leftEyebrow"] = (0..<5).map { CGPoint(x: 0.2 + 0.08 * Double($0), y: 0.7 + (($0 == 2) ? 0.04 : 0)) }       // box-relative, y up
        f.landmarks["rightEyebrow"] = (0..<5).map { CGPoint(x: 0.6 + 0.08 * Double($0), y: 0.7 + (($0 == 2) ? 0.04 : 0)) }
        return f
    }
    static func photo() -> CIImage { CIImage(color: CIColor(red: 0.8, green: 0.65, blue: 0.55)).cropped(to: CGRect(origin: .zero, size: size)) }
    static func lum(_ i: CIImage, _ p: CGPoint) -> Int { let c = GeometryTests.rgb(i, x: Int(p.x * 400), y: Int((1 - p.y) * 400)); return Int(c[0]) + Int(c[1]) + Int(c[2]) }

    @Test func defaultsAreIdentity() {
        #expect(EyeMakeup().isIdentity)
        #expect(EyeMakeupRenderer.apply(EyeMakeup(), to: Self.photo(), face: Self.face()).extent == Self.photo().extent)
        var b = EyeMakeup(); b.browShape = .arched; #expect(!b.isIdentity)
    }

    @Test func upperLidIsTheTopHalfLeftToRight() {
        let eye = FaceReshape.points(Self.face(), "leftEye")
        let lid = EyeMakeupRenderer.upperLid(eye)
        let c = FaceReshape.center(eye)!
        #expect(lid.count >= 2 && lid.allSatisfy { $0.y <= c.y + 0.001 } && zip(lid, lid.dropFirst()).allSatisfy { $0.x <= $1.x })
    }

    @Test func shadowDarkensAboveTheEyeNotOnIt() throws {
        var m = EyeMakeup(); m.left.shadow = 1
        let out = EyeMakeupRenderer.apply(m, to: Self.photo(), face: Self.face())
        let eye = FaceReshape.points(Self.face(), "leftEye"), c = FaceReshape.center(eye)!, w = FaceReshape.width(eye)
        let lid = EyeMakeupRenderer.upperLid(eye), mid = lid[lid.count / 2]
        let above = CGPoint(x: mid.x, y: mid.y - w * 0.25)
        #expect(Self.lum(out, above) < Self.lum(Self.photo(), above) - 25)
        #expect(GeometryTests.near(GeometryTests.rgb(out, x: Int(c.x * 400), y: Int((1 - c.y) * 400)), GeometryTests.rgb(Self.photo(), x: Int(c.x * 400), y: Int((1 - c.y) * 400)), tolerance: 6))      // the eye itself is clear
    }

    @Test func leftAndRightAreIndependent() {
        var m = EyeMakeup(); m.left.shadow = 1                                           // only the left eye
        let out = EyeMakeupRenderer.apply(m, to: Self.photo(), face: Self.face())
        func probe(_ region: String) -> CGPoint {
            let eye = FaceReshape.points(Self.face(), region), lid = EyeMakeupRenderer.upperLid(eye), mid = lid[lid.count / 2]
            return CGPoint(x: mid.x, y: mid.y - FaceReshape.width(eye) * 0.25)
        }
        #expect(Self.lum(out, probe("leftEye")) < Self.lum(Self.photo(), probe("leftEye")) - 25)
        #expect(abs(Self.lum(out, probe("rightEye")) - Self.lum(Self.photo(), probe("rightEye"))) < 8)
        m.setBoth { $0.shadow = 1 }
        #expect(m.left.shadow == 1 && m.right.shadow == 1)
    }

    @Test func linerDrawsADarkLineAlongTheLidAndLashesAreHeavier() throws {
        let eye = FaceReshape.points(Self.face(), "leftEye")
        let lid = EyeMakeupRenderer.upperLid(eye)
        let mid = lid[lid.count / 2]
        var m = EyeMakeup(); m.left.liner = 1
        let out = EyeMakeupRenderer.apply(m, to: Self.photo(), face: Self.face())
        #expect(Self.lum(out, mid) < Self.lum(Self.photo(), mid) - 150)
        let thin = try #require(EyeMakeupRenderer.linerMask(eye, size: Self.size, thickness: 0.1, wing: false)), thick = try #require(EyeMakeupRenderer.linerMask(eye, size: Self.size, thickness: 1, wing: false))
        func area(_ i: CIImage) -> Int { var px = [UInt8](repeating: 0, count: 400 * 400); CIContext().render(i, toBitmap: &px, rowBytes: 400, bounds: i.extent, format: .L8, colorSpace: nil); return px.filter { $0 > 128 }.count }
        #expect(area(thick) > area(thin))
        var l = EyeMakeup(); l.left.lashes = 1
        #expect(Self.lum(EyeMakeupRenderer.apply(l, to: Self.photo(), face: Self.face()), mid) < Self.lum(Self.photo(), mid) - 100)
    }

    @Test func browColorTintsTheBrowOnly() {
        var m = EyeMakeup(); m.browOpacity = 1; m.browColor = RGBA(r: 0.1, g: 0.05, b: 0.02, a: 1)
        let out = EyeMakeupRenderer.apply(m, to: Self.photo(), face: Self.face())
        let brow = FaceReshape.center(FaceReshape.points(Self.face(), "leftEyebrow"))!
        #expect(Self.lum(out, brow) < Self.lum(Self.photo(), brow) - 20)
        #expect(GeometryTests.near(GeometryTests.rgb(out, x: 5, y: 5), GeometryTests.rgb(Self.photo(), x: 5, y: 5)))
    }

    @Test func browShapesMakeDifferentStrokesAndNaturalMakesNone() {
        let f = Self.face()
        #expect(EyeMakeupRenderer.browStrokes(f, shape: .natural, height: 0).isEmpty)
        let arched = EyeMakeupRenderer.browStrokes(f, shape: .arched, height: 0), straight = EyeMakeupRenderer.browStrokes(f, shape: .straight, height: 0), soft = EyeMakeupRenderer.browStrokes(f, shape: .soft, height: 0)
        #expect(arched.count == 2 && arched.allSatisfy { $0.dirY < 0 })                        // peak goes up
        #expect(straight.allSatisfy { $0.dirY > 0 } && soft.count == 4)
        let up = EyeMakeupRenderer.browStrokes(f, shape: .natural, height: 1), down = EyeMakeupRenderer.browStrokes(f, shape: .natural, height: -1)
        #expect(up.allSatisfy { $0.dirY < 0 } && down.allSatisfy { $0.dirY > 0 })
        #expect(EyeMakeupRenderer.browStrokes(FaceInfo(box: .zero, landmarks: [:]), shape: .arched, height: 1).isEmpty)
    }

    @Test func eyeMakeupGoesThroughTheFaceOperationAndOldDraftsStillOpen() throws {
        var r = FaceRetouch(); r.eyes.left.shadow = 0.5; r.eyes.browShape = .arched
        #expect(!r.isIdentity)
        #expect(try JSONDecoder().decode(FaceRetouch.self, from: JSONEncoder().encode(r)) == r)
        let old = try JSONDecoder().decode(FaceRetouch.self, from: Data(#"{"skin":{"smooth":0.3,"texture":0.5,"whiten":0,"rosy":0,"tan":0}}"#.utf8))
        #expect(old.skin.smooth == 0.3 && old.eyes.isIdentity)
        let out = FaceRetouchRender.apply(r, to: Self.photo(), faces: [Self.face()])
        #expect(out.extent == Self.photo().extent)
    }

    @Test func missingLandmarksAreSafe() {
        var m = EyeMakeup(); m.setBoth { $0.shadow = 1; $0.liner = 1; $0.lashes = 1 }; m.browOpacity = 1
        #expect(EyeMakeupRenderer.apply(m, to: Self.photo(), face: FaceInfo(box: CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5), landmarks: [:])).extent == Self.photo().extent)
    }
}
