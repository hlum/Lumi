import CoreImage
import Foundation
import Testing
@testable import Lumi

struct InpaintPlanTests {
    @Test func cropGrowsAroundMaskWithContext() {
        let r = InpaintPlan.cropRect(maskBounds: CGRect(x: 1000, y: 1000, width: 100, height: 100), imageSize: CGSize(width: 4000, height: 3000))!
        #expect(r.width == 300 && r.height == 300 && r.midX == 1050 && r.midY == 1050)
    }

    @Test func tinyMasksGetTheMinimumWindow() {
        let r = InpaintPlan.cropRect(maskBounds: CGRect(x: 500, y: 500, width: 4, height: 4), imageSize: CGSize(width: 4000, height: 3000))!
        #expect(r.width >= 256)
    }

    @Test func windowSlidesBackInsideTheImage() {
        let r = InpaintPlan.cropRect(maskBounds: CGRect(x: 0, y: 0, width: 100, height: 100), imageSize: CGSize(width: 4000, height: 3000))!
        #expect(r.minX == 0 && r.minY == 0 && r.width == 300)
        let r2 = InpaintPlan.cropRect(maskBounds: CGRect(x: 3950, y: 2950, width: 50, height: 50), imageSize: CGSize(width: 4000, height: 3000))!
        #expect(r2.maxX == 4000 && r2.maxY == 3000)
    }

    @Test func windowNeverLeavesTheImage() {
        let size = CGSize(width: 500, height: 400)
        for mb in [CGRect(x: 0, y: 0, width: 500, height: 400), CGRect(x: 250, y: 200, width: 10, height: 10), CGRect(x: 490, y: 390, width: 10, height: 10)] {
            let r = InpaintPlan.cropRect(maskBounds: mb, imageSize: size)!
            #expect(CGRect(origin: .zero, size: size).contains(r))
        }
    }

    @Test func emptyOrInvalidInputGivesNil() {
        #expect(InpaintPlan.cropRect(maskBounds: .null, imageSize: CGSize(width: 10, height: 10)) == nil)
        #expect(InpaintPlan.cropRect(maskBounds: CGRect(x: 1, y: 1, width: 0, height: 0), imageSize: CGSize(width: 10, height: 10)) == nil)
        #expect(InpaintPlan.cropRect(maskBounds: CGRect(x: 1, y: 1, width: 3, height: 3), imageSize: .zero) == nil)
    }

    @Test func maskBoundsAreTightAndBottomLeftOriented() {
        var px = [UInt8](repeating: 0, count: 10 * 10)
        for y in 1...2 { for x in 3...5 { px[y * 10 + x] = 255 } }       // top rows of the buffer
        #expect(InpaintPlan.bounds(ofMask: px, width: 10, height: 10) == CGRect(x: 3, y: 7, width: 3, height: 2))
        #expect(InpaintPlan.bounds(ofMask: [UInt8](repeating: 0, count: 100), width: 10, height: 10).isNull)
    }

    @Test func faintNoiseBelowThresholdIsIgnored() {
        var px = [UInt8](repeating: 0, count: 100); px[5] = 3
        #expect(InpaintPlan.bounds(ofMask: px, width: 10, height: 10).isNull)
    }
}

struct LaMaDeviceTests {
    static let modelPresent = LaMaInpainter.isModelAvailable

    @Test(.enabled(if: LaMaDeviceTests.modelPresent))
    func removesAnObjectFromASyntheticPhoto() throws {
        // gray background with a bright red square; mask the square
        let bg = CIImage(color: CIColor(red: 0.45, green: 0.5, blue: 0.55)).cropped(to: CGRect(x: 0, y: 0, width: 1200, height: 900))
        let box = CGRect(x: 500, y: 350, width: 160, height: 160)
        let photo = CIImage(color: .red).cropped(to: box).composited(over: bg)
        let mask = MosaicOps.mask(rects: [CGRect(x: box.minX / 1200, y: box.minY / 900, width: box.width / 1200, height: box.height / 900)], extent: bg.extent)
        let start = Date()
        let out = try LaMaInpainter().inpaint(photo, mask: mask)
        let seconds = Date().timeIntervalSince(start)
        #expect(out.extent == photo.extent)
        let c = GeometryTests.rgb(out, x: 580, y: 430)
        #expect(Int(c[0]) < 200, "red square should be gone, got \(c)")          // no longer pure red
        #expect(abs(Int(c[0]) - Int(c[2])) < 80)
        #expect(GeometryTests.rgb(out, x: 20, y: 20) == GeometryTests.rgb(photo, x: 20, y: 20))   // outside the mask: untouched
        print("LaMa first-call latency (incl. model load): \(seconds)s")
        #expect(seconds < 30)
    }

    @Test(.enabled(if: LaMaDeviceTests.modelPresent))
    func emptyMaskIsRejected() throws {
        let img = RendererTests.solid(0.5, size: 300)
        #expect(throws: InpaintError.emptyMask) { try LaMaInpainter().inpaint(img, mask: CIImage(color: .black).cropped(to: img.extent)) }
    }
}
