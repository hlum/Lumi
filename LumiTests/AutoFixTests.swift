import CoreImage
import Testing
@testable import Lumi

struct AutoFixTests {
    /// n pixels of one colour, as RGBA bytes.
    private func pixels(_ r: UInt8, _ g: UInt8, _ b: UInt8, n: Int = 400) -> [UInt8] { (0..<n).flatMap { _ in [r, g, b, 255] } }
    private func fix(_ rgb: [UInt8]) -> AdjustParams { AutoFix.params(for: AutoFix.measure(rgb: rgb)!) }

    @Test func darkPicturesGetLifted() {
        let p = fix(pixels(40, 40, 40))
        #expect(p.exposure > 0.2)
    }

    @Test func brightPicturesGetPulledDown() {
        #expect(fix(pixels(235, 235, 235)).exposure < -0.1)
    }

    @Test func aWellExposedPictureIsLeftAlone() {
        // a smooth ramp from 10 to 245 with a mid median and full range
        var ramp: [UInt8] = []
        for v in 0..<256 { let g = UInt8(10 + v * 235 / 255); ramp += [g, g, g, 255] }
        let p = fix(ramp)
        #expect(abs(p.exposure) < 0.15 && abs(p.whites) < 0.15 && p.blacks > -0.2 && abs(p.contrast) < 0.1)
    }

    @Test func flatLowContrastGetsContrastAndRange() {
        var flat: [UInt8] = []
        for v in 0..<256 { let g = UInt8(100 + v * 60 / 255); flat += [g, g, g, 255] }
        let p = fix(flat)
        #expect(p.contrast > 0.1)
        #expect(p.whites > 0 && p.blacks < 0)
    }

    @Test func colourCastsAreNeutralisedTheRightWay() {
        let blue = fix(pixels(90, 120, 170))
        #expect(blue.temperature > 0.05)                        // too blue: warm it
        let orange = fix(pixels(170, 120, 90))
        #expect(orange.temperature < -0.05)                     // too warm: cool it
        let green = fix(pixels(110, 150, 110))
        #expect(green.tint > 0)                                 // too green: positive tint moves toward magenta, as in other editors
    }

    @Test func dullColourGetsAHintOfVibrance() {
        #expect(fix(pixels(120, 118, 119)).vibrance > 0)
        #expect(fix(pixels(220, 60, 60)).vibrance == 0)
    }

    @Test func valuesStayGentleAndEmptyInputIsNil() {
        for rgb in [pixels(0, 0, 0), pixels(255, 255, 255), pixels(255, 0, 0), pixels(0, 0, 255)] {
            let p = fix(rgb)
            for k in AdjustParams.Key.allCases { #expect(abs(p[k]) <= 0.5 + 1e-9, "\(k)") }
        }
        #expect(AutoFix.measure(rgb: []) == nil)
    }

    @Test func imageEntryPointWorksOnARealPicture() {
        let dark = CIImage(color: CIColor(red: 0.05, green: 0.05, blue: 0.05)).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(AutoFix.params(for: dark).exposure > 0.2)
        #expect(AutoFix.params(for: CIImage(color: .black).cropped(to: .zero)) == AdjustParams())
    }
}

struct TintDirectionTests {
    @Test func positiveTintMovesTowardMagentaAndNegativeTowardGreen() {
        let ctx = CIContext()
        let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
        func px(_ p: AdjustParams) -> [Int] { var b = [UInt8](repeating: 0, count: 4); ctx.render(AdjustOps.apply(p, to: grey), toBitmap: &b, rowBytes: 4, bounds: CGRect(x: 2, y: 2, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)); return b.map(Int.init) }
        let magenta = px(AdjustParams(tint: 0.5)), green = px(AdjustParams(tint: -0.5))
        #expect(magenta[1] < magenta[0] && magenta[1] < magenta[2])
        #expect(green[1] > green[0] && green[1] > green[2])
    }
}
