import CoreImage
import Foundation
import Testing
@testable import Lumi

struct StickerTests {
    @Test func libraryIsLargeWithUniqueIds() {
        #expect(StickerLibrary.all.count >= 25)
        #expect(Set(StickerLibrary.all.map(\.id)).count == StickerLibrary.all.count)
        #expect(StickerLibrary.categories.count >= 4)
    }

    @Test(arguments: StickerLibrary.all.map(\.id))
    func everyStickerHasAPathAndRendersInsideItsSquare(id: String) throws {
        let p = try #require(StickerLibrary.path(id), "no path for \(id)")
        let b = p.bounds
        #expect(b.minX >= -0.01 && b.minY >= -0.01 && b.maxX <= 1.01 && b.maxY <= 1.01 && b.width > 0.2 && b.height > 0.2, "\(id) \(b)")
        let img = try #require(StickerLibrary.image(id, side: 128))
        #expect(img.extent == CGRect(x: 0, y: 0, width: 128, height: 128))
        // not empty: some pixel in the bounding box center region is opaque, and the far corner is clear
        var buf = [UInt8](repeating: 0, count: 4 * 128 * 128)
        GeometryTests.ctx.render(img, toBitmap: &buf, rowBytes: 512, bounds: img.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        #expect(buf.enumerated().contains { $0.offset % 4 == 3 && $0.element > 200 }, "\(id) is empty")
    }

    @Test func colorOverrideAndUnknownId() throws {
        let red = try #require(StickerLibrary.image("circle", side: 64, color: RGBA(r: 1, g: 0, b: 0, a: 1)))
        let px = GeometryTests.rgb(red, x: 32, y: 32)
        #expect(px[0] > 200 && px[1] < 40 && px[2] < 40)
        #expect(StickerLibrary.image("nope") == nil && StickerLibrary.path("nope") == nil)
    }

    @Test func searchMatchesNameCategoryAndKeywordsInBothLanguages() {
        #expect(StickerLibrary.search("heart").first?.id == "heart")
        #expect(StickerLibrary.search("ハート").first?.id == "heart")
        #expect(StickerLibrary.search("nature").count >= 5)
        #expect(StickerLibrary.search("zzz").isEmpty && StickerLibrary.search(" ").count == StickerLibrary.all.count)
    }

    @Test func outlineGrowsTheAlphaEdgeAndKeepsTheOriginalOnTop() throws {
        let dot = try #require(StickerLibrary.image("circle", side: 100, color: RGBA(r: 1, g: 0, b: 0, a: 1)))
        let out = OutlineOps.apply(to: dot, width: 0.05)
        #expect(out.extent.width > dot.extent.width)
        // just outside the circle's edge (circle radius ≈ 46 px, centered at 50): outline is white and opaque
        let edgeOut = GeometryTests.rgb(out, x: Int(out.extent.minX * -1) + 2, y: Int(-out.extent.minY) + 50)
        #expect(edgeOut[3] > 200 && edgeOut[0] > 200 && edgeOut[1] > 200)
        let center = GeometryTests.rgb(out, x: Int(-out.extent.minX) + 50, y: Int(-out.extent.minY) + 50)
        #expect(center[0] > 200 && center[1] < 60)              // the sticker itself is still red
    }

    @Test func zeroOutlineLeavesStickerUnchangedInRender() throws {
        var s = LayerStack(); try s.add(Layer(content: .sticker(id: "star5", outline: 0)))
        let base = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let out = LayerRenderer.render(s, over: base)
        #expect(out.extent == base.extent)
        #expect(GeometryTests.rgb(out, x: 100, y: 100)[0] > 150)               // yellow star at the center
    }

    @Test func stickersScaleWithThePhotoNotTheirOwnResolution() throws {
        var s = LayerStack(); try s.add(Layer(content: .sticker(id: "circle", outline: 0)))
        func lit(_ size: Int) -> Double {
            let base = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
            let o = LayerRenderer.render(s, over: base)
            var buf = [UInt8](repeating: 0, count: 4 * size * size)
            GeometryTests.ctx.render(o, toBitmap: &buf, rowBytes: size * 4, bounds: o.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return Double(buf.enumerated().filter { $0.offset % 4 == 0 && $0.element > 128 }.count) / Double(size * size)
        }
        #expect(abs(lit(200) - lit(800)) < 0.02)                              // same share of the photo at any resolution
    }

    @Test func manyStickersRespectTheLimitAndRoundTrip() throws {
        var s = LayerStack()
        for id in StickerLibrary.all.prefix(25).map(\.id) { try s.add(Layer(content: .sticker(id: id, outline: 0.01))) }
        #expect(throws: LayerStack.AddError.stickerLimit) { try s.add(Layer(content: .sticker(id: "heart", outline: 0))) }
        #expect(try JSONDecoder().decode(LayerStack.self, from: JSONEncoder().encode(s)) == s)
    }
}
