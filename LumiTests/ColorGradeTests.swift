import CoreImage
import Foundation
import Testing
@testable import Lumi

struct ColorGradeTests {
    @Test func defaultIsIdentityAndLUTIsIdentity() {
        #expect(ColorGrade().isIdentity)
        let l = ColorGrade().lut(size: 9), id = LUT.identity(size: 9)
        #expect(zip(l.rgb, id.rgb).allSatisfy { abs($0 - $1) < 1e-4 })
    }

    @Test func hslRoundTrips() {
        for c in [(1.0, 0.0, 0.0), (0.2, 0.7, 0.4), (0.9, 0.9, 0.1), (0.3, 0.3, 0.9), (0.5, 0.5, 0.5), (0, 0, 0), (1, 1, 1)] {
            let h = ColorGrade.hsl(c.0, c.1, c.2), o = ColorGrade.rgb(h.h, h.s, h.l)
            #expect(abs(o.0 - c.0) < 1e-6 && abs(o.1 - c.1) < 1e-6 && abs(o.2 - c.2) < 1e-6)
        }
        #expect(abs(ColorGrade.hsl(0, 1, 0).h - 120) < 1e-9 && abs(ColorGrade.hsl(0, 0, 1).h - 240) < 1e-9)
    }

    @Test func eightBandsWithOverlappingWeights() {
        #expect(ColorGrade.bandNames.count == 8 && ColorGrade.bandCenters.count == 8)
        #expect(ColorGrade.weight(hue: 0, band: 0) == 1 && ColorGrade.weight(hue: 359, band: 0) > 0.9)       // wraps around red
        #expect(ColorGrade.weight(hue: 120, band: 0) == 0)
        let total = (0..<8).map { ColorGrade.weight(hue: 45, band: $0) }.reduce(0, +)
        #expect(total > 0.9 && total < 1.6)                                                                   // smooth blend between neighbours
    }

    @Test func aBandOnlyMovesItsOwnHue() {
        var g = ColorGrade(); g.bands[5] = .init(hue: 0, sat: -1, lum: 0)               // desaturate blues
        let blue = g.apply(0.2, 0.3, 0.9), red = g.apply(0.9, 0.2, 0.2)
        let rb = ColorGrade.hsl(blue.0, blue.1, blue.2), rr = ColorGrade.hsl(red.0, red.1, red.2)
        #expect(rb.s < ColorGrade.hsl(0.2, 0.3, 0.9).s * 0.4)
        #expect(abs(rr.s - ColorGrade.hsl(0.9, 0.2, 0.2).s) < 1e-6)                        // red untouched
    }

    @Test func hueShiftRotatesTheBandAndGraysAreIgnored() {
        var g = ColorGrade(); g.bands[0] = .init(hue: 1, sat: 0, lum: 0)                 // +30° on reds
        let o = g.apply(0.9, 0.1, 0.1), h0 = ColorGrade.hsl(0.9, 0.1, 0.1), h1 = ColorGrade.hsl(o.0, o.1, o.2)
        #expect(h1.h > h0.h + 10 && h1.h < h0.h + 40)
        let gray = g.apply(0.5, 0.5, 0.5)
        #expect(abs(gray.0 - 0.5) < 1e-6 && abs(gray.1 - 0.5) < 1e-6)
    }

    @Test func luminanceShiftBrightensOrDarkensTheBand() {
        var g = ColorGrade(); g.bands[3] = .init(hue: 0, sat: 0, lum: 1)
        let base = ColorGrade.hsl(0.2, 0.7, 0.3), o = g.apply(0.2, 0.7, 0.3), after = ColorGrade.hsl(o.0, o.1, o.2)
        #expect(after.l > base.l + 0.05)
    }

