import CoreImage
import Foundation
import Testing
@testable import Lumi

struct OverlayVideoTests {
    private let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    private func px(_ i: CIImage, _ x: Int, _ yDown: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: Int(i.extent.height) - 1 - yDown, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return b
    }
    private func solid(_ c: CIColor, _ w: CGFloat = 100, _ h: CGFloat = 100) -> CIImage { CIImage(color: c).cropped(to: CGRect(x: 0, y: 0, width: w, height: h)) }

    @Test func pipLandsAtItsCenterWithOpacityAndTiming() {
        var p = PiP(); p.center = CGPoint(x: 0.5, y: 0.5); p.width = 0.4; p.shape = .rect; p.start = 1; p.end = 3
        let frame = solid(CIColor(red: 0, green: 0, blue: 0), 200, 200)
        let out = PiPRenderer.draw(solid(CIColor(red: 1, green: 0, blue: 0)), p, on: frame)
        #expect(px(out, 100, 100)[0] > 250 && px(out, 10, 10)[0] < 5)
        p.opacity = 0.5
        let half = PiPRenderer.draw(solid(CIColor(red: 1, green: 0, blue: 0)), p, on: frame)
        #expect(abs(Int(px(half, 100, 100)[0]) - 128) < 8)
        #expect(!p.isActive(at: 0.5) && p.isActive(at: 1) && !p.isActive(at: 3))
        #expect(PiPRenderer.draw(CIImage(color: .clear).cropped(to: .zero), p, on: frame) == frame)
    }

    @Test func blendModesChangeTheResult() {
        var p = PiP(); p.center = CGPoint(x: 0.5, y: 0.5); p.width = 1; p.shape = .rect
        let frame = solid(CIColor(red: 0.5, green: 0.5, blue: 0.5)), top = solid(CIColor(red: 0.5, green: 0.5, blue: 0.5))
        let normal = px(PiPRenderer.draw(top, p, on: frame), 50, 50)[0]
        p.blend = .multiply
        let mult = px(PiPRenderer.draw(top, p, on: frame), 50, 50)[0]
        #expect(mult < normal - 40)
        for b in PiP.Blend.allCases { p.blend = b; #expect(CIFilter(name: p.filterName) != nil) }
    }

    @Test func shapeMasksCutTheCorners() {
        let img = solid(CIColor(red: 1, green: 1, blue: 1))
        let circle = Masks.apply(.circle, to: img)
        #expect(px(circle, 50, 50)[3] > 250 && px(circle, 1, 1)[3] < 5)
        #expect(Masks.apply(.rect, to: img) == img)
        #expect(px(Masks.apply(.rounded, to: img), 1, 1)[3] < 100)
        #expect(px(Masks.apply(.heart, to: img), 50, 40)[3] > 200 && px(Masks.apply(.heart, to: img), 1, 1)[3] < 5)
    }

    struct Scripted: ObjectTracking {
        var script: [CGRect?]
        mutating func next(frame: CIImage) -> CGRect? { script.isEmpty ? nil : script.removeFirst() }
    }

    @Test func trackRecordsHoldsThroughGapsAndSmooths() {
        let f = solid(.black)
        let boxes: [CGRect?] = [CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), nil, CGRect(x: 0.3, y: 0.1, width: 0.2, height: 0.2), nil]
        let t = ObjectTrack.record(frames: Array(repeating: f, count: 4), start: boxes[0]!, fps: 10, tracker: Scripted(script: boxes))
        #expect(t.boxes.count == 4 && t.box(at: 0.1)?.minX == 0.1)               // gap holds the last box
        #expect(t.box(at: 0.2)?.minX == 0.3 && t.box(at: 99)?.minX == 0.3 && t.box(at: -1)?.minX == 0.1)
        let c = t.centers(radius: 1)
        #expect(c[1] == nil && c[0] != nil && c[2] != nil)
        #expect(ObjectTrack(fps: 10, boxes: [nil, CGRect(x: 0, y: 0, width: 1, height: 1)]).box(at: 0) == nil)
        #expect(ObjectTrack(fps: 0, boxes: [CGRect.zero]).box(at: 0) == nil)
    }

    @Test func attachedOverlayFollowsTheObject() {
        let t = ObjectTrack(fps: 10, boxes: [CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), CGRect(x: 0.5, y: 0.5, width: 0.2, height: 0.2)])
        let a = t.attachedCenter(at: 0, offset: CGPoint(x: 0, y: -0.2))!, b = t.attachedCenter(at: 0.1, offset: CGPoint(x: 0, y: -0.2))!
        #expect(abs(a.x - 0.2) < 1e-9 && abs(a.y - 0.0) < 1e-9 && abs(b.x - 0.6) < 1e-9)
    }

    @Test func matteSmootherBlendsWithPreviousFrame() {
        var s = MatteSmoother(); s.weight = 0.5
        let white = solid(CIColor(red: 1, green: 1, blue: 1)), black = solid(CIColor(red: 0, green: 0, blue: 0))
        #expect(px(s.smooth(white), 5, 5)[0] > 250)                 // first frame passes through
        let second = s.smooth(black)
        #expect(abs(Int(px(second, 5, 5)[0]) - 128) < 8)           // half old, half new
        s.reset(); #expect(px(s.smooth(black), 5, 5)[0] < 5)
    }
}
