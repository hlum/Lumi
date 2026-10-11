import CoreImage
import Foundation
import Testing
@testable import Lumi

struct FakeHairMasker: HairMasking {
    func hairMasks(in image: CIImage) throws -> [CIImage] {
        [MosaicOps.mask(rects: [CGRect(x: 0, y: 0.5, width: 1, height: 0.5)], extent: image.extent)]       // the top half is "hair"
    }
}

extension ServicesSerial {
struct HairRetouchTests {
    static let ext = CGRect(x: 0, y: 0, width: 100, height: 100)
    static func brown() -> CIImage { CIImage(color: CIColor(red: 0.35, green: 0.22, blue: 0.12)).cropped(to: ext) }
    static let topHair = MosaicOps.mask(rects: [CGRect(x: 0, y: 0.5, width: 1, height: 0.5)], extent: ext)

    @Test func defaultsAreIdentity() {
        #expect(HairRetouch().isIdentity)
        #expect(HairRetouchRender.apply(HairRetouch(), to: Self.brown(), hairMasks: [Self.topHair]).extent == Self.ext)
    }

    @Test func swatchesCoverTheThreeCategories() {
        #expect(Set(HairRetouch.swatches.map(\.category)) == ["Natural", "Fashion", "Vivid"])
        #expect(Set(HairRetouch.swatches.map(\.name)).count == HairRetouch.swatches.count && HairRetouch.swatches.count >= 10)
    }

    @Test func dyeChangesOnlyTheHairMask() {
        var h = HairRetouch(); h.dye.color = RGBA(r: 0.2, g: 0.4, b: 1, a: 1); h.dye.strength = 1
        let out = HairRetouchRender.apply(h, to: Self.brown(), hairMasks: [Self.topHair])
        let top = GeometryTests.rgb(out, x: 50, y: 80), bottom = GeometryTests.rgb(out, x: 50, y: 20)
        #expect(top[2] > top[0])
        #expect(GeometryTests.near(bottom, GeometryTests.rgb(Self.brown(), x: 50, y: 20)))
    }

    @Test func brushAddsHairAndErasingTakesItAway() {
        var h = HairRetouch(); h.dye.color = RGBA(r: 0.2, g: 0.4, b: 1, a: 1); h.dye.strength = 1
        var add = MaskCanvas(width: 20, height: 20); add.fill(rect: CGRect(x: 0, y: 14, width: 20, height: 6))        // paint into the bottom (mask rows are top-first; this is the picture's bottom rows)
        h.add = add
        let out = HairRetouchRender.apply(h, to: Self.brown(), hairMasks: [])
        #expect(GeometryTests.rgb(out, x: 50, y: 5)[2] > GeometryTests.rgb(out, x: 50, y: 5)[0])                        // brushed-in strip is dyed even with no estimated hair
        var rem = MaskCanvas(width: 20, height: 20); rem.fill(rect: CGRect(x: 0, y: 0, width: 20, height: 20))
        h.add = nil; h.remove = rem
        #expect(GeometryTests.near(RendererTests.pixel(HairRetouchRender.apply(h, to: Self.brown(), hairMasks: [Self.topHair])), RendererTests.pixel(Self.brown())))   // everything erased
    }

    @Test func deOilSmoothAndRootsActOnlyInsideTheHair() {
        // bright specular streaks in the hair half
        let streaks = CIFilter(name: "CIStripesGenerator", parameters: ["inputWidth": 3, "inputColor0": CIColor.white, "inputColor1": CIColor.black])!.outputImage!.cropped(to: Self.ext)
        let cases: [(String, (inout HairRetouch) -> Void)] = [("deOil", { $0.deOil = 1 }), ("smooth", { $0.smooth = 1 }), ("roots", { $0.rootRetouch = 1 })]
        for (name, set) in cases {
            var h = HairRetouch(); set(&h)
            let out = HairRetouchRender.apply(h, to: streaks, hairMasks: [Self.topHair])
            let changedTop = (60..<95).contains { y in (0..<100).contains { x in GeometryTests.rgb(out, x: x, y: y) != GeometryTests.rgb(streaks, x: x, y: y) } }
            let changedBottom = (0..<30).contains { y in (0..<100).contains { x in GeometryTests.rgb(out, x: x, y: y) != GeometryTests.rgb(streaks, x: x, y: y) } }
            #expect(changedTop && !changedBottom, "\(name)")
        }
    }

    @Test func rootsAreDarkerNearTheTopThanLowerDown() {
        var h = HairRetouch(); h.rootRetouch = 1
        let img = CIImage(color: CIColor(red: 0.6, green: 0.5, blue: 0.3)).cropped(to: Self.ext)
        let out = HairRetouchRender.apply(h, to: img, hairMasks: [Self.topHair])
        func l(_ y: Int) -> Int { let c = GeometryTests.rgb(out, x: 50, y: y); return Int(c[0]) + Int(c[1]) + Int(c[2]) }
        #expect(l(95) < l(60))
    }

    @Test func operationRoundTripsAndOldDraftsOpen() throws {
        var d = EditDocument(); d.hair.dye.strength = 0.7; d.hair.deOil = 0.4
        var add = MaskCanvas(width: 8, height: 8); add.fill(rect: CGRect(x: 0, y: 0, width: 4, height: 4)); d.hair.add = add
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).hair == d.hair)
        d.hair = HairRetouch(); #expect(d.operations.isEmpty)
    }

    @Test func rendererUsesTheHairMaskerAndCachesIt() {
        Renderer.services = Renderer.Services(); Renderer.services.hairMasker = FakeHairMasker()
        defer { Renderer.services = Renderer.Services() }
        var d = EditDocument()
        var h = HairRetouch(); h.dye.color = RGBA(r: 0.2, g: 0.4, b: 1, a: 1); h.dye.strength = 1; d.hair = h        // set together, as the swatch buttons do
        let out = Renderer.render(Self.brown(), document: d)
        #expect(GeometryTests.rgb(out, x: 50, y: 80)[2] > GeometryTests.rgb(out, x: 50, y: 80)[0])
        d.hair.dye.strength = 0.5; _ = Renderer.render(Self.brown(), document: d)
        #expect(Renderer.services.inpaintCalls == 1)                                                             // slider drag reuses the estimate
        Renderer.services = Renderer.Services()
        #expect(GeometryTests.near(RendererTests.pixel(Renderer.render(Self.brown(), document: d)), RendererTests.pixel(Self.brown())))      // no masker: untouched
    }

    @Test func estimatedMaskerNeedsASubject() throws {
        let m = EstimatedHairMasker(faces: FakeLandmarker(faces: [EyeMakeupTests.face()]), subject: NoSubjectMasker())
        #expect(try m.hairMasks(in: Self.brown()).isEmpty)
        let ok = EstimatedHairMasker(faces: FakeLandmarker(faces: [EyeMakeupTests.face()]), subject: FakeMasker())
        #expect(try ok.hairMasks(in: CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))).count == 1)
    }
}
}
