import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Lumi

struct LiveConvertTests {
    @Test func gifTimesAreEvenAndCapped() {
        let t = LiveConvert.gifTimes(duration: 3, fps: 10)
        #expect(t.count == 30 && t[0] == 0 && abs(t[1] - 0.1) < 1e-9 && t.last! < 3)
        #expect(LiveConvert.gifTimes(duration: 60, fps: 30).count == LiveConvert.maxGIFFrames)
        #expect(LiveConvert.gifTimes(duration: 0, fps: 10).isEmpty && LiveConvert.gifTimes(duration: 3, fps: 0).isEmpty)
        #expect(LiveConvert.gifTimes(duration: 0.01, fps: 10).count == 1)
    }

    @Test func liveWindowCentersOnTheKeyFrameAndStaysInside() {
        let mid = LiveConvert.liveWindow(videoDuration: 10, keyTime: 5)!
        #expect(mid.start == 3.5 && mid.end == 6.5 && mid.key == 1.5)
        let early = LiveConvert.liveWindow(videoDuration: 10, keyTime: 0.2)!
        #expect(early.start == 0 && early.end == 3 && abs(early.key - 0.2) < 1e-9)
        let late = LiveConvert.liveWindow(videoDuration: 10, keyTime: 99)!
        #expect(late.end == 10 && late.start == 7 && late.key == 3)
        let short = LiveConvert.liveWindow(videoDuration: 1.5, keyTime: 1)!
        #expect(short.start == 0 && short.end == 1.5)
        #expect(LiveConvert.liveWindow(videoDuration: 0, keyTime: 1) == nil)
    }

    @Test func slideshowTimes() {
        let s = LiveConvert.slideshow(count: 4, perPhoto: 0.5)
        #expect(s.duration == 2 && s.starts == [0, 0.5, 1, 1.5])
        #expect(LiveConvert.slideshow(count: 0).starts.isEmpty)
    }

    @Test func gifEncoderWritesEveryFrameWithTheRightDelay() throws {
        func frame(_ g: CGFloat) -> CGImage {
            let c = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            c.setFillColor(gray: g, alpha: 1); c.fill(CGRect(x: 0, y: 0, width: 20, height: 20)); return c.makeImage()!
        }
        let data = try #require(GIFMaker.encode([frame(0), frame(0.5), frame(1)], options: .init(fps: 10, maxSide: 480, loopCount: 0)))
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(src) == 3)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 1, nil) as? [CFString: Any]
        let delay = (props?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFDelayTime] as? Double
        #expect(abs((delay ?? 0) - 0.1) < 0.001)
        #expect(GIFMaker.encode([], options: .init()) == nil && GIFMaker.encode([frame(0)], options: .init(fps: 0, maxSide: 100, loopCount: 0)) == nil)
    }

    @Test func liveTextsAreLimitedToThree() {
        var l = LiveOverlays()
        for i in 0..<3 { let ok = l.add(VideoOverlay(content: .text("t\(i)"), start: 0, end: 2)); #expect(ok) }
        let fourth = l.add(VideoOverlay(content: .text("fourth"), start: 0, end: 2))
        #expect(!fourth && l.textCount == 3)
        let sticker = l.add(VideoOverlay(content: .sticker("heart"), start: 0, end: 2))
        #expect(sticker && l.items.count == 4)                                   // stickers don't count
        l.remove(l.items[0].id)
        let again = l.add(VideoOverlay(content: .text("again"), start: 0, end: 2)); #expect(again)
    }

    @Test func overlayTimesStayInsideTheClip() {
        var l = LiveOverlays()
        l.add(VideoOverlay(content: .sticker("star"), start: -1, end: 9))
        #expect(l.items[0].start == 0 && l.items[0].end == 3)
        #expect(l.active(at: 1).count == 1 && l.active(at: 3).isEmpty)
    }
}
