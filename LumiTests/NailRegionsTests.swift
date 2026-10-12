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

    @Test func everyFinishPaintsTheNailAndLeavesTheRestAlone() {
        let img = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let nails = NailRegions.nails(from: [finger])
        let c = nails[0].center
        for f in NailPaint.Finish.allCases {
            var p = NailPaint(); p.finish = f; p.opacity = 1; p.color = RGBA(r: 0.9, g: 0.1, b: 0.2, a: 1)
            let out = NailRenderer.paint(nails, p, to: img)
            #expect(out.extent == img.extent, "\(f)")
            #expect(px(out, 10, 10) == px(img, 10, 10), "\(f)")
            // somewhere on the nail the picture changed
            let changed = stride(from: -8, through: 8, by: 2).contains { d in px(out, Int(c.x * 200), Int(c.y * 200) + d) != px(img, Int(c.x * 200), Int(c.y * 200) + d) }
            #expect(changed, "\(f)")
        }
        #expect(NailRenderer.paint([], NailPaint(color: RGBA(), finish: .cream, opacity: 1), to: img) == img)
        #expect(NailRenderer.paint(nails, NailPaint(), to: img) == img)
    }

    @Test func frenchTipIsWhiteAndTheBaseIsSheer() {
        let img = CIImage(color: CIColor(red: 0.5, green: 0.4, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 400))
        let big = [Nail(center: CGPoint(x: 0.5, y: 0.5), width: 0.3, length: 0.4, angle: -.pi / 2)]       // pointing up the picture
        var p = NailPaint(); p.finish = .french; p.opacity = 1
        let out = NailRenderer.paint(big, p, to: img)
        let tip = px(out, 200, Int(400 * (0.5 - 0.17))), base = px(out, 200, Int(400 * (0.5 + 0.12)))
        #expect(tip[0] > 220 && tip[1] > 220 && base[0] < 200)
    }

    @Test func nailPaintInTheDocumentPaintsFromHandPose() {
        let img = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))
        let saved = (Renderer.services.handFinder, Renderer.services.faceLandmarker)
        defer { (Renderer.services.handFinder, Renderer.services.faceLandmarker) = saved }
        Renderer.services.faceLandmarker = nil
        Renderer.services.handFinder = Fake(hands: [[finger]])
        var d = EditDocument(); var f = FaceRetouch(); f.nails.opacity = 1; f.nails.finish = .cream; d.face = f
        let out = Renderer.render(img, document: d)
        let c = NailRegions.nails(from: [finger])[0].center
        #expect(px(out, Int(c.x * 200), Int(c.y * 200))[0] != px(img, Int(c.x * 200), Int(c.y * 200))[0] || px(out, Int(c.x * 200), Int(c.y * 200))[1] != px(img, Int(c.x * 200), Int(c.y * 200))[1])
        Renderer.services.handFinder = Fake(hands: [])
        #expect(Renderer.render(img, document: d).extent == img.extent)                       // no hand: nothing painted, no crash
    }
}
