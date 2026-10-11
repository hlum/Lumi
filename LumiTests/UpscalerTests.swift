import CoreImage
import Foundation
import Testing
@testable import Lumi

struct FakeUpscaler: Upscaling {
    func upscale4x(_ image: CIImage) throws -> CIImage {
        image.transformed(by: CGAffineTransform(scaleX: 4, y: 4))
    }
}

struct TilePlanTests {
    @Test func smallImagesAreOneTile() {
        let t = TilePlan.tiles(width: 300, height: 200)
        #expect(t.count == 1 && t[0].origin == .zero && t[0].core == CGRect(x: 0, y: 0, width: 300, height: 200))
    }

    @Test func coresPartitionTheImageExactly() {
        for (w, h) in [(512, 512), (513, 700), (1500, 900), (2048, 2048), (777, 1234)] {
            let t = TilePlan.tiles(width: w, height: h)
            let area = t.reduce(0.0) { $0 + Double($1.core.width * $1.core.height) }
            #expect(area == Double(w * h), "\(w)x\(h)")                                             // no gaps, no double coverage by area
            for (i, a) in t.enumerated() { for b in t[(i + 1)...] { #expect(a.core.intersection(b.core).isEmpty || a.core.intersection(b.core).width * a.core.intersection(b.core).height == 0, "\(w)x\(h)") } }
            #expect(t.allSatisfy { CGRect(x: 0, y: 0, width: w, height: h).contains($0.core) })
        }
    }

    @Test func everyWindowStaysInsideLargeImagesAndCoversItsCore() {
        let t = TilePlan.tiles(width: 1500, height: 900)
        for tile in t {
            let window = CGRect(x: tile.origin.x, y: tile.origin.y, width: 512, height: 512)
            #expect(CGRect(x: 0, y: 0, width: 1500, height: 900).contains(window))
            #expect(window.contains(tile.core))
        }
    }

    @Test func neighbouringWindowsAlwaysOverlap() {
        for w in [513, 600, 1024, 1500, 2048] {
            let xs = Set(TilePlan.tiles(width: w, height: 512).map { Int($0.origin.x) }).sorted()
            for (a, b) in zip(xs, xs.dropFirst()) { #expect(a + 512 - b >= 32, "\(w): \(a) \(b)") }
        }
    }

    @Test func tileCountGrowsWithImageSize() {
        #expect(TilePlan.tiles(width: 512, height: 512).count == 1)
        #expect(TilePlan.tiles(width: 1024, height: 512).count == 3)          // 2 tiles would touch with no overlap, so 3 evenly spaced ones
        #expect(TilePlan.tiles(width: 2048, height: 2048).count > TilePlan.tiles(width: 1024, height: 1024).count)
        #expect(TilePlan.tiles(width: 0, height: 10).isEmpty)
    }
}

extension ServicesSerial {
struct UpscaleRenderTests {
    @Test func upscaleOperationRoundTripsAndValidates() throws {
        var d = EditDocument(); d.upscale = 4
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).upscale == 4)
        d.upscale = 3; #expect(d.upscale == nil && d.operations.isEmpty)           // only 2 and 4 are valid
    }

    @Test func rendererScalesBy2or4AndCaches() {
        Renderer.services = Renderer.Services(); Renderer.services.upscaler = FakeUpscaler()
        defer { Renderer.services = Renderer.Services() }
        let img = RendererTests.solid(0.5, size: 40)
        var d = EditDocument(); d.upscale = 4
        #expect(Renderer.render(img, document: d).extent.width == 160)
        d.upscale = 2
        #expect(Renderer.render(img, document: d).extent.width == 80)
        #expect(Renderer.services.inpaintCalls == 1)                                // one model run served both factors
    }

    @Test func withoutAnUpscalerTheImageIsUnchanged() {
        Renderer.services = Renderer.Services()
        var d = EditDocument(); d.upscale = 4
        #expect(Renderer.render(RendererTests.solid(0.5, size: 40), document: d).extent.width == 40)
    }

    @Test(.enabled(if: RealESRGANUpscaler.isModelAvailable))
    func realModelUpscalesAndPreservesTheLook() throws {
        let grad = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 300, y: 0), "inputColor0": CIColor.black, "inputColor1": CIColor.white])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 300, height: 200))
        let start = Date()
        let out = try RealESRGANUpscaler().upscale4x(grad)
        let seconds = Date().timeIntervalSince(start)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 1200, height: 800))
        let l = GeometryTests.rgb(out, x: 100, y: 400)[0], r = GeometryTests.rgb(out, x: 1100, y: 400)[0]
        #expect(l < 90 && r > 160, "gradient direction lost: \(l) \(r)")
        #expect(seconds < 60, "slow: \(seconds)")
    }

    @Test(.enabled(if: RealESRGANUpscaler.isModelAvailable))
    func oversizedInputIsRejected() throws {
        let big = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 3000, height: 100))
        #expect(throws: UpscaleError.tooLarge) { try RealESRGANUpscaler().upscale4x(big) }
    }
}
}
