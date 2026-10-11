import CoreGraphics
import Foundation
import Testing
@testable import Lumi

struct AnalysisTests {
    @Test func cacheComputesOncePerKey() async {
        let c = AnalysisCache<String, Int>()
        let a = await c.value(for: "x") { 41 + 1 }
        let b = await c.value(for: "x") { 999 }
        #expect(a == 42 && b == 42)
        #expect(await c.computeCount == 1)
    }

    @Test func differentKeysComputeSeparately() async {
        let c = AnalysisCache<String, Int>()
        _ = await c.value(for: "a") { 1 }; _ = await c.value(for: "b") { 2 }
        #expect(await c.computeCount == 2)
    }

    @Test func invalidateForcesRecompute() async {
        let c = AnalysisCache<String, Int>()
        _ = await c.value(for: "a") { 1 }
        await c.invalidate("a")
        let v = await c.value(for: "a") { 2 }
        let n = await c.computeCount
        #expect(v == 2 && n == 2)
    }

    @Test func cacheDoesNotStoreFailures() async {
        struct E: Error {}
        let c = AnalysisCache<String, Int>()
        _ = try? await c.value(for: "a") { throw E() }
        let v = await c.value(for: "a") { 5 }
        #expect(v == 5)
    }

    @Test func visionAnalyzerHandlesBlankImage() async throws {
        let ctx = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.5, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        let a = try await VisionAnalyzer().analyze(ctx.makeImage()!)
        #expect(a.faces.isEmpty && a.textBoxes.isEmpty)
    }
}
