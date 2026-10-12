import CoreImage
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

struct MaskDilationTests {
    @Test func growsEverySideByTheRadiusAndStopsAtTheEdges() {
        var m = MaskCanvas(width: 20, height: 20)
        m.fill(rect: CGRect(x: 9, y: 9, width: 2, height: 2))
        let d = m.dilated(by: 3)
        #expect(d[6, 9] == 255 && d[13, 10] == 255 && d[9, 6] == 255 && d[10, 13] == 255 && d[6, 6] == 255)
        #expect(d[5, 9] == 0 && d[14, 9] == 0 && d[9, 5] == 0 && d[9, 14] == 0)
        var edge = MaskCanvas(width: 10, height: 10); edge.fill(rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let e = edge.dilated(by: 4)
        #expect(e[4, 0] == 255 && e[0, 4] == 255 && e[5, 0] == 0)
    }

    @Test func emptyMasksAndZeroRadiusAreUnchanged() {
        let m = MaskCanvas(width: 8, height: 8)
        #expect(m.dilated(by: 5) == m)
        var f = MaskCanvas(width: 8, height: 8); f.fill(rect: CGRect(x: 2, y: 2, width: 2, height: 2))
        #expect(f.dilated(by: 0) == f)
    }

    @Test func objectsExcludeAnythingMostlyCoveredByAPerson() {
        func inst(_ r: CGRect) -> PersonInstance { PersonInstance(mask: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4)), box: r) }
        let person = inst(CGRect(x: 0.1, y: 0.1, width: 0.4, height: 0.8))
        let bag = inst(CGRect(x: 0.15, y: 0.4, width: 0.1, height: 0.1))          // inside the person
        let bench = inst(CGRect(x: 0.6, y: 0.1, width: 0.3, height: 0.2))
        let out = AutoRemove.objects(from: [person, bag, bench], excluding: [person])
        #expect(out == [bench])
        #expect(AutoRemove.objects(from: [bench], excluding: []) == [bench])
    }
}
