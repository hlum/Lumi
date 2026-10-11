import CoreImage
import Foundation
import Testing
@testable import Lumi

struct LayerTests {
    static func text(_ s: String = "Hi", size: Double = 0.1) -> Layer {
        var st = TextStyle(); st.size = size
        return Layer(content: .text(s, st))
    }
    static func sticker(_ id: String = "s") -> Layer { Layer(content: .sticker(id: id, outline: 0)) }

    @Test func addsMultipleTextLayersInOrder() throws {
        var s = LayerStack()
        let a = Self.text("A"), b = Self.text("B")
        try s.add(a); try s.add(b)
        #expect(s.layers.map(\.id) == [a.id, b.id])
    }

    @Test func emptyTextIsRejected() {
        var s = LayerStack()
        #expect(throws: LayerStack.AddError.emptyText) { try s.add(Self.text("  \n")) }
        #expect(s.layers.isEmpty)
    }

    @Test func stickerLimitIs25ButTextIsNotCounted() throws {
        var s = LayerStack()
        for _ in 0..<LayerStack.maxStickers { try s.add(Self.sticker()) }
        #expect(throws: LayerStack.AddError.stickerLimit) { try s.add(Self.sticker()) }
        try s.add(Self.text())
        #expect(s.layers.count == 26)
    }

    @Test func removingStickerFreesASlot() throws {
        var s = LayerStack(); let first = Self.sticker()
        try s.add(first); for _ in 1..<LayerStack.maxStickers { try s.add(Self.sticker()) }
        s.remove(first.id)
        try s.add(Self.sticker())
    }

    @Test func updateClampsOpacityAndScale() throws {
        var s = LayerStack(); let l = Self.text(); try s.add(l)
        s.update(l.id) { $0.opacity = 4; $0.transform.scale = 1000 }
        #expect(s.layers[0].opacity == 1 && s.layers[0].transform.scale == 20)
        s.update(l.id) { $0.opacity = -1; $0.transform.scale = 0 }
        #expect(s.layers[0].opacity == 0 && s.layers[0].transform.scale == 0.05)
        s.update(UUID()) { $0.opacity = 0.3 }          // unknown id: no-op
    }

    @Test func reorder() throws {
        var s = LayerStack(); let a = Self.text("A"), b = Self.text("B"), c = Self.text("C")
        for l in [a, b, c] { try s.add(l) }
        s.bringToFront(a.id); #expect(s.layers.map(\.id) == [b.id, c.id, a.id])
        s.sendToBack(c.id); #expect(s.layers.map(\.id) == [c.id, b.id, a.id])
        s.bringToFront(UUID())
    }

    @Test func stackRoundTripsThroughJSON() throws {
        var s = LayerStack(); try s.add(Self.text("Hello")); try s.add(Layer(content: .sticker(id: "star", outline: 0.05), transform: LayerTransform(center: CGPoint(x: 0.2, y: 0.8), scale: 2, rotation: 1, flipH: true), opacity: 0.5))
        #expect(try JSONDecoder().decode(LayerStack.self, from: JSONEncoder().encode(s)) == s)
    }

    @Test func textRendersAndScalesWithImageHeight() throws {
        let small = try #require(LayerRenderer.textImage("Hello", style: TextStyle(), imageHeight: 500))
        let big = try #require(LayerRenderer.textImage("Hello", style: TextStyle(), imageHeight: 2000))
        let ratio = big.extent.height / small.extent.height
        #expect(abs(ratio - 4) < 0.6)        // preview and export differ only in resolution
        #expect(abs(big.extent.width / small.extent.width - 4) < 0.6)
    }

    @Test func strokeAndShadowEnlargeTheImage() throws {
        let plain = try #require(LayerRenderer.textImage("Hi", style: TextStyle(), imageHeight: 1000))
        var st = TextStyle(); st.strokeWidth = 0.1; st.shadowRadius = 0.2
        let fancy = try #require(LayerRenderer.textImage("Hi", style: st, imageHeight: 1000))
        #expect(fancy.extent.width > plain.extent.width)
    }

    @Test func unknownFontFallsBack() {
        var st = TextStyle(); st.fontName = "NoSuchFont-XYZ"
        #expect(LayerRenderer.textImage("Hi", style: st, imageHeight: 500) != nil)
    }

    @Test func absurdSizeReturnsNilInsteadOfCrashing() {
        var st = TextStyle(); st.size = 500
        #expect(LayerRenderer.textImage("Hi", style: st, imageHeight: 10_000) == nil)
    }

    @Test func compositeKeepsBaseExtentAndPlacesAtCenter() {
        let base = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let dot = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 10, height: 10))
        let out = LayerRenderer.composite(dot, transform: LayerTransform(center: CGPoint(x: 0.25, y: 0.25)), opacity: 1, over: base)
        #expect(out.extent == base.extent)
        // normalized y is from the top, so (0.25,0.25) lands at CI y = 75
        #expect(GeometryTests.rgb(out, x: 25, y: 75)[0] > 200)
        #expect(GeometryTests.rgb(out, x: 75, y: 25)[0] < 20)
    }

    @Test func opacityBlendsLayer() {
        let base = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20))
        let full = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 20))
        let half = GeometryTests.rgb(LayerRenderer.composite(full, transform: LayerTransform(), opacity: 0.5, over: base), x: 10, y: 10)[0]
        #expect(half > 90 && half < 250)      // linear-light blending, so not exactly 128
    }

    @Test func renderWithUnknownStickerSkipsIt() throws {
        var s = LayerStack(); try s.add(Self.sticker("missing"))
        let base = RendererTests.solid(0.3, size: 20)
        #expect(RendererTests.pixel(LayerRenderer.render(s, over: base)) == RendererTests.pixel(base))
    }

    @Test func renderDrawsText() throws {
        var s = LayerStack(); try s.add(Self.text("MMMM", size: 0.5))
        let base = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        let out = LayerRenderer.render(s, over: base)
        #expect(out.extent == base.extent)
        let ctx = GeometryTests.ctx
        var buf = [UInt8](repeating: 0, count: 4 * 200 * 100)
        ctx.render(out, toBitmap: &buf, rowBytes: 800, bounds: base.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        #expect(buf.enumerated().contains { $0.offset % 4 == 0 && $0.element > 200 })   // some white glyph pixels
    }
}
