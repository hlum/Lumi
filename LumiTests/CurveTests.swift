import Foundation
import Testing
@testable import Lumi

struct CurveTests {
    @Test func defaultIsIdentity() {
        let c = ToneCurve()
        #expect(c.isIdentity && c.lut == (0...255).map { UInt8($0) })
    }

    @Test func passesThroughControlPoints() {
        let c = ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.3), CGPoint(x: 1, y: 1)])
        #expect(abs(c.value(at: 0.5) - 0.3) < 1e-9)
        #expect(c.value(at: 0) == 0 && c.value(at: 1) == 1)
    }

    @Test func monotoneInputGivesMonotoneOutputWithoutOvershoot() {
        let c = ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.1, y: 0.9), CGPoint(x: 0.2, y: 0.92), CGPoint(x: 1, y: 1)])
        let l = c.lut
        #expect(zip(l, l.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(l.allSatisfy { $0 <= 255 })
    }

    @Test func clampsOutsideRangeAndOutOfBoundsPoints() {
        let c = ToneCurve(points: [CGPoint(x: -1, y: -1), CGPoint(x: 2, y: 5)])
        #expect(c.value(at: 0.5) >= 0 && c.value(at: 0.5) <= 1)
        #expect(c.value(at: -3) == c.value(at: 0) && c.value(at: 9) == c.value(at: 1))
    }

    @Test func unsortedAndDuplicatePointsAreHandled() {
        let c = ToneCurve(points: [CGPoint(x: 1, y: 1), CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.2), CGPoint(x: 0.5, y: 0.8)])
        #expect(c.value(at: 0.5).isFinite && c.value(at: 0.75).isFinite)
    }

    @Test func singlePointFallsBackToIdentityValue() {
        #expect(ToneCurve(points: [CGPoint(x: 0.5, y: 0.9)]).value(at: 0.3) == 0.3)
        #expect(ToneCurve(points: []).value(at: 0.3) == 0.3)
    }

    @Test func flatSegmentStaysFlat() {
        let c = ToneCurve(points: [CGPoint(x: 0, y: 0.5), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1)])
        #expect(abs(c.value(at: 0.25) - 0.5) < 1e-9)
    }

    @Test func contrastPresetDarkensShadowsLightensHighlights() {
        let c = ToneCurve.presets["contrast"]!
        #expect(c.value(at: 0.25) < 0.25 && c.value(at: 0.75) > 0.75)
    }

    @Test func fadeLiftsBlacks() {
        #expect(ToneCurve.presets["fade"]!.lut[0] > 0)
    }

    @Test func codableThroughDocument() throws {
        var d = EditDocument(); d.curve = ToneCurve.presets["contrast"]!
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).curve == d.curve)
        d.curve = ToneCurve()
        #expect(d.operations.isEmpty)
    }

    @Test func rendererAppliesCurve() {
        let img = RendererTests.solid(0.25)
        var d = EditDocument(); d.curve = ToneCurve.presets["contrast"]!
        #expect(RendererTests.pixel(Renderer.render(img, document: d))[0] < RendererTests.pixel(img)[0])
    }
}
