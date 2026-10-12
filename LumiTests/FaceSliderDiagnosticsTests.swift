import CoreImage
import Testing
@testable import Lumi

/// Renders every face-shape slider at both ends on a real photo copied into the app's Documents (not part of normal runs) and writes how much each one moved the picture.
@Suite(.serialized)
struct FaceSliderDiagnosticsTests {
    static let docs = URL(fileURLWithPath: NSHomeDirectory() + "/Documents")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: FaceSliderDiagnosticsTests.docs.appendingPathComponent("face.jpg").path))) func everySliderMovesThePicture() throws {
        let photo = try #require(CIImage(contentsOf: Self.docs.appendingPathComponent("face.jpg")))
        let proxy = Renderer.proxy(photo, maxDimension: 900)
        let ctx = CIContext()
        let base = Renderer.render(proxy, document: EditDocument())
        var report = "faces: \((try? Renderer.services.faceLandmarker?.faces(in: proxy).count) ?? -1)\n"
        func meanDiff(_ a: CIImage, _ b: CIImage) -> Double {
            let d = a.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: b]).applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: a.extent)])
            var px = [UInt8](repeating: 0, count: 4)
            ctx.render(d, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return Double(px[0] + px[1] + px[2]) / 3
        }
        let sliders: [(String, WritableKeyPath<FaceRetouch, Double>)] = [
            ("chin", \.reshape.chinLength), ("jaw", \.reshape.jawSlim), ("vShape", \.shape.vShape), ("width", \.reshape.faceWidth), ("cheekbones", \.shape.cheekbones), ("cheekVolume", \.reshape.cheekVolume),
            ("eyeSize", \.reshape.eyeSize), ("noseSlim", \.reshape.noseSlim), ("mouthSize", \.reshape.mouthSize), ("lift", \.reshape.lift),
        ]
        func mean(_ img: CIImage) -> String {
            let a = img.applyingFilter("CIAreaAverage", parameters: [kCIInputExtentKey: CIVector(cgRect: img.extent)])
            var px = [UInt8](repeating: 0, count: 4)
            ctx.render(a, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return "\(px[0]),\(px[1]),\(px[2]) extent \(img.extent)"
        }
        report += "identity face: \(FaceRetouch().isIdentity)  base mean \(mean(base))\n"
        var one = EditDocument(); var of = one.face; of.reshape.chinLength = 1; one.face = of
        let chin = Renderer.render(proxy, document: one)
        report += "chin+1 mean \(mean(chin)); ops \(one.operations.count)\n"
        var tiny = WarpEdit(); tiny.add(BrushStroke(kind: .push, x: 0.05, y: 0.05, radius: 0.02, strength: 1, dirX: 0.01, dirY: 0))
        let warped = MeshWarpRenderer.apply(tiny.field(aspect: Float(proxy.extent.width / proxy.extent.height)), to: proxy)
        report += "tiny far-away warp: mean diff \(meanDiff(base, warped)) (should be ~0), kernel error: \(MeshWarpRenderer.loadError ?? "none")\n"
        for (name, path) in sliders {
            for v in [1.0, -1.0] {
                var d = EditDocument(); var f = d.face; f[keyPath: path] = v; d.face = f
                let out = Renderer.render(proxy, document: d)
                report += "\(name) \(v): mean diff \(meanDiff(base, out))\n"
                if v == 1 { try ctx.pngRepresentation(of: out, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)?.write(to: Self.docs.appendingPathComponent("face_\(name).png")) }
            }
        }
        try ctx.pngRepresentation(of: base, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)?.write(to: Self.docs.appendingPathComponent("face_base.png"))
        try report.write(to: Self.docs.appendingPathComponent("face_diag.txt"), atomically: true, encoding: .utf8)
    }
}
