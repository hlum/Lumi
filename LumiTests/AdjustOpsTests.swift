import CoreImage
import Foundation
import Testing
@testable import Lumi

struct AdjustOpsTests {
    static func px(_ p: AdjustParams, base: CGFloat = 0.4) -> [UInt8] {
        RendererTests.pixel(AdjustOps.apply(p, to: RendererTests.solid(base)))
    }

    @Test func identityDoesNothing() {
        #expect(AdjustParams().isIdentity)
        #expect(Self.px(AdjustParams()) == RendererTests.pixel(RendererTests.solid(0.4)))
    }

    @Test func brightnessMovesBothWays() {
        let base = Self.px(AdjustParams())[0]
        #expect(Self.px(AdjustParams(brightness: 0.5))[0] > base)
        #expect(Self.px(AdjustParams(brightness: -0.5))[0] < base)
    }

    @Test func brightnessKeepsBlackAndWhitePinned() {
        // an additive offset lifts black and looks faded; brightness must not
        for b in [0.6, 1.0] {
            #expect(Self.px(AdjustParams(brightness: b), base: 0)[0] <= 2)
            #expect(Self.px(AdjustParams(brightness: b), base: 1)[0] >= 253)
        }
        #expect(Self.px(AdjustParams(brightness: -1), base: 1)[0] >= 253)
        #expect(Self.px(AdjustParams(brightness: 1), base: 0.5)[0] > Self.px(AdjustParams(), base: 0.5)[0] + 20)
    }

    @Test func contrastSpreadsAroundMid() {
        #expect(Self.px(AdjustParams(contrast: 1), base: 0.8)[0] > Self.px(AdjustParams(), base: 0.8)[0])
        #expect(Self.px(AdjustParams(contrast: 1), base: 0.2)[0] < Self.px(AdjustParams(), base: 0.2)[0])
    }

    @Test func fullDesaturationGivesGray() {
        let img = CIImage(color: CIColor(red: 0.9, green: 0.2, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        let p = RendererTests.pixel(AdjustOps.apply(AdjustParams(saturation: -1), to: img))
        #expect(abs(Int(p[0]) - Int(p[1])) < 3 && abs(Int(p[1]) - Int(p[2])) < 3)
    }

    @Test func warmShiftsRedOverBlue() {
        let p = Self.px(AdjustParams(temperature: 1))
        let c = Self.px(AdjustParams(temperature: -1))
        #expect(Int(p[0]) - Int(p[2]) > Int(c[0]) - Int(c[2]))
    }

    @Test func fadeLiftsBlack() {
        #expect(Self.px(AdjustParams(fade: 1), base: 0)[0] > 10)
    }

    @Test func vignetteDarkensCornersOfLargeImage() {
        let img = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let out = AdjustOps.apply(AdjustParams(vignette: 1), to: img)
        func at(_ x: Int, _ y: Int) -> UInt8 {
            var p = [UInt8](repeating: 0, count: 4)
            RendererTests.ctx.render(out, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return p[0]
        }
        #expect(at(1, 1) < at(100, 100))
    }

    @Test func outputKeepsExtentForEveryParameter() {
        for k in AdjustParams.Key.allCases {
            var p = AdjustParams(); p[k] = 0.5
            #expect(AdjustOps.apply(p, to: RendererTests.solid(0.4, size: 30)).extent == CGRect(x: 0, y: 0, width: 30, height: 30), "\(k)")
        }
    }

    @Test func subscriptClampsToRange() {
        var p = AdjustParams()
        p[.brightness] = 5; #expect(p.brightness == 1)
        p[.sharpen] = -3; #expect(p.sharpen == 0)
        p[.vignette] = 9; #expect(p.vignette == 1)
    }

    @Test func resetSingleSliderLeavesOthers() {
        var p = AdjustParams(brightness: 0.3, contrast: 0.2)
        p.reset(.brightness)
        #expect(p.brightness == 0 && p.contrast == 0.2)
    }

    @Test func presetsAreNonIdentityAndInRange() {
        for (name, p) in AdjustParams.presets {
            #expect(!p.isIdentity, "\(name)")
            #expect(AdjustParams.Key.allCases.allSatisfy { p[$0] >= $0.range.lowerBound && p[$0] <= $0.range.upperBound })
        }
    }

    @Test func valuesPersistThroughDocument() throws {
        var d = EditDocument(); d.adjust = AdjustParams(brightness: 0.2, shadows: 0.4)
        let back = try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d))
        #expect(back.adjust == d.adjust)
        d.adjust = AdjustParams()
        #expect(d.operations.isEmpty)
    }

    @Test func rendererAppliesAdjustAfterOtherOps() {
        var d = EditDocument(); d.exposure = 0.5; d.adjust = AdjustParams(brightness: 0.4)
        let img = RendererTests.solid(0.3)
        #expect(RendererTests.pixel(Renderer.render(img, document: d))[0] > RendererTests.pixel(Renderer.render(img, exposure: 0.5))[0])
    }
}

struct AdjustProSliderTests {
    private let ctx = CIContext()            // the app's own setup: linear working space, sRGB out
    private func px(_ i: CIImage, _ x: Int, _ yDown: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: Int(i.extent.height) - 1 - yDown, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return b
    }
    private func flat(_ g: CGFloat, _ s: CGFloat = 100) -> CIImage { CIImage(color: CIColor(red: g, green: g, blue: g)).cropped(to: CGRect(x: 0, y: 0, width: s, height: s)) }
    /// Dark left half, light right half, so local contrast has an edge to work on.
    private func edge(_ lo: CGFloat = 0.4, _ hi: CGFloat = 0.6) -> CIImage {
        CIImage(color: CIColor(red: hi, green: hi, blue: hi)).cropped(to: CGRect(x: 50, y: 0, width: 50, height: 100)).composited(over: flat(lo))
    }
    private func step(_ i: CIImage) -> Int { Int(px(i, 51, 50)[0]) - Int(px(i, 48, 50)[0]) }     // right at the edge, where local contrast shows

