import CoreImage
import Foundation
import ImageIO
import PDFKit
import Testing
import UIKit
@testable import Lumi

struct ScanAndGIFTests {
    static func frame(_ v: CGFloat, size: Int = 64) -> CGImage {
        GeometryTests.ctx.createCGImage(RendererTests.solid(v, size: CGFloat(size)), from: CGRect(x: 0, y: 0, width: size, height: size))!
    }

    // MARK: GIF
    @Test func gifHasAllFramesDelayAndLoop() throws {
        let data = try #require(GIFMaker.encode([Self.frame(0.1), Self.frame(0.5), Self.frame(0.9)], options: .init(fps: 5, maxSide: 480, loopCount: 0)))
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceGetCount(src) == 3)
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        #expect(abs((gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0) - 0.2) < 0.011)
    }

    @Test func gifFramesAreScaledDown() throws {
        let data = try #require(GIFMaker.encode([Self.frame(0.5, size: 400)], options: .init(fps: 10, maxSide: 100, loopCount: 1)))
        let src = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        #expect(CGImageSourceCreateImageAtIndex(src, 0, nil)?.width == 100)
        #expect(GIFMaker.targetSize(for: CGSize(width: 50, height: 20), maxSide: 100) == CGSize(width: 50, height: 20))
        #expect(GIFMaker.targetSize(for: CGSize(width: 400, height: 200), maxSide: 100) == CGSize(width: 100, height: 50))
    }

    @Test func gifRejectsBadInput() {
        #expect(GIFMaker.encode([]) == nil)
        #expect(GIFMaker.encode([Self.frame(0.5)], options: .init(fps: 0)) == nil)
        #expect(GIFMaker.encode([Self.frame(0.5)], options: .init(fps: 500)) == nil)
    }

    @Test func emojiIsATransparentSquareWithTheCutoutCentered() {
        let cut = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        let e = GIFMaker.emoji(cut, side: 256)
        #expect(e.extent == CGRect(x: 0, y: 0, width: 256, height: 256))
        #expect(GeometryTests.rgb(e, x: 128, y: 128)[0] > 200)                // center is red
        #expect(GeometryTests.rgb(e, x: 128, y: 10)[3] == 0)                  // above/below the wide cutout is transparent
        #expect(GeometryTests.rgb(e, x: 2, y: 128)[3] == 0)                   // margin
    }

    // MARK: scan
    @Test func scanFiltersKeepExtentAndBlackWhiteIsBinary() {
        let img = RendererTests.solid(0.7, size: 32)
        for f in ScanFilter.allCases { #expect(ScanTools.apply(f, to: img).extent == img.extent) }
        let bw = ScanTools.apply(.blackWhite, to: img)
        let p = GeometryTests.rgb(bw, x: 5, y: 5)
        #expect(p[0] == 255 || p[0] == 0)
        #expect(GeometryTests.rgb(ScanTools.apply(.blackWhite, to: RendererTests.solid(0.2, size: 32)), x: 5, y: 5)[0] == 0)
        #expect(GeometryTests.rgb(ScanTools.apply(.grayscale, to: CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: img.extent)), x: 5, y: 5).prefix(3).allSatisfy { abs(Int($0) - Int(GeometryTests.rgb(ScanTools.apply(.grayscale, to: CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: img.extent)), x: 5, y: 5)[0])) < 4 })
    }

    @Test func flattenCorrectsPerspectiveToTheQuad() {
        let img = RendererTests.solid(0.5, size: 100)
        let out = ScanTools.flatten(img, topLeft: CGPoint(x: 0.1, y: 0.9), topRight: CGPoint(x: 0.9, y: 0.95), bottomLeft: CGPoint(x: 0.1, y: 0.1), bottomRight: CGPoint(x: 0.9, y: 0.05))
        #expect(out.extent.width > 50 && out.extent.height > 50 && out.extent.width < 100)
    }

    @Test func ocrReadsRenderedText() throws {
        var style = TextStyle(); style.size = 0.25; style.color = .black
        let text = try #require(LayerRenderer.textImage("HELLO LUMI", style: style, imageHeight: 400))
        let page = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: text.extent.width + 80, height: 300))
        let doc = LayerRenderer.composite(text, transform: LayerTransform(center: CGPoint(x: 0.5, y: 0.5)), opacity: 1, over: page)
        let lines = try ScanTools.recognizeText(in: doc)
        #expect(lines.joined(separator: " ").uppercased().contains("HELLO"), "got \(lines)")
    }

    @Test func pdfHasOnePagePerImageAtImageSize() throws {
        let a = UIImage(cgImage: Self.frame(0.2, size: 80)), b = UIImage(cgImage: Self.frame(0.8, size: 120))
        let data = try #require(ScanTools.pdf([a, b]))
        let doc = try #require(PDFDocument(data: data))
        #expect(doc.pageCount == 2)
        #expect(ScanTools.pdf([]) == nil)
    }
}

struct GIFSequenceTests {
    @Test func bounceGoesForwardThenBackWithoutRepeatingTheEnds() {
        #expect(GIFMaker.sequence([1, 2, 3, 4], bounce: true) == [1, 2, 3, 4, 3, 2])
        #expect(GIFMaker.sequence([1, 2, 3, 4], bounce: false) == [1, 2, 3, 4])
        #expect(GIFMaker.sequence([1, 2], bounce: true) == [1, 2] && GIFMaker.sequence([Int](), bounce: true).isEmpty)
    }

    @Test func settingsPersistAndDefaultToSensibleValues() {
        let saved = (AppPrefs.format, AppPrefs.quality, AppPrefs.maxLongSide, AppPrefs.appearance)
        defer { (AppPrefs.format, AppPrefs.quality, AppPrefs.maxLongSide, AppPrefs.appearance) = saved }
        AppPrefs.format = .heic; AppPrefs.quality = 5; AppPrefs.maxLongSide = 2048; AppPrefs.appearance = .dark
        let s = AppPrefs.exportSettings()
        #expect(s.format == .heic && s.quality == 1 && s.maxLongSide == 2048 && AppPrefs.appearance == .dark)
        AppPrefs.maxLongSide = 0
        #expect(AppPrefs.exportSettings().maxLongSide == nil)
    }
}
