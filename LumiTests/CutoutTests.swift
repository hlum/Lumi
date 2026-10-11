import CoreImage
import Foundation
import Testing
@testable import Lumi

struct FakeMasker: SubjectMasking {
    var left = true
    func subjectMask(for image: CIImage) throws -> CIImage? {
        let e = image.extent
        return MosaicOps.mask(rects: [CGRect(x: 0, y: 0, width: 0.5, height: 1)], extent: e)      // left half is "the subject"
    }
}
struct NoSubjectMasker: SubjectMasking { func subjectMask(for image: CIImage) throws -> CIImage? { nil } }

extension ServicesSerial {
struct CutoutTests {
    static func photo() -> CIImage { CIImage(color: CIColor(red: 0.9, green: 0.2, blue: 0.2)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64)) }
    static let mask = MosaicOps.mask(rects: [CGRect(x: 0, y: 0, width: 0.5, height: 1)], extent: CGRect(x: 0, y: 0, width: 64, height: 64))

    @Test func transparentBackgroundDropsNonSubjectPixels() {
        let out = CutoutOps.apply(CutoutConfig(), to: Self.photo(), subjectMask: Self.mask)
        #expect(GeometryTests.rgb(out, x: 10, y: 32)[3] == 255)
        #expect(GeometryTests.rgb(out, x: 54, y: 32)[3] == 0)
    }

    @Test func colorBackgroundFillsOutside() {
        var c = CutoutConfig(); c.background = .color(RGBA(r: 0, g: 0, b: 1, a: 1))
        let out = CutoutOps.apply(c, to: Self.photo(), subjectMask: Self.mask)
        let bg = GeometryTests.rgb(out, x: 54, y: 32)
        #expect(bg[2] > 200 && bg[0] < 30 && bg[3] == 255)
        #expect(GeometryTests.rgb(out, x: 10, y: 32)[0] > 200)       // subject untouched
    }

    @Test func gradientRunsTopToBottom() {
        var c = CutoutConfig(); c.background = .gradient(RGBA(r: 1, g: 1, b: 1, a: 1), RGBA(r: 0, g: 0, b: 0, a: 1))
        let out = CutoutOps.apply(c, to: Self.photo(), subjectMask: Self.mask)
        #expect(GeometryTests.rgb(out, x: 54, y: 60)[0] > GeometryTests.rgb(out, x: 54, y: 4)[0])      // CI y grows upward: y=60 is the top
    }

    @Test func blurBackgroundKeepsExtent() {
        var c = CutoutConfig(); c.background = .blur(0.5)
        #expect(CutoutOps.apply(c, to: Self.photo(), subjectMask: Self.mask).extent == Self.photo().extent)
    }

    @Test func invertSwapsSubjectAndBackground() {
        var c = CutoutConfig(); c.invert = true
        let out = CutoutOps.apply(c, to: Self.photo(), subjectMask: Self.mask)
        #expect(GeometryTests.rgb(out, x: 10, y: 32)[3] == 0 && GeometryTests.rgb(out, x: 54, y: 32)[3] == 255)
    }

    @Test func featherSoftensTheEdgeAndShiftMovesIt() {
        let big = CGRect(x: 0, y: 0, width: 200, height: 200)
        let mask = MosaicOps.mask(rects: [CGRect(x: 0, y: 0, width: 0.5, height: 1)], extent: big)
        func edge(_ m: CIImage) -> Int { Int(GeometryTests.rgb(m, x: 99, y: 100)[0]) }
        var soft = CutoutConfig(); soft.feather = 1
        #expect(edge(CutoutOps.refine(mask, soft)) < 255 && edge(CutoutOps.refine(mask, soft)) > 0)
        var shrink = CutoutConfig(); shrink.shift = 1
        var grow = CutoutConfig(); grow.shift = -1
        #expect(edge(CutoutOps.refine(mask, shrink)) < edge(mask))
        #expect(GeometryTests.rgb(CutoutOps.refine(mask, grow), x: 101, y: 100)[0] > GeometryTests.rgb(mask, x: 101, y: 100)[0])
        #expect(CutoutOps.refine(mask, CutoutConfig()).extent == big)
    }

    @Test func configRoundTripsThroughDocument() throws {
        var d = EditDocument()
        var c = CutoutConfig(); c.background = .gradient(.white, .black); c.feather = 0.4
        d.cutout = c
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).cutout == c)
        d.cutout = nil; #expect(d.operations.isEmpty)
    }

    @Test func renderUsesTheMaskerAndCachesIt() {
        Renderer.services = Renderer.Services(); Renderer.services.subjectMasker = FakeMasker()
        var d = EditDocument(); var c = CutoutConfig(); c.background = .color(RGBA(r: 0, g: 1, b: 0, a: 1)); d.cutout = c
        let img = Self.photo()
        let out = Renderer.render(img, document: d)
        #expect(GeometryTests.rgb(out, x: 54, y: 32)[1] > 200)
        _ = Renderer.render(img, document: d)
        #expect(Renderer.services.inpaintCalls == 1)                       // one mask computation for two renders
    }

    @Test func noSubjectOrNoMaskerReturnsTheOriginal() {
        var d = EditDocument(); d.cutout = CutoutConfig()
        let img = Self.photo()
        Renderer.services = Renderer.Services(); Renderer.services.subjectMasker = NoSubjectMasker()
        #expect(GeometryTests.rgb(Renderer.render(img, document: d), x: 54, y: 32)[3] == 255)
        Renderer.services = Renderer.Services()
        #expect(GeometryTests.rgb(Renderer.render(img, document: d), x: 54, y: 32)[3] == 255)
    }

    @Test func visionMaskerHandlesAnImageWithNoSubject() throws {
        let flat = RendererTests.solid(0.5, size: 128)
        _ = try? VisionSubjectMasker().subjectMask(for: flat)             // must not crash; nil or a mask are both fine
    }

    @MainActor @Test func transparentCutoutExportsAsPNG() throws {
        Renderer.services = Renderer.Services(); Renderer.services.subjectMasker = FakeMasker()
        defer { Renderer.services = Renderer.Services() }
        let m = EditorModel(saver: EditorModelTests.FakeSaver())
        m.load(image: RendererTests.solid(0.3, size: 32))
        m.edit { $0.cutout = CutoutConfig() }                          // transparent background
        #expect(Array(try m.exportData().prefix(4)) == [0x89, 0x50, 0x4E, 0x47])   // PNG signature
        m.edit { $0.cutout = nil }
        #expect(Array(try m.exportData().prefix(2)) == [0xFF, 0xD8])    // JPEG again
    }
}
}
