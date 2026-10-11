import CoreImage
import Foundation
import Testing
@testable import Lumi

struct FakeFaces: FaceFinding {
    var boxes: [CGRect]
    func faceBoxes(in image: CIImage) throws -> [CGRect] { boxes }
}

extension ServicesSerial {
struct MosaicWatermarkRenderTests {
    static func checker(_ n: CGFloat = 64) -> CIImage {
        CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 2, "inputColor0": CIColor.white, "inputColor1": CIColor.black])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: n, height: n))
    }
    static func differs(_ a: CIImage, _ b: CIImage, x: Int) -> Bool { GeometryTests.rgb(a, x: x, y: 20) != GeometryTests.rgb(b, x: x, y: 20) }

    @Test func emptyConfigIsIdentity() {
        #expect(MosaicConfig().isIdentity)
        #expect(MosaicRender.apply(MosaicConfig(), to: Self.checker(), faces: []).extent == Self.checker().extent)
    }

    @Test func brushedMaskPixelatesOnlyThere() {
        var m = MaskCanvas(width: 32, height: 32); m.fill(rect: CGRect(x: 0, y: 0, width: 16, height: 32))
        var c = MosaicConfig(); c.masks = [m]; c.block = 0.2
        let img = Self.checker(), out = MosaicRender.apply(c, to: img, faces: [])
        #expect((0..<28).contains { Self.differs(out, img, x: $0) })
        #expect((36..<64).allSatisfy { !Self.differs(out, img, x: $0) })
    }

    @Test func coverFacesPixelatesDetectedFacesOnly() {
        var c = MosaicConfig(); c.coverFaces = true; c.block = 0.2
        let img = Self.checker(), out = MosaicRender.apply(c, to: img, faces: [CGRect(x: 0.0, y: 0.0, width: 0.4, height: 1)])
        #expect((0..<20).contains { Self.differs(out, img, x: $0) } && (50..<64).allSatisfy { !Self.differs(out, img, x: $0) })
    }

    @Test func blurStyleWorksThroughTheDocumentAndRoundTrips() throws {
        var d = EditDocument(); var m = MaskCanvas(width: 8, height: 8); m.fill(rect: CGRect(x: 0, y: 0, width: 8, height: 8))
        var c = MosaicConfig(); c.style = .blur; c.masks = [m]; d.mosaic = c
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).mosaic == c)
        #expect(Renderer.render(Self.checker(), document: d).extent == Self.checker().extent)
        d.mosaic = MosaicConfig(); #expect(d.operations.isEmpty)
    }

    @Test func rendererUsesTheFaceFinderOnlyWhenAsked() {
        Renderer.services = Renderer.Services(); Renderer.services.faceFinder = FakeFaces(boxes: [CGRect(x: 0, y: 0, width: 0.4, height: 1)])
        var d = EditDocument(); var c = MosaicConfig(); c.coverFaces = true; c.block = 0.2; d.mosaic = c
        let img = Self.checker(), out = Renderer.render(img, document: d)
        #expect((0..<20).contains { Self.differs(out, img, x: $0) })
        Renderer.services = Renderer.Services()                          // no finder: nothing to cover
        #expect(!(0..<64).contains { Self.differs(Renderer.render(img, document: d), img, x: $0) })
    }

    // MARK: watermark
    static func black(_ w: CGFloat = 400, _ h: CGFloat = 300) -> CIImage { CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: w, height: h)) }
    static func litPixels(_ i: CIImage) -> Int {
        let w = Int(i.extent.width), h = Int(i.extent.height)
        var buf = [UInt8](repeating: 0, count: 4 * w * h)
        GeometryTests.ctx.render(i, toBitmap: &buf, rowBytes: w * 4, bounds: i.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return buf.enumerated().filter { $0.offset % 4 == 0 && $0.element > 100 }.count
    }

    @Test func singleMarkDrawsInTheBottomRightOnly() {
        let out = WatermarkRenderer.apply(Watermark(name: "w", kind: .text("© Lumi"), opacity: 1, size: 0.1), to: Self.black())
        #expect(out.extent == Self.black().extent && Self.litPixels(out) > 50)
        func lit(_ x: Int, _ y: Int) -> Bool { GeometryTests.rgb(out, x: x, y: y)[0] > 100 }
        var topLeft = false
        for x in 0..<150 { for y in 150..<300 where lit(x, y) { topLeft = true } }
        #expect(!topLeft)
    }

    @Test func tiledMarkCoversMoreThanASingleOne() {
        var single = Watermark(name: "s", kind: .text("LUMI"), opacity: 1, size: 0.08)
        var tiled = single; tiled.isTiled = true
        let a = Self.litPixels(WatermarkRenderer.apply(single, to: Self.black())), b = Self.litPixels(WatermarkRenderer.apply(tiled, to: Self.black()))
        #expect(b > a * 3)
        single.opacity = 0.2
        #expect(Self.litPixels(WatermarkRenderer.apply(single, to: Self.black())) < a)           // fainter => fewer bright pixels
    }

    @Test func emptyTextAndImageKindsLeaveThePhoto() {
        let img = Self.black()
        #expect(Self.litPixels(WatermarkRenderer.apply(Watermark(name: "e", kind: .text("")), to: img)) == 0)
        #expect(Self.litPixels(WatermarkRenderer.apply(Watermark(name: "i", kind: .image("logo")), to: img)) == 0)
    }

    @Test func watermarkIsADocumentOperation() throws {
        var d = EditDocument(); d.watermark = Watermark(name: "me", kind: .text("© me"), isTiled: true)
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).watermark == d.watermark)
        #expect(Self.litPixels(Renderer.render(Self.black(), document: d)) > 0)
        d.watermark = nil; #expect(d.operations.isEmpty)
    }
}
}
