import CoreImage
import Testing
@testable import Lumi

struct KeyframeTests {
    @Test func emptyTrackUsesDefaultAndHoldsOutsideKeys() {
        var t = Track()
        #expect(t.value(at: 5, default: 0.7) == 0.7)
        t.set(10, at: 1); t.set(20, at: 3)
        #expect(t.value(at: 0, default: 0) == 10 && t.value(at: 9, default: 0) == 20)
    }

    @Test func interpolatesAndSortsKeys() {
        var t = Track()
        t.set(20, at: 3); t.set(10, at: 1)
        #expect(t.keys.map(\.time) == [1, 3])
        #expect(abs(t.value(at: 2, default: 0) - 15) < 1e-9)
        t.set(30, at: 3); #expect(t.keys.count == 2 && t.value(at: 3, default: 0) == 30)
        t.remove(at: 3); #expect(t.keys.count == 1)
    }

    @Test func easingShapesAndHold() {
        var t = Track(); t.set(0, at: 0, ease: .easeIn); t.set(100, at: 1)
        #expect(abs(t.value(at: 0.5, default: 0) - 25) < 1e-9)
        var o = Track(); o.set(0, at: 0, ease: .easeOut); o.set(100, at: 1)
        #expect(abs(o.value(at: 0.5, default: 0) - 75) < 1e-9)
        var h = Track(); h.set(5, at: 0, ease: .hold); h.set(9, at: 1)
        #expect(h.value(at: 0.99, default: 0) == 5)
        for e in [Track.Ease.linear, .easeIn, .easeOut, .easeInOut] { #expect(Track.curve(e, 0) == 0 && Track.curve(e, 1) == 1) }
    }

    @Test func poseFallsBackToBaseAndClampsOpacity() {
        var k = Keyframes(); k.opacity.set(3, at: 0)
        let p = k.pose(at: 1)
        #expect(p.opacity == 1 && p.x == 0.5 && p.scale == 1)
        k.x.set(0.2, at: 0); k.x.set(0.8, at: 2)
        #expect(abs(k.pose(at: 1).x - 0.5) < 1e-9)
    }

    private func overlay(_ a: VideoOverlay.Animation = .none, out: VideoOverlay.Animation = .none) -> VideoOverlay {
        VideoOverlay(content: .text("hi"), start: 2, end: 6, animationIn: a, animationOut: out)
    }

    @Test func activeOnlyBetweenStartAndEnd() {
        let o = overlay()
        #expect(OverlayTimeline.pose(o, at: 1.9) == nil && OverlayTimeline.pose(o, at: 6) == nil && OverlayTimeline.pose(o, at: 2) != nil)
        #expect(OverlayTimeline.active([o], at: 3).count == 1 && OverlayTimeline.active([o], at: 7).isEmpty)
    }

    @Test func inAnimationsStartHiddenAndEndAtRest() {
        for a in VideoOverlay.Animation.allCases where a != .none {
            let o = overlay(a)
            let start = OverlayTimeline.pose(o, at: 2.0)!, rest = OverlayTimeline.pose(o, at: 4)!
            #expect(rest == Keyframes.Pose(x: 0.5, y: 0.5, scale: 1, rotation: 0, opacity: 1), "\(a)")
            #expect(start != rest, "\(a)")
        }
        #expect(OverlayTimeline.pose(overlay(.fade), at: 2.0)!.opacity == 0)
    }

    @Test func outAnimationFadesTowardTheEnd() {
        let o = overlay(out: .fade)
        #expect(OverlayTimeline.pose(o, at: 4)!.opacity == 1)
        #expect(OverlayTimeline.pose(o, at: 5.99)!.opacity < 0.05)
    }

    @Test func keyframesAreRelativeToStart() {
        var o = overlay(); o.keyframes.x.set(0.2, at: 0); o.keyframes.x.set(0.8, at: 4)
        #expect(abs(OverlayTimeline.pose(o, at: 4)!.x - 0.5) < 1e-9)
    }

    @Test func drawPlacesContentAtPose() {
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        let frame = CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        let dot = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 10, height: 10))
        let out = OverlayTimeline.draw(dot, pose: .init(x: 0.25, y: 0.25, scale: 1, rotation: 0, opacity: 1), on: frame)
        func px(_ x: Int, _ yDown: Int) -> UInt8 { var b = [UInt8](repeating: 0, count: 4); ctx.render(out, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: 99 - yDown, width: 1, height: 1), format: .RGBA8, colorSpace: nil); return b[0] }
        #expect(px(25, 25) > 250 && px(75, 75) < 5)
        let none = OverlayTimeline.draw(dot, pose: .init(x: 0.25, y: 0.25, scale: 1, rotation: 0, opacity: 0), on: frame)
        #expect(none == frame)
    }
}
