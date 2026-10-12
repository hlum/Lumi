import CoreImage
import Foundation
import Metal
import Testing
@testable import Lumi

/// T04 measurements. Device-only: the simulator's GPU numbers say nothing about a phone.
@MainActor
struct PreviewBenchmarkTests {
    static func residentMB() -> Int {
        var info = mach_task_basic_info(); var cnt = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / 4)
        _ = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: 1) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &cnt) } }
        return Int(info.resident_size / 1_048_576)
    }

    /// A 48 MP-sized picture with real detail (noise) so filters have work to do.
    static func fortyEightMP() -> CIImage {
        CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 8000, height: 6000))
    }

    @Test(.enabled(if: !RunsOn.isSimulator))
    func proxyPreviewAtFortyEightMegapixelsIsInteractive() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let ctx = CIContext(mtlDevice: device)
        let full = Self.fortyEightMP()
        let proxy = Renderer.proxy(full, maxDimension: EditorModel.proxySize)
        var doc = EditDocument(); doc.filter = ("film-gold", 1); doc.adjust = AdjustParams(contrast: 0.2, saturation: 0.2, vignette: 0.3)
        let tex = device.makeTexture(descriptor: { let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: 1170, height: 1560, mipmapped: false); d.usage = [.shaderWrite, .shaderRead, .renderTarget]; return d }())!
        let cb0 = device.makeCommandQueue()!
        func frame(_ exposure: Double) {
            doc.exposure = exposure
            let out = Renderer.render(proxy, document: doc)
            let q = cb0.makeCommandBuffer()!
            ctx.render(out, to: tex, commandBuffer: q, bounds: CGRect(x: 0, y: 0, width: 1170, height: 1560), colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
            q.commit(); q.waitUntilCompleted()
        }
        frame(0.1)                                                       // warm up shaders and caches
        let n = 30, start = Date()
        for i in 0..<n { frame(Double(i % 10) / 10) }
        let perFrame = Date().timeIntervalSince(start) / Double(n) * 1000
        let mem = Self.residentMB()
        #expect(perFrame < 50, "proxy frame \(perFrame) ms, resident \(mem) MB")
        #expect(mem < 2500, "memory \(mem) MB")
    }

    @Test(.enabled(if: !RunsOn.isSimulator))
    func fullResolutionExportOfFortyEightMegapixelsCompletes() throws {
        let m = EditorModel(saver: EditorModelTests.FakeSaver())
        m.load(image: Self.fortyEightMP())
        m.edit { $0.filter = ("film-gold", 1); $0.adjust = AdjustParams(contrast: 0.2, saturation: 0.2) }
        m.exportSettings.format = .jpeg; m.exportSettings.quality = 0.8
        let start = Date()
        let data = try m.exportData()
        let seconds = Date().timeIntervalSince(start)
        #expect(data.count > 1_000_000)
        #expect(seconds < 30, "export took \(seconds) s, resident \(Self.residentMB()) MB")
    }
}
