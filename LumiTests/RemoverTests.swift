import CoreImage
import Foundation
import Testing
@testable import Lumi

/// Tests that swap `Renderer.services` share global state, so they all live under this one serialized suite.
@Suite(.serialized) enum ServicesSerial {}

struct FakeInpainter: Inpainting {
    /// Fills the masked pixels with green so tests can see where it ran.
    func inpaint(_ image: CIImage, mask: CIImage) throws -> CIImage {
        let f = CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: image.extent),
                                                              kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])!
        return f.outputImage!.cropped(to: image.extent)
    }
}

extension ServicesSerial {
struct RemoverTests {
    init() { Renderer.services = Renderer.Services(inpainter: FakeInpainter()) }

    // MARK: view <-> image mapping
    @Test func mappingLetterboxesAndRoundTrips() {
        let m = FitMapping(view: CGSize(width: 400, height: 800), image: CGSize(width: 2000, height: 1000))   // wide image in a tall view
        #expect(m.scale == 0.2)
        #expect(m.displayed == CGRect(x: 0, y: 300, width: 400, height: 200))
        #expect(m.toImage(CGPoint(x: 200, y: 400)) == CGPoint(x: 1000, y: 500))
        #expect(m.toImage(CGPoint(x: 200, y: 100)) == nil)                     // in the letterbox
        #expect(m.toImageClamped(CGPoint(x: -50, y: 9999)) == CGPoint(x: 0, y: 1000))
    }

    @Test func mappingHandlesZeroSizes() {
        let m = FitMapping(view: .zero, image: .zero)
        #expect(m.toImage(CGPoint(x: 1, y: 1)) == nil)
        _ = m.toImageClamped(.zero)
    }

    // MARK: remover model
    @Test func maskKeepsTheImageAspect() {
        let r = RemoverModel(imageSize: CGSize(width: 4000, height: 3000))
        #expect(r.mask.width == 1024 && r.mask.height == 768)
        #expect(!r.hasSelection && !r.canUndo)
    }

    @Test func brushStrokePaintsWhereDragged() {
        let r = RemoverModel(imageSize: CGSize(width: 1000, height: 1000))
        r.brushSize = 0.1
        r.begin(at: CGPoint(x: 500, y: 500)); r.move(to: CGPoint(x: 700, y: 500)); r.end(at: CGPoint(x: 700, y: 500))
        #expect(r.hasSelection && r.canUndo)
        #expect(r.mask[512, 512] == 255 && r.mask[716, 512] > 0)
        #expect(r.mask[100, 100] == 0)
    }

    @Test func boxFillsOnlyOnEnd() {
        let r = RemoverModel(imageSize: CGSize(width: 1000, height: 1000)); r.mode = .box
        r.begin(at: CGPoint(x: 100, y: 100)); r.move(to: CGPoint(x: 300, y: 300))
        #expect(!r.hasSelection)
        r.end(at: CGPoint(x: 300, y: 300))
        #expect(r.hasSelection && r.mask[200, 200] == 255 && r.mask[500, 500] == 0)
    }

    @Test func undoStrokeRestoresPreviousSelection() {
        let r = RemoverModel(imageSize: CGSize(width: 1000, height: 1000))
        r.begin(at: CGPoint(x: 200, y: 200)); r.end(at: CGPoint(x: 200, y: 200))
        let one = r.mask
        r.begin(at: CGPoint(x: 800, y: 800)); r.end(at: CGPoint(x: 800, y: 800))
        r.undoStroke(); #expect(r.mask == one)
        r.undoStroke(); #expect(!r.hasSelection)
        r.undoStroke()
    }

    @Test func takeReturnsAndClears() {
        let r = RemoverModel(imageSize: CGSize(width: 100, height: 100))
        #expect(r.take() == nil)
        r.begin(at: CGPoint(x: 50, y: 50)); r.end(at: CGPoint(x: 50, y: 50))
        #expect(r.take() != nil && !r.hasSelection && !r.canUndo)
    }

    // MARK: document + render
    @Test func removalIsAnOperationThatRoundTrips() throws {
        var d = EditDocument()
        var m = MaskCanvas(width: 16, height: 16); m.fill(rect: CGRect(x: 4, y: 4, width: 8, height: 8))
        d.removals = [m]
        let back = try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d))
        #expect(back.removals == [m])
        d.removals = []; #expect(d.operations.isEmpty)
    }

    @Test func renderRunsTheInpainterInsideTheMaskOnly() {
        var d = EditDocument()
        var m = MaskCanvas(width: 32, height: 32); m.fill(rect: CGRect(x: 0, y: 0, width: 16, height: 32))     // left half
        d.removals = [m]
        let img = RendererTests.solid(0.5, size: 64)
        let out = Renderer.render(img, document: d)
        let left = GeometryTests.rgb(out, x: 10, y: 32), right = GeometryTests.rgb(out, x: 54, y: 32)
        #expect(left[1] > 200 && left[0] < 60)                      // filled
        #expect(right == GeometryTests.rgb(img, x: 54, y: 32))      // untouched
    }

    @Test func maskIsScaledToTheImageSize() {
        var m = MaskCanvas(width: 10, height: 10); m.fill(rect: CGRect(x: 0, y: 0, width: 5, height: 10))
        let big = MaskScaling.scaled(m, to: CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(big.extent == CGRect(x: 0, y: 0, width: 200, height: 200))
        #expect(GeometryTests.rgb(big, x: 50, y: 100)[0] > 200 && GeometryTests.rgb(big, x: 150, y: 100)[0] < 20)
    }

    @Test func resultIsCachedAcrossRendersAndInvalidatedByEarlierEdits() {
        Renderer.services = Renderer.Services(inpainter: FakeInpainter())
        var d = EditDocument()
        var m = MaskCanvas(width: 8, height: 8); m.fill(rect: CGRect(x: 0, y: 0, width: 4, height: 4))
        d.removals = [m]
        let img = RendererTests.solid(0.5, size: 32)
        _ = Renderer.render(img, document: d); _ = Renderer.render(img, document: d)
        #expect(Renderer.services.inpaintCalls == 1, "\(Renderer.services.keysSeen)")
        d.exposure = 0.3                                    // an op before... after the remover: removal prefix unchanged
        _ = Renderer.render(img, document: d)
        #expect(Renderer.services.inpaintCalls == 1, "\(Renderer.services.keysSeen)")
        _ = Renderer.render(RendererTests.solid(0.5, size: 48), document: d)        // different image size: recompute
        #expect(Renderer.services.inpaintCalls == 2)
    }

    @Test func noInpainterMeansTheImageIsReturnedUnchanged() {
        Renderer.services = Renderer.Services(inpainter: nil)
        var d = EditDocument(); var m = MaskCanvas(width: 8, height: 8); m.fill(rect: CGRect(x: 0, y: 0, width: 8, height: 8)); d.removals = [m]
        let img = RendererTests.solid(0.5, size: 16)
        #expect(RendererTests.pixel(Renderer.render(img, document: d)) == RendererTests.pixel(img))
    }

    @Test func tintedOverlayShowsOnlyWhenSelected() {
        #expect(MaskCanvas(width: 4, height: 4).tintedImage() == nil)
        var m = MaskCanvas(width: 4, height: 4); m.fill(rect: CGRect(x: 0, y: 0, width: 2, height: 2))
        #expect(m.tintedImage()?.width == 4)
    }
}
}
