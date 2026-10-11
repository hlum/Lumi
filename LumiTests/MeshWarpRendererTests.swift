import CoreImage
import Foundation
import Testing
@testable import Lumi

struct MeshWarpRendererTests {
    /// Horizontal black-to-white ramp, 64x64.
    static func ramp() -> CIImage {
        CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 64, y: 0),
                                                       "inputColor0": CIColor.black, "inputColor1": CIColor.white])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    static func v(_ i: CIImage, _ x: Int, _ y: Int = 32) -> Int { Int(GeometryTests.rgb(i, x: x, y: y)[0]) }

    @Test func kernelLoads() { #expect(MeshWarpRenderer.loadError == nil, "\(MeshWarpRenderer.loadError ?? "")") }

    @Test func identityFieldReturnsImageUnchanged() {
        let i = Self.ramp()
        #expect(MeshWarpRenderer.apply(DisplacementField(cols: 9, rows: 9), to: i).extent == i.extent)
    }

    @Test func kernelLoadsAndPushMovesContent() {
        var e = WarpEdit(cols: 17, rows: 17)
        e.add(BrushStroke(kind: .push, x: 0.5, y: 0.5, radius: 0.4, strength: 1, dirX: 0.2, dirY: 0))   // content moves right
        let i = Self.ramp()
        let out = MeshWarpRenderer.apply(e.field, to: i)
        #expect(out.extent == i.extent)
        // moving content right means each output pixel samples further left: darker than the original
        #expect(Self.v(out, 32) < Self.v(i, 32) - 5)
        // far corners are untouched
        #expect(abs(Self.v(out, 2, 2) - Self.v(i, 2, 2)) <= 2)
    }

    @Test func noSeamsAtEdgesWhenFieldPushesOutward() {
        var e = WarpEdit(cols: 9, rows: 9)
        e.add(BrushStroke(kind: .push, x: 0.0, y: 0.5, radius: 0.5, strength: 1, dirX: 0.3, dirY: 0))
        let out = MeshWarpRenderer.apply(e.field, to: Self.ramp())
        #expect(GeometryTests.rgb(out, x: 0, y: 32)[3] == 255)         // clamped, never transparent
    }

    @Test func bloatVersusPinchChangeCenterDifferently() {
        let i = Self.ramp()
        var b = WarpEdit(cols: 17, rows: 17), p = b
        b.add(BrushStroke(kind: .bloat, x: 0.5, y: 0.5, radius: 0.4, strength: 1))
        p.add(BrushStroke(kind: .pinch, x: 0.5, y: 0.5, radius: 0.4, strength: 1))
        let ob = MeshWarpRenderer.apply(b.field, to: i), op = MeshWarpRenderer.apply(p.field, to: i)
        #expect(Self.v(ob, 40) != Self.v(op, 40))
    }

    @Test func fieldImageIsSizedLikeTheGrid() {
        #expect(MeshWarpRenderer.fieldImage(DisplacementField(cols: 5, rows: 7)).extent.size == CGSize(width: 5, height: 7))
    }

    @Test func fullResolutionWarpRenders() {
        let big = CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 4000, height: 3000))
        var e = WarpEdit(); e.add(BrushStroke(kind: .bloat, x: 0.5, y: 0.5, radius: 0.3, strength: 0.5))
        let out = MeshWarpRenderer.apply(e.field, to: big)
        #expect(out.extent == big.extent)
        _ = GeometryTests.rgb(out, x: 2000, y: 1500)
    }

    @Test func warpIsADocumentOperationThatRendersAndRoundTrips() throws {
        var d = EditDocument()
        var w = WarpEdit(cols: 17, rows: 17)
        w.add(BrushStroke(kind: .push, x: 0.5, y: 0.5, radius: 0.4, strength: 1, dirX: 0.2, dirY: 0))
        d.warp = w
        let back = try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d))
        #expect(back.warp == w)
        let i = Self.ramp()
        #expect(Self.v(Renderer.render(i, document: back), 32) != Self.v(i, 32))
        d.warp = WarpEdit()
        #expect(d.operations.isEmpty)
    }
}
