import CoreImage
import Foundation
import Testing
@testable import Lumi

struct CropMathTests {
    let full = CGRect(x: 0, y: 0, width: 1, height: 1)
    let mid = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    let size = CGSize(width: 1000, height: 1000)

    @Test func handlesAreChosenByWhereYouTouch() {
        #expect(CropMath.handle(at: CGPoint(x: 0.26, y: 0.26), in: mid, slop: 0.05) == .topLeft)
        #expect(CropMath.handle(at: CGPoint(x: 0.74, y: 0.74), in: mid, slop: 0.05) == .bottomRight)
        #expect(CropMath.handle(at: CGPoint(x: 0.5, y: 0.26), in: mid, slop: 0.05) == .top)
        #expect(CropMath.handle(at: CGPoint(x: 0.74, y: 0.5), in: mid, slop: 0.05) == .right)
        #expect(CropMath.handle(at: CGPoint(x: 0.5, y: 0.5), in: mid, slop: 0.05) == .move)
        #expect(CropMath.handle(at: CGPoint(x: 0.05, y: 0.05), in: mid, slop: 0.05) == nil)
    }

    @Test func freeDragMovesOnlyTheTouchedSides() {
        let r = CropMath.drag(mid, handle: .topLeft, by: CGPoint(x: 0.1, y: 0.05), aspect: nil, imageSize: size)
        #expect(abs(r.minX - 0.35) < 1e-9 && abs(r.minY - 0.30) < 1e-9 && r.maxX == 0.75 && r.maxY == 0.75)
        let e = CropMath.drag(mid, handle: .right, by: CGPoint(x: 0.1, y: 0.4), aspect: nil, imageSize: size)
        #expect(abs(e.maxX - 0.85) < 1e-9 && e.minY == 0.25 && e.maxY == 0.75)
    }

    @Test func neverLeavesThePictureOrCollapses() {
        let out = CropMath.drag(mid, handle: .bottomRight, by: CGPoint(x: 5, y: 5), aspect: nil, imageSize: size)
        #expect(out.maxX == 1 && out.maxY == 1)
        let tiny = CropMath.drag(mid, handle: .bottomRight, by: CGPoint(x: -5, y: -5), aspect: nil, imageSize: size)
        #expect(tiny.width >= CropMath.minSide - 1e-9 && tiny.height >= CropMath.minSide - 1e-9)
        let moved = CropMath.drag(mid, handle: .move, by: CGPoint(x: 5, y: -5), aspect: nil, imageSize: size)
        #expect(moved.maxX == 1 && moved.minY == 0 && moved.width == 0.5)
    }

    @Test func lockedRatioKeepsTheRatioWhileDragging() {
        let ratio = 16.0 / 9
        let start = CropSpec.rect(aspect: 16, 9, in: size)
        for h in [CropMath.Handle.topLeft, .topRight, .bottomLeft, .bottomRight, .left, .right, .top, .bottom] {
            let r = CropMath.drag(start, handle: h, by: CGPoint(x: -0.1, y: 0.06), aspect: ratio, imageSize: size)
            let pixelAspect = Double(r.width * size.width) / Double(r.height * size.height)
            #expect(abs(pixelAspect - ratio) < 0.02, "\(h)")
            #expect(r.minX >= -1e-9 && r.minY >= -1e-9 && r.maxX <= 1 + 1e-9 && r.maxY <= 1 + 1e-9, "\(h)")
        }
    }

    @Test func keystoneKeepsTheFrameSizeAndChangesThePicture() {
        let img = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        let out = GeometryOps.keystone(img, v: 1, h: 0)
        #expect(out.extent.size == img.extent.size)
        var spec = CropSpec(); spec.keystoneV = 0.5
        #expect(!spec.isIdentity && GeometryOps.apply(spec, to: img).extent.width > 0)
    }

    @Test func oldCropDraftsDecodeAndKeystoneRoundTrips() throws {
        let old = #"{"rect":[[0.1,0.1],[0.5,0.5]],"quarterTurns":1,"angle":2,"flipH":true,"flipV":false}"#
        let c = try JSONDecoder().decode(CropSpec.self, from: Data(old.utf8))
        #expect(c.quarterTurns == 1 && c.flipH && c.keystoneV == 0)
        var k = CropSpec(); k.keystoneH = -0.4; k.angle = 3
        #expect(try JSONDecoder().decode(CropSpec.self, from: JSONEncoder().encode(k)) == k)
    }
}
