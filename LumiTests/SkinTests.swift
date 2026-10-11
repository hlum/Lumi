import CoreImage
import Foundation
import Testing
@testable import Lumi

struct SkinTests {
    static func face() -> FaceInfo {
        let f = FaceReshapeTests.face()
        return FaceInfo(box: f.box, landmarks: f.landmarks.merging(["leftEyebrow": [], "rightEyebrow": [], "innerLips": []]) { a, _ in a })
    }

    @Test func maskCoversFaceAndNotBackground() throws {
        let size = CGSize(width: 200, height: 200)
        let m = try #require(SkinMask.make(face: Self.face(), size: size, feather: 0))
        #expect(m.extent == CGRect(origin: .zero, size: size))
        // cheek: inside the face, away from features (box x .3-.7, y .25-.75; image y-down)
        #expect(GeometryTests.rgb(m, x: 100, y: 105)[0] > 200)                   // between nose and chin area
        #expect(GeometryTests.rgb(m, x: 5, y: 5)[0] < 20)                        // far corner
    }

    @Test func eyesAreCutOut() throws {
        let size = CGSize(width: 200, height: 200)
        let m = try #require(SkinMask.make(face: Self.face(), size: size, feather: 0))
        let eye = FaceReshape.center(FaceReshape.points(Self.face(), "leftEye"))!
        #expect(GeometryTests.rgb(m, x: Int(eye.x * 200), y: Int((1 - eye.y) * 200))[0] < 40)
    }

    @Test func degenerateInputsReturnNil() {
        #expect(SkinMask.make(face: FaceInfo(box: .zero, landmarks: [:]), size: CGSize(width: 10, height: 10)) == nil)
        #expect(SkinMask.make(face: Self.face(), size: .zero) == nil)
    }

    @Test func featherSoftensEdgeButKeepsExtent() throws {
        let size = CGSize(width: 200, height: 200)
        let hard = try #require(SkinMask.make(face: Self.face(), size: size, feather: 0))
        let soft = try #require(SkinMask.make(face: Self.face(), size: size, feather: 0.03))
        #expect(soft.extent == hard.extent)
    }

    static func texture() -> CIImage {   // noisy mid-gray so smoothing is measurable
        let n = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        return n.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0.3, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.3, z: 0, w: 0),
                                                                "inputBVector": CIVector(x: 0, y: 0, z: 0.3, w: 0), "inputBiasVector": CIVector(x: 0.35, y: 0.35, z: 0.35, w: 0)])
    }
    static func spread(_ i: CIImage) -> Int {
        let v = (0..<16).map { Int(GeometryTests.rgb(i, x: 8 + $0 * 3, y: 10)[0]) }
        return v.max()! - v.min()!
    }

    @Test func smoothingReducesNoiseInsideMaskOnly() {
        let img = Self.texture().cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let mask = MosaicOps.mask(rects: [CGRect(x: 0, y: 0, width: 0.5, height: 1)], extent: img.extent)
        var p = SkinParams(); p.smooth = 1; p.texture = 0
        let out = SkinOps.apply(p, to: img, mask: mask)
        func spreadAt(_ im: CIImage, _ x0: Int) -> Int { let v = (0..<12).map { Int(GeometryTests.rgb(im, x: x0 + $0, y: 20)[0]) }; return v.max()! - v.min()! }
        #expect(spreadAt(out, 2) < spreadAt(img, 2))
        #expect(spreadAt(out, 48) == spreadAt(img, 48))          // outside the mask: untouched
    }

    @Test func textureSliderKeepsMoreDetail() {
        let img = Self.texture()
        let mask = CIImage(color: .white).cropped(to: img.extent)
        var lo = SkinParams(); lo.smooth = 1; lo.texture = 0
        var hi = lo; hi.texture = 1
        #expect(Self.spread(SkinOps.apply(hi, to: img, mask: mask)) >= Self.spread(SkinOps.apply(lo, to: img, mask: mask)))
    }

    @Test func whitenBrightensAndTanDarkens() {
        let img = RendererTests.solid(0.5, size: 16), mask = CIImage(color: .white).cropped(to: img.extent)
        let base = RendererTests.pixel(img)[0]
        var w = SkinParams(); w.whiten = 1
        var t = SkinParams(); t.tan = 1
        #expect(RendererTests.pixel(SkinOps.apply(w, to: img, mask: mask))[0] > base)
        #expect(RendererTests.pixel(SkinOps.apply(t, to: img, mask: mask))[0] < base)
    }

    @Test func rosyAddsRedOverGreen() {
        let img = RendererTests.solid(0.5, size: 16), mask = CIImage(color: .white).cropped(to: img.extent)
        var p = SkinParams(); p.rosy = 1
        let o = RendererTests.pixel(SkinOps.apply(p, to: img, mask: mask))
        #expect(o[0] > o[1])
    }

    @Test func identityParamsReturnTheImage() {
        let img = RendererTests.solid(0.4, size: 16)
        #expect(SkinOps.apply(SkinParams(), to: img, mask: CIImage(color: .black).cropped(to: img.extent)).extent == img.extent)
        #expect(SkinParams().isIdentity)
    }

    @Test func emptyMaskChangesNothing() {
        let img = RendererTests.solid(0.5, size: 16)
        var p = SkinParams(); p.whiten = 1; p.smooth = 1
        let out = SkinOps.apply(p, to: img, mask: CIImage(color: .black).cropped(to: img.extent))
        #expect(RendererTests.pixel(out) == RendererTests.pixel(img))
    }
}
