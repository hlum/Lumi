import CoreImage
import Foundation
import Testing
@testable import Lumi

struct HairTests {
    static let size = CGSize(width: 200, height: 200)
    static var extent: CGRect { CGRect(origin: .zero, size: size) }

    /// Face box at the middle of the picture (Vision space: bottom-left origin).
    static func face() -> FaceInfo {
        var f = SkinTests.face()
        f.box = CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)
        return FaceInfo(box: f.box, landmarks: SkinTests.face().landmarks)
    }
    /// The whole picture counts as "person" so only the region logic is tested.
    static func everyone() -> CIImage { CIImage(color: .white).cropped(to: extent) }

    @Test func headRegionIsWiderAndHigherThanTheFace() {
        let face = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)         // y-down
        let h = HairMask.headRegion(face: face)
        #expect(h.width > face.width && h.minY < face.minY && h.contains(face.origin))
        #expect(abs(h.midX - face.midX) < 1e-9)
    }

    @Test func estimateFindsHairAboveAndBesideTheFaceButNotOnIt() {
        let m = HairMask.estimate(person: Self.everyone(), face: Self.face())
        #expect(m.extent == Self.extent)
        // face is the box x 70-130, y 70-130 (CI coords); above the forehead, still within the head region, should be "hair"
        #expect(GeometryTests.rgb(m, x: 100, y: 150)[0] > 150)             // above the face (CI y grows upward)
        #expect(GeometryTests.rgb(m, x: 100, y: 100)[0] < 100)             // on the face itself
        #expect(GeometryTests.rgb(m, x: 5, y: 5)[0] < 20)                  // far corner: outside the head region
    }

    @Test func nothingOutsideThePersonIsHair() {
        let personOnLeft = MosaicOps.mask(rects: [CGRect(x: 0, y: 0, width: 0.5, height: 1)], extent: Self.extent)
        let m = HairMask.estimate(person: personOnLeft, face: Self.face())
        #expect(GeometryTests.rgb(m, x: 150, y: 150)[0] < 20)              // right half is background
    }

    @Test func brushAddsAndRemoves() {
        let base = CIImage(color: .black).cropped(to: Self.extent)
        var add = MaskCanvas(width: 20, height: 20); add.fill(rect: CGRect(x: 0, y: 0, width: 10, height: 20))
        var rem = MaskCanvas(width: 20, height: 20); rem.fill(rect: CGRect(x: 0, y: 0, width: 20, height: 5))
        let r = HairMask.refine(base, add: add, remove: nil)
        #expect(GeometryTests.rgb(r, x: 20, y: 100)[0] > 200 && GeometryTests.rgb(r, x: 180, y: 100)[0] < 20)
        let both = HairMask.refine(r, add: nil, remove: rem)
        #expect(GeometryTests.rgb(both, x: 20, y: 20)[0] > 200)            // y 20 (low CI y) is mask-top rows? bottom rows kept
        #expect(HairMask.refine(base, add: nil, remove: nil).extent == Self.extent)
    }

    // MARK: recolor
    static func brown() -> CIImage { CIImage(color: CIColor(red: 0.35, green: 0.22, blue: 0.12)).cropped(to: extent) }

    @Test func recolorChangesHueInsideTheMaskOnly() {
        var p = HairColorParams(); p.color = RGBA(r: 0.2, g: 0.3, b: 1, a: 1); p.strength = 1
        let mask = MosaicOps.mask(rects: [CGRect(x: 0, y: 0, width: 0.5, height: 1)], extent: Self.extent)
        let out = HairOps.recolor(p, image: Self.brown(), mask: mask)
        let inside = GeometryTests.rgb(out, x: 20, y: 100), outside = GeometryTests.rgb(out, x: 180, y: 100)
        #expect(inside[2] > inside[0])                                     // turned bluish
        #expect(GeometryTests.near(outside, GeometryTests.rgb(Self.brown(), x: 180, y: 100)))
    }

    @Test func strengthBlendsAndZeroIsIdentity() {
        let all = CIImage(color: .white).cropped(to: Self.extent)
        var half = HairColorParams(); half.color = RGBA(r: 0.2, g: 0.3, b: 1, a: 1); half.strength = 0.5
        var full = half; full.strength = 1
        let h = GeometryTests.rgb(HairOps.recolor(half, image: Self.brown(), mask: all), x: 100, y: 100)
        let f = GeometryTests.rgb(HairOps.recolor(full, image: Self.brown(), mask: all), x: 100, y: 100)
        let base = GeometryTests.rgb(Self.brown(), x: 100, y: 100)
        #expect(Int(f[2]) - Int(f[0]) > Int(h[2]) - Int(h[0]) && Int(h[2]) - Int(h[0]) > Int(base[2]) - Int(base[0]))
        #expect(HairColorParams().isIdentity)
        #expect(HairOps.recolor(HairColorParams(), image: Self.brown(), mask: all).extent == Self.extent)
    }

    @Test func colorBlendKeepsLuminanceSoDarkHairStaysDarker() {
        var p = HairColorParams(); p.color = RGBA(r: 1, g: 0.9, b: 0.4, a: 1); p.strength = 1; p.keepShine = 0
        let all = CIImage(color: .white).cropped(to: Self.extent)
        let dark = CIImage(color: CIColor(red: 0.08, green: 0.06, blue: 0.05)).cropped(to: Self.extent)
        let light = CIImage(color: CIColor(red: 0.6, green: 0.5, blue: 0.4)).cropped(to: Self.extent)
        let d = GeometryTests.rgb(HairOps.recolor(p, image: dark, mask: all), x: 50, y: 50), l = GeometryTests.rgb(HairOps.recolor(p, image: light, mask: all), x: 50, y: 50)
        #expect(Int(d[0]) + Int(d[1]) < Int(l[0]) + Int(l[1]))
    }

    @Test func paramsRoundTrip() throws {
        var p = HairColorParams(); p.strength = 0.7; p.keepShine = 0.2
        #expect(try JSONDecoder().decode(HairColorParams.self, from: JSONEncoder().encode(p)) == p)
    }
}

