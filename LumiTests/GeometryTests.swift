import CoreImage
import Foundation
import Testing
@testable import Lumi

struct GeometryTests {
    static let ctx = CIContext(options: [.useSoftwareRenderer: true])

    /// Left half red, right half blue.
    static func twoTone(w: CGFloat = 100, h: CGFloat = 50) -> CIImage {
        let red = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: w / 2, height: h))
        let blue = CIImage(color: .blue).cropped(to: CGRect(x: w / 2, y: 0, width: w / 2, height: h))
        return blue.composited(over: red)
    }

    static func rgb(_ img: CIImage, x: Int, y: Int) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 4)
        ctx.render(img, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: img.extent.minX + CGFloat(x), y: img.extent.minY + CGFloat(y), width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return p
    }
    static func isRed(_ p: [UInt8]) -> Bool { p[0] > 200 && p[2] < 50 }
    static func isBlue(_ p: [UInt8]) -> Bool { p[2] > 200 && p[0] < 50 }

    @Test func identitySpecReturnsImageUntouched() {
        let i = Self.twoTone()
        #expect(CropSpec().isIdentity)
        #expect(GeometryOps.apply(CropSpec(), to: i).extent == i.extent)
    }

    @Test func quarterTurnSwapsDimensions() {
        let o = GeometryOps.apply(CropSpec(quarterTurns: 1), to: Self.twoTone())
        #expect(o.extent.width == 50 && o.extent.height == 100 && o.extent.origin == .zero)
    }

    @Test func fourQuarterTurnsAreIdentityInSize() {
        let o = GeometryOps.apply(CropSpec(quarterTurns: 4), to: Self.twoTone())
        #expect(o.extent.size == CGSize(width: 100, height: 50))
        #expect(Self.isRed(Self.rgb(o, x: 5, y: 25)) && Self.isBlue(Self.rgb(o, x: 95, y: 25)))
    }

    @Test func negativeTurnsWrap() {
        let o = GeometryOps.apply(CropSpec(quarterTurns: -1), to: Self.twoTone())
        #expect(o.extent.size == CGSize(width: 50, height: 100))
    }

    @Test func clockwiseTurnMovesLeftToTop() {
        // red is the left half; rotating clockwise puts it on top (CI y grows upward, so high y)
        let o = GeometryOps.apply(CropSpec(quarterTurns: 1), to: Self.twoTone())
        #expect(Self.isRed(Self.rgb(o, x: 25, y: 90)))
        #expect(Self.isBlue(Self.rgb(o, x: 25, y: 10)))
    }

    @Test func flipHorizontalSwapsSides() {
        let o = GeometryOps.apply(CropSpec(flipH: true), to: Self.twoTone())
        #expect(Self.isBlue(Self.rgb(o, x: 5, y: 25)) && Self.isRed(Self.rgb(o, x: 95, y: 25)))
        #expect(o.extent.size == CGSize(width: 100, height: 50))
    }

    @Test func flipVerticalKeepsHorizontalLayout() {
        let o = GeometryOps.apply(CropSpec(flipV: true), to: Self.twoTone())
        #expect(Self.isRed(Self.rgb(o, x: 5, y: 25)) && Self.isBlue(Self.rgb(o, x: 95, y: 25)))
    }

    @Test func cropRectSelectsRegion() {
        let o = GeometryOps.apply(CropSpec(rect: CGRect(x: 0.5, y: 0, width: 0.5, height: 1)), to: Self.twoTone())
        #expect(o.extent.size == CGSize(width: 50, height: 50))
        #expect(Self.isBlue(Self.rgb(o, x: 25, y: 25)))
    }

    @Test func freeAngleCropsInsideFrame() {
        let o = GeometryOps.apply(CropSpec(angle: 10), to: Self.twoTone())
        #expect(o.extent.width < 100 && o.extent.height < 50 && o.extent.width > 60)
        // no transparent corners: every corner pixel is opaque
        #expect(Self.rgb(o, x: 0, y: 0)[3] == 255 && Self.rgb(o, x: Int(o.extent.width) - 1, y: Int(o.extent.height) - 1)[3] == 255)
    }

    @Test func zeroInsetIsFullSize() {
        let (w, h) = GeometryOps.insetSize(width: 100, height: 50, radians: 0)
        #expect(abs(w - 100) < 1e-9 && abs(h - 50) < 1e-9)
    }

    @Test func insetShrinksMonotonicallyAndKeepsAspect() {
        let a = GeometryOps.insetSize(width: 100, height: 50, radians: 0.1)
        let b = GeometryOps.insetSize(width: 100, height: 50, radians: 0.3)
        #expect(b.0 < a.0 && a.0 < 100)
        #expect(abs(a.0 / a.1 - 2) < 1e-9)
    }

    @Test func insetHandlesDegenerateSize() {
        #expect(GeometryOps.insetSize(width: 0, height: 10, radians: 0.2) == (0, 0))
    }

    @Test func ratioRectFitsAndCenters() {
        let r = CropSpec.rect(aspect: 1, 1, in: CGSize(width: 200, height: 100))
        #expect(abs(r.width - 0.5) < 1e-9 && r.height == 1 && abs(r.midX - 0.5) < 1e-9)
        let t = CropSpec.rect(aspect: 16, 9, in: CGSize(width: 100, height: 200))
        #expect(t.width == 1 && abs(t.height * 200 / 100 - 9.0 / 16) < 1e-9)
        #expect(CropSpec.rect(aspect: 0, 1, in: CGSize(width: 10, height: 10)) == CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    @Test func straightenCancelsTiltAndClamps() {
        #expect(CropSpec.straighten(horizonTilt: 3.5) == -3.5)
        #expect(CropSpec.straighten(horizonTilt: -100) == 45)
    }

    @Test func specRoundTripsThroughDocument() throws {
        var d = EditDocument()
        d.crop = CropSpec(rect: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.5), quarterTurns: 1, angle: 2, flipH: true)
        let back = try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d))
        #expect(back.crop == d.crop)
        d.crop = CropSpec()
        #expect(d.operations.isEmpty)
    }
}
