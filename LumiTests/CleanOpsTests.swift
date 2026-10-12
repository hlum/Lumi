import CoreImage
import Testing
@testable import Lumi

struct CleanOpsTests {
    private let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    private func px(_ i: CIImage, _ x: Int, _ y: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: Int(i.extent.height) - 1 - y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return b
    }
    /// Left half red, right half blue.
    private var split: CIImage {
        let r = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 50, height: 100))
        let b = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 50, y: 0, width: 50, height: 100))
        return b.composited(over: r)
    }

    @Test func identityWhenEmpty() { #expect(CleanConfig().isIdentity); #expect(!CleanConfig(denoise: 0.5).isIdentity) }

    @Test func cloneCopiesFromOffsetSource() {
        var m = MaskCanvas(width: 100, height: 100)
        m.stamp(x: 70, y: 50, radius: 8, hardness: 1, erase: false)       // paint on the blue half
        let out = CleanOps.apply(CleanConfig(cloneMask: m, offsetX: 0.3), to: split)   // source is 30 px to the left: red
        #expect(px(out, 70, 50)[0] > 200)
        #expect(px(out, 90, 50)[2] > 200)                                  // untouched
    }

    @Test func offsetIsAdjustable() {
        var m = MaskCanvas(width: 100, height: 100)
        m.stamp(x: 70, y: 50, radius: 8, hardness: 1, erase: false)
        let out = CleanOps.apply(CleanConfig(cloneMask: m, offsetX: 0.0), to: split)   // zero shift: same pixels
        #expect(px(out, 70, 50)[2] > 200)
    }

    @Test func denoiseKeepsExtent() {
        let out = CleanOps.apply(CleanConfig(denoise: 1), to: split)
        #expect(out.extent == split.extent)
    }

    @Test func everyBrushHasPreset() {
        for b in SpecialtyBrush.allCases { #expect(b.strength > 0 && b.strength <= 1); #expect(b.grow > 0); #expect(!b.title.isEmpty) }
    }

    @Test func documentRoundTripsAndDropsIdentity() throws {
        var d = EditDocument()
        d.clean = CleanConfig(denoise: 0.4)
        let back = try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d))
        #expect(back.clean.denoise == 0.4)
        d.clean = CleanConfig()
        #expect(d.operations.isEmpty)
    }
}