struct HairColorGateTests {
    /// Dark hair above a skin-coloured face, over a bright background; the whole picture counts as person.
    private func photo() -> CIImage {
        let e = HairTests.extent
        let bg = CIImage(color: CIColor(red: 0.9, green: 0.9, blue: 0.95)).cropped(to: e)
        let hair = CIImage(color: CIColor(red: 0.08, green: 0.06, blue: 0.05)).cropped(to: CGRect(x: 60, y: 125, width: 80, height: 50))
        let skin = CIImage(color: CIColor(red: 0.85, green: 0.65, blue: 0.55)).cropped(to: CGRect(x: 70, y: 70, width: 60, height: 60))
        return skin.composited(over: hair.composited(over: bg))
    }

    @Test func gateKeepsHairColouredPixelsAndDropsOthers() {
        let m = HairMask.estimate(person: HairTests.everyone(), face: HairTests.face(), image: photo())
        #expect(GeometryTests.rgb(m, x: 100, y: 150)[0] > 150)             // dark hair above the face
        #expect(GeometryTests.rgb(m, x: 62, y: 95)[0] < 60)                // bright background beside the face, inside the head region
    }

    @Test func shadowedSkinBelowTheChinIsNotHair() {
        // dark hair above, bright skin face, and a darker patch of the same skin tone (neck in shadow) under the chin
        let e = HairTests.extent
        var img = photo()
        let neck = CIImage(color: CIColor(red: 0.85 * 0.35, green: 0.65 * 0.35, blue: 0.55 * 0.35)).cropped(to: CGRect(x: 75, y: 40, width: 50, height: 28))
        img = neck.composited(over: img)
        let m = HairMask.estimate(person: HairTests.everyone(), face: HairTests.face(), image: img)
        #expect(m.extent == e)
        #expect(GeometryTests.rgb(m, x: 100, y: 150)[0] > 150)            // hair still found above the face
        #expect(GeometryTests.rgb(m, x: 100, y: 55)[0] < 60)              // shadowed neck skin is excluded
    }

    @Test func noHairAboveTheFaceMeansNoGate() {
        let plain = CIImage(color: CIColor(red: 0.8, green: 0.6, blue: 0.5)).cropped(to: HairTests.extent)
        let nobody = MosaicOps.mask(rects: [], extent: HairTests.extent)
        #expect(HairMask.colorGate(image: plain, person: nobody, box: CGRect(x: 0.35, y: 0.35, width: 0.3, height: 0.3)) == nil)
    }
}
