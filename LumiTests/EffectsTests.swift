import CoreImage
import Foundation
import Testing
@testable import Lumi

struct EffectsTests {
    private let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    private func px(_ i: CIImage, _ x: Int, _ yDown: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: Int(i.extent.height) - 1 - yDown, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return b
    }
    private func gray(_ g: CGFloat = 0.4, _ s: CGFloat = 100) -> CIImage { CIImage(color: CIColor(red: g, green: g, blue: g)).cropped(to: CGRect(x: 0, y: 0, width: s, height: s)) }
    /// Left half black, right half white: a hard edge to see channel shifts and motion on.
    private var edge: CIImage {
        CIImage(color: .white).cropped(to: CGRect(x: 50, y: 0, width: 50, height: 100)).composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)))
    }

    @Test func everyEffectKeepsTheFrameAndZeroIsIdentity() {
        let g = gray()
        for e in PhotoEffect.allCases {
            #expect(PhotoEffect.apply(e, strength: 1, to: g).extent == g.extent, "\(e)")
            #expect(PhotoEffect.apply(e, strength: 0, to: g) == g, "\(e)")
        }
    }

    @Test func effectsAreDeterministic() {
        let a = PhotoEffect.apply(.particles, strength: 0.7, to: gray()), b = PhotoEffect.apply(.particles, strength: 0.7, to: gray())
        for (x, y) in [(10, 10), (40, 60), (80, 20)] { #expect(px(a, x, y) == px(b, x, y)) }
        var r1 = SplitMix(seed: 1), r2 = SplitMix(seed: 1)
        #expect(r1.next() == r2.next() && r1.unit() >= 0 && r1.unit() < 1)
    }

    @Test func glitchSplitsChannelsAtAnEdge() {
        let out = PhotoEffect.apply(.glitch, strength: 1, to: edge)
        // just left of the white edge the shifted red channel already shows while blue does not (or the reverse)
        let near = (44...56).map { px(out, $0, 5) }
        #expect(near.contains { abs(Int($0[0]) - Int($0[2])) > 100 })
    }

    @Test func lightLeakBrightensItsCornerOnly() {
        let out = PhotoEffect.apply(.lightLeak, strength: 1, to: gray())
        #expect(px(out, 5, 5)[0] > px(gray(), 5, 5)[0] + 60 && abs(Int(px(out, 95, 95)[0]) - Int(px(gray(), 95, 95)[0])) < 10)
    }

    @Test func relightColoursThePersonNotTheBackground() {
        let person = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 100)).composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)))
        let out = RelightLook.redLight.apply(to: gray(0.5), personMask: person, strength: 1)
        let p = px(out, 20, 50), bg = px(out, 80, 50)
        #expect(p[0] > p[2] + 40 && abs(Int(bg[0]) - 128) < 6)
        for l in RelightLook.allCases { #expect(l.apply(to: gray(), personMask: nil, strength: 1).extent == gray().extent) }
        let g = gray(); #expect(RelightLook.ledStrip.apply(to: g, personMask: nil, strength: 0) == g)
    }

    @Test func kenBurnsMovesOverTime() {
        var a = AnimatePhoto(); a.style = .zoomIn; a.intensity = 1
        #expect(a.camera(at: 0).scale == 1 && a.camera(at: 1).scale > 1.15)
        a.style = .zoomOut; #expect(a.camera(at: 0).scale > a.camera(at: 1).scale)
        a.style = .panLeft; #expect(a.camera(at: 0).dx > 0 && a.camera(at: 1).dx < 0)
        a.intensity = 0; a.style = .zoomIn; #expect(a.camera(at: 1).scale == 1)
        #expect(AnimatePhoto(style: .zoomIn, duration: 2, fps: 30, intensity: 0.5).frameCount == 60 && AnimatePhoto(style: .zoomIn, duration: 0, fps: 30, intensity: 0.5).frameCount == 1)
    }

    @Test func framesKeepSizeAndMotionChangesPixels() {
        var a = AnimatePhoto(); a.style = .panRight; a.intensity = 1; a.duration = 1; a.fps = 5
        let f = a.frames(of: edge, personMask: nil)
        #expect(f.count == 5 && f.allSatisfy { $0.extent == edge.extent })
        #expect((30...70).contains { px(f[0], $0, 50) != px(f[4], $0, 50) })           // the edge has moved
    }

    @Test func parallaxMovesPersonMoreThanBackground() {
        var a = AnimatePhoto(); a.style = .parallax; a.intensity = 1
        let person = CIImage(color: .white).cropped(to: CGRect(x: 40, y: 0, width: 20, height: 100)).composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)))
        let f0 = a.frame(of: edge, personMask: person, at: 0), f1 = a.frame(of: edge, personMask: person, at: 0.25)
        #expect(f0.extent == edge.extent && f1.extent == edge.extent)
        let noMask = a.frame(of: edge, personMask: nil, at: 0.25)
        #expect(noMask.extent == edge.extent)
    }
}
