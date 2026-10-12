import CoreImage
import Foundation
import Testing
@testable import Lumi

struct VideoEraseTests {
    private let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    private func px(_ i: CIImage, _ x: Int, _ yDown: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: Int(i.extent.height) - 1 - yDown, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return b
    }
    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage { CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)) }

    /// Fills the mask with a constant colour, ignoring the picture.
    struct Fill: Inpainting {
        var color: CIColor
        func inpaint(_ image: CIImage, mask: CIImage) throws -> CIImage {
            CIFilter(name: "CIBlendWithMask", parameters: [kCIInputImageKey: CIImage(color: color).cropped(to: image.extent), kCIInputBackgroundImageKey: image, kCIInputMaskImageKey: mask])!.outputImage!.cropped(to: image.extent)
        }
    }

    @Test func planAcceptsShortClipsOnly() {
        #expect(VideoEraser.plan(duration: 3, fps: 30) == (true, 90))
        #expect(VideoEraser.plan(duration: 20, fps: 30).accepted == false && VideoEraser.plan(duration: 0, fps: 30).accepted == false)
        #expect(VideoEraser.plan(duration: 8, fps: 60).accepted == false)         // 480 frames is over the frame cap
    }

    @Test func maskCoversTheGrownBoxOnly() {
        let m = VideoEraser.mask(box: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), grow: 0.5, extent: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(px(m, 50, 50)[0] > 250 && px(m, 38, 50)[0] > 250 && px(m, 10, 10)[0] < 5)
        let edge = VideoEraser.mask(box: CGRect(x: 0.9, y: 0.9, width: 0.3, height: 0.3), grow: 1, extent: CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(edge.extent == CGRect(x: 0, y: 0, width: 100, height: 100) && px(edge, 95, 95)[0] > 250)
    }

    @Test func temporalBlendMixesOnlyInsideTheMask() {
        var b = TemporalBlend(); b.weight = 0.5
        let mask = VideoEraser.mask(box: CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.4), grow: 0, extent: CGRect(x: 0, y: 0, width: 100, height: 100))
        _ = b.blend(filled: solid(1, 1, 1), mask: mask)                              // first frame: white
        let out = b.blend(filled: solid(0, 0, 0), mask: mask)
        #expect(abs(Int(px(out, 50, 50)[0]) - 128) < 8)                              // inside: half of the old frame
        #expect(px(out, 5, 5)[0] < 5)                                                // outside: this frame as is
        b.reset(); #expect(px(b.blend(filled: solid(0, 0, 0), mask: mask), 50, 50)[0] < 5)
    }

    @Test func eraserFillsTheTrackedAreaAndSkipsLostFrames() throws {
        let box = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
        var e = VideoEraser(track: ObjectTrack(fps: 10, boxes: [box, nil, nil]))
        e.grow = 0
        let out = try e.process(frame: solid(1, 0, 0), at: 0, inpainter: Fill(color: CIColor(red: 0, green: 0, blue: 1)))
        #expect(px(out, 50, 50)[2] > 250 && px(out, 5, 5)[0] > 250)                 // box painted blue, rest still red
        var lost = VideoEraser(track: ObjectTrack(fps: 10, boxes: [nil]))
        let same = try lost.process(frame: solid(1, 0, 0), at: 0, inpainter: Fill(color: .blue))
        #expect(px(same, 50, 50)[0] > 250)
    }
}
