import CoreImage
import Testing
@testable import Lumi

struct NailRegionsTests {
    struct Fake: HandFinding {
        var hands: [[[CGPoint]]]
        func fingertips(in image: CIImage) throws -> [[[CGPoint]]] { hands }
    }
    struct Boom: HandFinding, Error { func fingertips(in image: CIImage) throws -> [[[CGPoint]]] { throw Boom() } }
    private let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    private func px(_ i: CIImage, _ x: Int, _ y: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: Int(i.extent.height) - 1 - y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return b
    }
    private let finger = [CGPoint(x: 0.5, y: 0.6), CGPoint(x: 0.5, y: 0.4)]      // pointing up the picture

    @Test func nailSitsAtTheFingertip() {
        let n = NailRegions.nails(from: [finger])
        #expect(n.count == 1)
        #expect(abs(n[0].center.x - 0.5) < 0.001 && n[0].center.y > 0.4 && n[0].center.y < 0.5)
        #expect(n[0].length > n[0].width)
    }

    @Test func degenerateFingersAreSkipped() {
        #expect(NailRegions.nails(from: [[CGPoint(x: 0.5, y: 0.5)], [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.5, y: 0.5)]]).isEmpty)
    }

    @Test func noHandOrFinderErrorGivesNoNails() {
        let img = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(NailRegions.find(in: img, finder: Fake(hands: [])).isEmpty)
        #expect(NailRegions.find(in: img, finder: Boom()).isEmpty)
        #expect(NailRegions.find(in: img, finder: Fake(hands: [[finger], [finger]])).count == 2)
    }

    @Test func colorLandsOnTheNailOnly() {
        let img = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let nails = NailRegions.nails(from: [finger])
        let out = NailRenderer.apply(nails, color: CIColor(red: 1, green: 0, blue: 0), opacity: 1, to: img)
        let c = nails[0].center
        #expect(px(out, Int(c.x * 200), Int(c.y * 200))[0] > 230)
        #expect(px(out, 10, 10)[1] > 120 && px(out, 10, 10)[0] < 140)               // far away: untouched
        #expect(NailRenderer.apply([], color: .red, opacity: 1, to: img).extent == img.extent)
    }

    @Test func zeroOpacityIsNoOp() {
        let img = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(NailRenderer.apply(NailRegions.nails(from: [finger]), color: .red, opacity: 0, to: img) == img)
    }
}
