import CoreImage
import Testing
@testable import Lumi

struct RendererTests {
    static let ctx = CIContext(options: [.useSoftwareRenderer: true])

    static func solid(_ v: CGFloat, size: CGFloat = 8) -> CIImage {
        CIImage(color: CIColor(red: v, green: v, blue: v)).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
    }

    static func pixel(_ img: CIImage) -> [UInt8] {
        var p = [UInt8](repeating: 0, count: 4)
        ctx.render(img, toBitmap: &p, rowBytes: 4, bounds: CGRect(x: 1, y: 1, width: 1, height: 1),
                   format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return p
    }

    @Test func zeroExposureReturnsSameImage() {
        let i = Self.solid(0.3)
        #expect(Renderer.render(i, exposure: 0).extent == i.extent)
        #expect(Self.pixel(Renderer.render(i, exposure: 0)) == Self.pixel(i))
    }

    @Test func positiveExposureBrightensNegativeDarkens() {
        let i = Self.solid(0.3)
        let base = Self.pixel(i)[0]
        #expect(Self.pixel(Renderer.render(i, exposure: 1))[0] > base)
        #expect(Self.pixel(Renderer.render(i, exposure: -1))[0] < base)
    }

    @Test func renderIsDeterministic() {
        let i = Self.solid(0.4)
        #expect(Self.pixel(Renderer.render(i, exposure: 0.7)) == Self.pixel(Renderer.render(i, exposure: 0.7)))
    }

    @Test func exposureKeepsExtent() {
        #expect(Renderer.render(Self.solid(0.5, size: 20), exposure: 2).extent == CGRect(x: 0, y: 0, width: 20, height: 20))
    }

    @Test func proxyDownscalesLongestSide() {
        let p = Renderer.proxy(Self.solid(0.5, size: 400), maxDimension: 100)
        #expect(abs(p.extent.width - 100) < 0.5 && abs(p.extent.height - 100) < 0.5)
    }

    @Test func proxyNeverUpscalesAndKeepsAspect() {
        let small = Self.solid(0.5, size: 50)
        #expect(Renderer.proxy(small, maxDimension: 100).extent == small.extent)
        let wide = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 200))
        let p = Renderer.proxy(wide, maxDimension: 100)
        #expect(abs(p.extent.width / p.extent.height - 2) < 0.02)
    }
}
