import CoreImage
import Foundation
import ImageIO
import Testing
@testable import Lumi

@MainActor
struct ExportSettingsEditorTests {
    static func model(_ w: CGFloat = 400, _ h: CGFloat = 300) -> EditorModel {
        let m = EditorModel(saver: EditorModelTests.FakeSaver())
        m.load(image: RendererTests.solid(0.4, size: 10).cropped(to: CGRect(x: 0, y: 0, width: 10, height: 10)))
        m.load(image: CIImage(color: CIColor(red: 0.4, green: 0.5, blue: 0.6)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h)))
        return m
    }
    static func size(_ d: Data) -> CGSize? {
        guard let s = CGImageSourceCreateWithData(d as CFData, nil), let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] else { return nil }
        return CGSize(width: p[kCGImagePropertyPixelWidth] as? Double ?? 0, height: p[kCGImagePropertyPixelHeight] as? Double ?? 0)
    }
    static func type(_ d: Data) -> String? { CGImageSourceCreateWithData(d as CFData, nil).flatMap { CGImageSourceGetType($0) as String? } }

    @Test func formatsProduceTheRightFileTypes() throws {
        let m = Self.model()
        m.exportSettings.format = .jpeg; #expect(Self.type(try m.exportData()) == "public.jpeg")
        m.exportSettings.format = .png; #expect(Self.type(try m.exportData()) == "public.png")
        m.exportSettings.format = .heic; #expect(Self.type(try m.exportData()) == "public.heic")
    }

    @Test func maxSizeDownscalesKeepingAspectAndNeverUpscales() throws {
        let m = Self.model(400, 300)
        m.exportSettings.maxLongSide = 200
        #expect(Self.size(try m.exportData()) == CGSize(width: 200, height: 150))
        #expect(m.exportPixelSize?.w == 200 && m.exportPixelSize?.h == 150)
        m.exportSettings.maxLongSide = 4096
        #expect(Self.size(try m.exportData()) == CGSize(width: 400, height: 300))
        m.exportSettings.maxLongSide = nil
        #expect(Self.size(try m.exportData()) == CGSize(width: 400, height: 300))
    }

    @Test func qualityChangesTheJPEGSize() throws {
        // a noisy image so quality matters
        let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 300, height: 300))
        let m = EditorModel(saver: EditorModelTests.FakeSaver()); m.load(image: noise)
        m.exportSettings.format = .jpeg; m.exportSettings.quality = 0.3
        let low = try m.exportData().count
        m.exportSettings.quality = 1
        #expect(try m.exportData().count > low)
    }

    @Test func estimateTracksTheChosenSettings() {
        let m = Self.model(2000, 1500)
        m.exportSettings.format = .jpeg
        let full = m.estimatedBytes ?? 0
        m.exportSettings.maxLongSide = 500
        #expect((m.estimatedBytes ?? 0) < full && full > 0)
        #expect(EditorModel(saver: EditorModelTests.FakeSaver()).estimatedBytes == nil)
    }

    @Test func croppedAndUpscaledSizesFeedTheExportSize() {
        let m = Self.model(400, 300)
        m.edit { $0.crop.quarterTurns = 1 }
        #expect(m.exportPixelSize?.w == 300 && m.exportPixelSize?.h == 400)
    }

    @Test func tenByFifteenCentimetresAtThreeHundredDpiExportsAs1181By1772() throws {
        let m = Self.model(4000, 3000)
        m.applyPrintSize(width: 10, height: 15, unit: .cm, dpi: 300)
        #expect(m.exportSettings.exactSize == ExportSettings.PixelSize(w: 1181, h: 1772))
        #expect(m.exportPixelSize?.w == 1181 && m.exportPixelSize?.h == 1772)
        m.exportSettings.format = .jpeg
        #expect(Self.size(try m.exportData()) == CGSize(width: 1181, height: 1772))
    }

    @Test func printSizeCropsToThePaperAspectFirst() {
        let m = Self.model(4000, 3000)
        m.applyPrintSize(width: 10, height: 15, unit: .cm, dpi: 300)
        let r = m.draft.crop.rect
        #expect(abs(Double(r.width * 4000) / Double(r.height * 3000) - 10.0 / 15) < 1e-6)
    }

    @Test func printSizeCanBeClearedAndPNGKeepsAlpha() throws {
        let m = Self.model(400, 300)
        m.applyPrintSize(width: 5, height: 5, unit: .cm, dpi: 200)
        m.clearPrintSize()
        #expect(m.exportSettings.exactSize == nil && m.exportPixelSize?.w == 400)
        // PNG of a partly transparent picture keeps the alpha channel
        let half = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 20, height: 40))
            .composited(over: CIImage(color: .clear).cropped(to: CGRect(x: 0, y: 0, width: 40, height: 40)))
        let t = EditorModel(saver: EditorModelTests.FakeSaver()); t.load(image: half); t.exportSettings.format = .png
        let out = try #require(CIImage(data: try t.exportData()))
        #expect(GeometryTests.rgb(out, x: 30, y: 20)[3] == 0 && GeometryTests.rgb(out, x: 5, y: 20)[3] == 255)
    }

    @Test func unitsConvertToPixels() {
        #expect(ExportSettings.printSize(width: 25.4, height: 50.8, unit: .mm, dpi: 100) == ExportSettings.PixelSize(w: 100, h: 200))
        #expect(ExportSettings.printSize(width: 1, height: 2, unit: .inch, dpi: 300) == ExportSettings.PixelSize(w: 300, h: 600))
    }
}
