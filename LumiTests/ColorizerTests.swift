import CoreImage
import Foundation
import Testing
@testable import Lumi

struct FakeColorizer: Colorizing {
    func colorize(_ image: CIImage) throws -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.5, z: 0, w: 0), "inputBVector": CIVector(x: 0, y: 0, z: 0.5, w: 0)])
    }
}

struct LabMergeTests {
    @Test func lightnessOfBlackAndWhite() {
        #expect(LabMerge.lightness(r: 0, g: 0, b: 0) < 1 && abs(LabMerge.lightness(r: 255, g: 255, b: 255) - 100) < 0.5)
        #expect(LabMerge.lightness(r: 128, g: 128, b: 128) > 45 && LabMerge.lightness(r: 128, g: 128, b: 128) < 60)
    }

    @Test func bilinearSampleAtCornersCentreAndOutside() {
        let side = 3
        var plane = [Float](repeating: 0, count: 2 * side * side)
        for i in 0..<(side * side) { plane[i] = Float(i) }                       // channel 0: 0..8
        #expect(LabMerge.sample(plane, side: side, channel: 0, u: 0, v: 0) == 0)
        #expect(LabMerge.sample(plane, side: side, channel: 0, u: 1, v: 1) == 8)
        #expect(LabMerge.sample(plane, side: side, channel: 0, u: 0.5, v: 0.5) == 4)
        #expect(LabMerge.sample(plane, side: side, channel: 0, u: 0.25, v: 0) == 0.5)
        #expect(LabMerge.sample(plane, side: side, channel: 0, u: -3, v: 9) == 6)         // clamped to the bottom-left corner
        #expect(LabMerge.sample(plane, side: side, channel: 1, u: 0.5, v: 0.5) == 0)
    }
}

extension ServicesSerial {
struct ColorizeRenderTests {
    @Test func operationRoundTripsAndClamps() throws {
        var d = EditDocument(); d.colorize = 0.7
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).colorize == 0.7)
        d.colorize = 9; #expect(d.colorize == 1)
        d.colorize = nil; #expect(d.operations.isEmpty)
    }

    @Test func rendererUsesTheColorizerBlendsStrengthAndCaches() {
        Renderer.services = Renderer.Services(); Renderer.services.colorizer = FakeColorizer()
        defer { Renderer.services = Renderer.Services() }
        let img = RendererTests.solid(0.8, size: 32)
        var d = EditDocument(); d.colorize = 1
        let full = RendererTests.pixel(Renderer.render(img, document: d))
        #expect(full[0] > full[1])                                                        // the fake tints toward red
        d.colorize = 0.5
        let half = RendererTests.pixel(Renderer.render(img, document: d)), base = RendererTests.pixel(img)
        #expect(half[1] < base[1] && half[1] > full[1])
        d.colorize = 0; #expect(GeometryTests.near(RendererTests.pixel(Renderer.render(img, document: d)), base))
        #expect(Renderer.services.inpaintCalls == 1)
    }

    @Test func withoutAColorizerNothingChanges() {
        Renderer.services = Renderer.Services()
        var d = EditDocument(); d.colorize = 1
        let img = RendererTests.solid(0.8, size: 16)
        #expect(RendererTests.pixel(Renderer.render(img, document: d)) == RendererTests.pixel(img))
    }

    @Test(.enabled(if: SiggraphColorizer.isModelAvailable))
    func networkOutputIsPlausibleAndFullyMerged() throws {
        let c = try SiggraphColorizer()
        // L ramp 10...90 across the image: check output scale (ab should be within Lab range, not tiny and not huge) and finite
        let n = SiggraphColorizer.side
        let ab = try c.predictAB(lightness: (0..<(n * n)).map { Float(10 + 80 * Double($0 % n) / Double(n)) })
        #expect(ab.count == 2 * n * n && ab.allSatisfy { $0.isFinite })
        let peak = ab.map { abs($0) }.max() ?? 0, mean = ab.map { abs($0) }.reduce(0, +) / Float(ab.count)
        #expect(peak <= 130 && peak > 0.5 && mean < 80, "ab scale off: peak \(peak) mean \(mean)")

        // a gray photo comes back with color, same size, lightness preserved
        let gray = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 160, height: 120))
        let out = try c.colorize(gray)
        #expect(out.extent == gray.extent)
        let p = GeometryTests.rgb(out, x: 80, y: 60)
        #expect(abs(LabMerge.lightness(r: p[0], g: p[1], b: p[2]) - LabMerge.lightness(r: 128, g: 128, b: 128)) < 12, "lightness drifted: \(p)")
    }

    @Test(.enabled(if: SiggraphColorizer.isModelAvailable))
    func oversizedInputIsRejected() throws {
        #expect(throws: ColorizeError.tooLarge) { try SiggraphColorizer().colorize(CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 3000, height: 50))) }
    }
}
}
