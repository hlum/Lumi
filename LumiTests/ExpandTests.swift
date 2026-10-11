import CoreImage
import Foundation
import Testing
@testable import Lumi

extension ServicesSerial {
struct ExpandTests {
    @Test func identityConfigChangesNothing() throws {
        let img = RendererTests.solid(0.5, size: 40)
        #expect(ExpandConfig().isIdentity)
        #expect(try ExpandOps.apply(ExpandConfig(), to: img, inpainter: FakeInpainter()).extent == img.extent)
    }

    @Test func canvasGrowsByTheRequestedFractions() throws {
        var c = ExpandConfig(); c.left = 0.5; c.right = 0.25; c.top = 0.1; c.bottom = 0.1
        let out = try ExpandOps.apply(c, to: RendererTests.solid(0.5, size: 100), inpainter: FakeInpainter())
        #expect(out.extent == CGRect(x: 0, y: 0, width: 175, height: 120))
        let n = c.newSize(from: CGSize(width: 100, height: 100))
        #expect(abs(n.width - 175) < 1e-9 && abs(n.height - 120) < 1e-9)
    }

    @Test func originalPixelsSitInThePaddedPositionAndNewAreaIsFilled() throws {
        var c = ExpandConfig(); c.left = 1                     // doubles the width, new space on the left
        let img = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))
        let out = try ExpandOps.apply(c, to: img, inpainter: FakeInpainter())      // fake paints green into the masked area
        #expect(out.extent.width == 100)
        let orig = GeometryTests.rgb(out, x: 80, y: 25), added = GeometryTests.rgb(out, x: 10, y: 25)
        #expect(orig[0] > 200 && orig[1] < 40)                 // the photo is on the right, untouched
        #expect(added[1] > 200 && added[0] < 40)               // the new strip was handed to the inpainter
    }

    @Test func bottomPaddingSitsAtLowY() {
        var c = ExpandConfig(); c.bottom = 1
        let p = ExpandOps.plan(c, image: RendererTests.solid(0.5, size: 50))
        #expect(GeometryTests.rgb(p.mask, x: 25, y: 10)[0] > 200)       // low y = new area (white)
        #expect(GeometryTests.rgb(p.mask, x: 25, y: 90)[0] < 40)        // photo area (black)
    }

    @Test func valuesAreClamped() {
        var c = ExpandConfig(); c.left = 9; c.top = -3; c.clamp()
        #expect(c.left == 1 && c.top == 0)
    }

    @Test func aspectPresetsAddSpaceOnTheShortAxis() {
        let wide = ExpandConfig.toAspect(2, from: CGSize(width: 100, height: 100))
        #expect(wide.left == 0.5 && wide.right == 0.5 && wide.top == 0)
        let tall = ExpandConfig.toAspect(0.5, from: CGSize(width: 100, height: 100))
        #expect(tall.top == 0.5 && tall.bottom == 0.5 && tall.left == 0)
        #expect(ExpandConfig.toAspect(1, from: CGSize(width: 100, height: 100)).isIdentity)
        #expect(ExpandConfig.toAspect(0, from: .zero).isIdentity)
        let n = ExpandConfig.toAspect(16.0 / 9, from: CGSize(width: 900, height: 1200)).newSize(from: CGSize(width: 900, height: 1200))
        #expect(abs(Double(n.width / n.height) - 1) < 1.2 && n.width > 900)          // clamped growth never exceeds 2x per axis
    }

    @Test func expandIsADocumentOperationWithCachedRender() throws {
        Renderer.services = Renderer.Services(inpainter: FakeInpainter())
        var d = EditDocument(); var c = ExpandConfig(); c.right = 0.5; d.expand = c
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).expand == c)
        let img = RendererTests.solid(0.5, size: 40)
        #expect(Renderer.render(img, document: d).extent.width == 60)
        _ = Renderer.render(img, document: d)
        #expect(Renderer.services.inpaintCalls == 1)
        d.expand = ExpandConfig(); #expect(d.operations.isEmpty)
    }

    @Test func withoutAnInpainterTheImageIsUnchanged() {
        Renderer.services = Renderer.Services(inpainter: nil)
        var d = EditDocument(); var c = ExpandConfig(); c.left = 0.5; d.expand = c
        #expect(Renderer.render(RendererTests.solid(0.5, size: 40), document: d).extent.width == 40)
    }
}
}