    @Test func exposureBrightensAndDarkens() {
        let base = Int(px(AdjustOps.apply(AdjustParams(), to: flat(0.3)), 5, 5)[0])
        #expect(Int(px(AdjustOps.apply(AdjustParams(exposure: 0.5), to: flat(0.3)), 5, 5)[0]) > base + 15)
        #expect(Int(px(AdjustOps.apply(AdjustParams(exposure: -0.5), to: flat(0.3)), 5, 5)[0]) < base - 15)
    }

    @Test func whitesAndBlacksMoveTheEnds() {
        #expect(px(AdjustOps.apply(AdjustParams(whites: 1), to: flat(0.8)), 5, 5)[0] > 230)
        #expect(px(AdjustOps.apply(AdjustParams(whites: -1), to: flat(0.8)), 5, 5)[0] < 200)
        #expect(px(AdjustOps.apply(AdjustParams(blacks: 1), to: flat(0)), 5, 5)[0] > 10, "blacks \(px(AdjustOps.apply(AdjustParams(blacks: 1), to: flat(0)), 5, 5)) \(px(AdjustOps.apply(AdjustParams(blacks: 1), to: flat(0.02)), 5, 5))")
        #expect(px(AdjustOps.apply(AdjustParams(blacks: -1), to: flat(0.1)), 5, 5)[0] < px(flat(0.1), 5, 5)[0])
    }

    @Test func clarityAndTextureAddLocalContrastAndNegativeSoftens() {
        let e = edge(), base = step(e)
        #expect(step(AdjustOps.apply(AdjustParams(clarity: 1), to: e)) > base)
        #expect(step(AdjustOps.apply(AdjustParams(texture: 1), to: e)) > base)
        #expect(step(AdjustOps.apply(AdjustParams(clarity: -1), to: e)) < base)
    }

    @Test func clarityLeavesFlatAreasAlone() {
        let out = AdjustOps.apply(AdjustParams(texture: 1, clarity: 1), to: flat(0.5))
        #expect(abs(Int(px(out, 50, 50)[0]) - Int(px(flat(0.5), 50, 50)[0])) < 6)
    }

    @Test func dehazeAddsContrastToAHazyPicture() {
        let hazy = edge(0.55, 0.7)
        let out = AdjustOps.apply(AdjustParams(dehaze: 1), to: hazy)
        #expect(step(out) > step(hazy))
        #expect(px(out, 44, 50)[0] < px(hazy, 44, 50)[0])                    // the veil is taken off the dark side
        let veiled = AdjustOps.apply(AdjustParams(dehaze: -1), to: edge(0.1, 0.9))
        #expect(step(veiled) < step(edge(0.1, 0.9)))
    }

    @Test func grainAddsVarianceButKeepsAverage() {
        let g = AdjustOps.apply(AdjustParams(grain: 1), to: flat(0.5, 120))
        let samples = (0..<120).map { Int(px(g, $0, 60)[0]) }
        #expect(Set(samples).count > 8)
        #expect(abs(Double(samples.reduce(0, +)) / 120 - 128) < 20)
        #expect(Set((0..<120).map { Int(px(AdjustOps.apply(AdjustParams(), to: flat(0.5, 120)), $0, 60)[0]) }).count == 1)
    }

    @Test func contrastIsAnSCurveThatKeepsTheEnds() {
        #expect(px(AdjustOps.apply(AdjustParams(contrast: 1), to: flat(0)), 5, 5)[0] <= 2 && px(AdjustOps.apply(AdjustParams(contrast: 1), to: flat(1)), 5, 5)[0] >= 253)
        let lo = AdjustOps.apply(AdjustParams(contrast: 1), to: flat(0.3)), hi = AdjustOps.apply(AdjustParams(contrast: 1), to: flat(0.7))
        #expect(px(lo, 5, 5)[0] < px(flat(0.3), 5, 5)[0] && px(hi, 5, 5)[0] > px(flat(0.7), 5, 5)[0], "lo \(px(lo, 5, 5)) vs \(px(flat(0.3), 5, 5)) hi \(px(hi, 5, 5)) vs \(px(flat(0.7), 5, 5))")
    }

    @Test func oldDraftsWithoutTheNewFieldsStillDecode() throws {
        let old = #"{"brightness":0.2,"contrast":0.1,"saturation":0,"vibrance":0,"temperature":0,"tint":0,"highlights":0,"shadows":0.3,"sharpen":0,"vignette":0,"fade":0}"#
        let p = try JSONDecoder().decode(AdjustParams.self, from: Data(old.utf8))
        #expect(p.brightness == 0.2 && p.shadows == 0.3 && p.clarity == 0 && p.exposure == 0)
        var q = AdjustParams(); q.clarity = 0.4; q.grain = 0.2
        #expect(try JSONDecoder().decode(AdjustParams.self, from: JSONEncoder().encode(q)) == q)
        #expect(AdjustParams.Key.allCases.count == 18 && AdjustParams.Key.grain.range == 0...1)
    }

    @Test func everyPresetIsNonTrivialAndEveryKeyIsReachable() {
        for (_, p) in AdjustParams.presets { #expect(!p.isIdentity) }
        var p = AdjustParams()
        for k in AdjustParams.Key.allCases { p[k] = 0.3 }
        for k in AdjustParams.Key.allCases { #expect(p[k] == 0.3, "\(k)") }
        p[.exposure] = 9; #expect(p.exposure == 1)
    }
}
