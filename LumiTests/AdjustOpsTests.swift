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