    @Test func perChannelCurvesChangeOnlyThatChannel() {
        var g = ColorGrade(); g.redCurve = ToneCurve(points: [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.7), CGPoint(x: 1, y: 1)])
        let o = g.apply(0.5, 0.5, 0.5)
        #expect(o.0 > 0.65 && abs(o.1 - 0.5) < 1e-6 && abs(o.2 - 0.5) < 1e-6)
        var m = ColorGrade(); m.rgbCurve = ToneCurve.presets["contrast"]!
        let d = m.apply(0.25, 0.25, 0.25)
        #expect(d.0 < 0.25 && d.0 == d.1 && d.1 == d.2)                                  // master curve moves all channels equally
    }

    @Test func curvePresetsExistAndSliderCurveIsMonotone() {
        for (name, p) in ColorGrade.curvePresets { #expect(!(p.rgb.isIdentity && p.r.isIdentity && p.g.isIdentity && p.b.isIdentity), "\(name)") }
        let c = ColorGrade.curve(shadows: 1, mids: -1, highlights: 1)
        let l = c.lut; #expect(zip(l, l.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(ColorGrade.curve(shadows: 0, mids: 0, highlights: 0).isIdentity || ColorGrade.curve(shadows: 0, mids: 0, highlights: 0).lut == ToneCurve().lut)
    }

    @Test func splitToneTintsShadowsAndHighlightsDifferently() {
        var g = ColorGrade(); g.shadows = .init(hue: 240, sat: 1); g.highlights = .init(hue: 30, sat: 1)       // blue shadows, orange highlights
        let dark = g.apply(0.1, 0.1, 0.1), light = g.apply(0.9, 0.9, 0.9)
        #expect(dark.2 > dark.0 && light.0 > light.2)
        #expect(ColorGrade().apply(0.1, 0.1, 0.1) == (0.1, 0.1, 0.1))
    }

    @Test func balanceFavoursOneSide() {
        var g = ColorGrade(); g.shadows = .init(hue: 240, sat: 1); g.highlights = .init(hue: 30, sat: 1)
        var hi = g; hi.balance = 1
        let a = g.apply(0.1, 0.1, 0.1), b = hi.apply(0.1, 0.1, 0.1)
        #expect(b.2 - b.0 < a.2 - a.0)                                                  // balance toward highlights weakens the shadow tint
    }

    @Test func posterizeQuantizes() {
        var g = ColorGrade(); g.posterize = 3
        let o = g.apply(0.3, 0.6, 0.9)
        for v in [o.0, o.1, o.2] { #expect([0.0, 0.5, 1.0].contains { abs($0 - v) < 1e-9 }) }
        g.posterize = 1
        let off = g.apply(0.3, 0.6, 0.9)
        #expect(abs(off.0 - 0.3) < 1e-9 && abs(off.1 - 0.6) < 1e-9 && abs(off.2 - 0.9) < 1e-9)       // below 2 levels: off
    }

    @Test func gradeIsADocumentOperationThatRenders() throws {
        var d = EditDocument(); d.grade.bands[0] = .init(hue: 0, sat: 1, lum: 0); d.grade.posterize = 4
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).grade == d.grade)
        let img = CIImage(color: CIColor(red: 0.8, green: 0.3, blue: 0.3)).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        #expect(Renderer.render(img, document: d).extent == img.extent)
        d.grade = ColorGrade(); #expect(d.operations.isEmpty)
    }

    // MARK: eyedropper and palette
    @Test func eyedropperReadsAPixelAndRejectsOutsidePoints() throws {
        let two = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 50, y: 0, width: 50, height: 100)).composited(over: CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)))
        let l = try #require(ColorSampler.sample(two, at: CGPoint(x: 10, y: 50))), r = try #require(ColorSampler.sample(two, at: CGPoint(x: 90, y: 50)))
        #expect(l.r > 0.95 && l.b < 0.05 && r.b > 0.95 && r.r < 0.05)
        #expect(ColorSampler.sample(two, at: CGPoint(x: 500, y: 5)) == nil)
        #expect(ColorSampler.sample(two, at: CGPoint(x: 0, y: 0)) != nil)
    }

    @Test func paletteListsDominantColorsMostCommonFirst() {
        let base = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let img = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 25, height: 100)).composited(over: base)
        let p = ColorSampler.palette(img, count: 3)
        #expect(p.count == 2)
        #expect(p[0].r > 0.9 && p[0].b < 0.1 && p[1].b > 0.9)                           // red (75%) before blue (25%)
        #expect(ColorSampler.palette(img, count: 0).isEmpty && ColorSampler.palette(CIImage(color: .clear).cropped(to: .zero)).isEmpty)
    }
}
