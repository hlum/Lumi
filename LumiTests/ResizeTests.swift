import Foundation
import Testing
@testable import Lumi

struct ResizeTests {
    @Test func tenByFifteenCmAt300DpiIs1181By1772() {
        #expect(ExportSettings.pixels(10, unit: .cm, dpi: 300) == 1181)
        #expect(ExportSettings.pixels(15, unit: .cm, dpi: 300) == 1772)
    }

    @Test func unitsAgree() {
        #expect(ExportSettings.pixels(100, unit: .mm, dpi: 254) == 1000)
        #expect(ExportSettings.pixels(1, unit: .inch, dpi: 300) == 300)
        #expect(ExportSettings.pixels(640, unit: .px, dpi: 999) == 640)
        #expect(ExportSettings.pixels(0, unit: .cm, dpi: 300) == 0)
    }

    @Test func fittedKeepsAspectAndNeverUpscales() {
        var s = ExportSettings(); s.maxLongSide = 1000
        #expect(s.fitted((4000, 3000)) == (1000, 750))
        #expect(s.fitted((3000, 4000)) == (750, 1000))
        #expect(s.fitted((800, 600)) == (800, 600))
        #expect(s.fitted((1000, 500)) == (1000, 500))
    }

    @Test func fittedWithoutLimitOrWithBadLimitIsUnchanged() {
        #expect(ExportSettings().fitted((5000, 4000)) == (5000, 4000))
        var s = ExportSettings(); s.maxLongSide = 0
        #expect(s.fitted((5000, 4000)) == (5000, 4000))
    }

    @Test func extremeAspectNeverCollapsesToZero() {
        var s = ExportSettings(); s.maxLongSide = 100
        #expect(s.fitted((10000, 1)).h == 1)
    }

    @Test func onlyJpegLacksAlpha() {
        #expect(ImageFormat.png.supportsAlpha && ImageFormat.heic.supportsAlpha && !ImageFormat.jpeg.supportsAlpha)
        #expect(ImageFormat.jpeg.fileExtension == "jpg" && ImageFormat.heic.fileExtension == "heic")
    }

    @Test func estimateGrowsWithQualityAndSize() {
        var lo = ExportSettings(); lo.quality = 0.3
        var hi = ExportSettings(); hi.quality = 0.95
        #expect(lo.estimatedBytes(width: 1000, height: 1000) < hi.estimatedBytes(width: 1000, height: 1000))
        #expect(hi.estimatedBytes(width: 2000, height: 2000) > hi.estimatedBytes(width: 1000, height: 1000))
        var heic = hi; heic.format = .heic
        #expect(heic.estimatedBytes(width: 1000, height: 1000) < hi.estimatedBytes(width: 1000, height: 1000))
    }

    @Test func codableRoundTrip() throws {
        var s = ExportSettings(); s.format = .png; s.maxLongSide = 2048
        #expect(try JSONDecoder().decode(ExportSettings.self, from: JSONEncoder().encode(s)) == s)
    }
}
