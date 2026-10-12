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

    // MARK: hair shape
    static func faceInfo() -> FaceInfo { EyeMakeupTests.face() }

    @Test func volumeAndHairlineRulesPlaceStrokesAboveTheFace() {
        let f = Self.faceInfo(), box = MakeupRenderer.faceBox(f)
        let v = HairShapeRules.strokes(faces: [f], volume: 1, hairline: 0)
        #expect(v.count == 1 && v[0].kind == .bloat && Double(v[0].y) < box.minY)                    // the crown is above the face
        #expect(HairShapeRules.strokes(faces: [f], volume: -1, hairline: 0)[0].kind == .pinch)
        let up = HairShapeRules.strokes(faces: [f], volume: 0, hairline: 1), down = HairShapeRules.strokes(faces: [f], volume: 0, hairline: -1)
        #expect(up[0].dirY < 0 && down[0].dirY > 0)                                                  // positive raises the hairline (up is negative y)
        #expect(HairShapeRules.strokes(faces: [], volume: 1, hairline: 1).isEmpty && HairShapeRules.strokes(faces: [f], volume: 0, hairline: 0).isEmpty)
    }

    @Test func volumeAndHairlineMoveThePicture() {
        let pattern = CIFilter(name: "CILinearGradient", parameters: ["inputPoint0": CIVector(x: 0, y: 0), "inputPoint1": CIVector(x: 0, y: 300), "inputColor0": CIColor.black, "inputColor1": CIColor.white])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 300, height: 300))
        var h = HairRetouch(); h.volume = 1; h.hairline = 0.5
        let out = HairRetouchRender.apply(h, to: pattern, hairMasks: [], faces: [Self.faceInfo()])
        let strokes = HairShapeRules.strokes(faces: [Self.faceInfo()], volume: 1, hairline: 0.5)
        var w = WarpEdit(); strokes.forEach { w.add($0) }
        let moved = (0..<300).contains { x in (150..<300).contains { y in GeometryTests.rgb(out, x: x, y: y) != GeometryTests.rgb(pattern, x: x, y: y) } }
        #expect(out.extent == pattern.extent && moved, "strokes \(strokes.count) identity \(w.field.isIdentity) kernel \(MeshWarpRenderer.loadError ?? "ok") off \(w.field.offset(x: 0.5, y: 0.1)) off2 \(w.field.offset(x: 0.5, y: 0.3)) outpx \(GeometryTests.rgb(out, x: 100, y: 250)) inpx \(GeometryTests.rgb(pattern, x: 100, y: 250))")
        #expect(GeometryTests.near(RendererTests.pixel(HairRetouchRender.apply(h, to: pattern, hairMasks: [], faces: [])), RendererTests.pixel(pattern)))      // no faces: nothing to warp
    }

    @Test func glowBrightensHairHighlightsOnly() {
        let img = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 0.95)).cropped(to: CGRect(x: 40, y: 70, width: 20, height: 20)).composited(over: CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3)).cropped(to: Self.ext))
        var h = HairRetouch(); h.glow = 1
        let out = HairRetouchRender.apply(h, to: img, hairMasks: [Self.topHair])
        func l(_ i: CIImage, _ y: Int) -> Int { let c = GeometryTests.rgb(i, x: 50, y: y); return Int(c[0]) + Int(c[1]) + Int(c[2]) }
        #expect(l(out, 80) >= l(img, 80) - 3 && l(out, 64) > l(img, 64), "out \(l(out, 80)) img \(l(img, 80)) top \(GeometryTests.rgb(out, x: 50, y: 80)) \(GeometryTests.rgb(img, x: 50, y: 80)) halo \(l(out, 64)) vs \(l(img, 64))")
        #expect(GeometryTests.near(GeometryTests.rgb(out, x: 50, y: 10), GeometryTests.rgb(img, x: 50, y: 10)))
    }

    @Test func flyawayCleanupSoftensOnlyTheOutline() {
        let stripes = CIFilter(name: "CIStripesGenerator", parameters: ["inputWidth": 2, "inputColor0": CIColor.white, "inputColor1": CIColor.black])!.outputImage!.cropped(to: Self.ext)
        var h = HairRetouch(); h.flyaway = 1
        let out = HairRetouchRender.apply(h, to: stripes, hairMasks: [Self.topHair])
        let nearEdge = (45..<55).contains { y in (0..<100).contains { x in GeometryTests.rgb(out, x: x, y: y) != GeometryTests.rgb(stripes, x: x, y: y) } }
        let farFromEdge = (75..<95).contains { y in (0..<100).contains { x in GeometryTests.rgb(out, x: x, y: y) != GeometryTests.rgb(stripes, x: x, y: y) } }
        #expect(nearEdge && !farFromEdge)
    }

    @Test func thinSpotFillGoesThroughTheInpainter() {
        var h = HairRetouch()
        var spot = MaskCanvas(width: 20, height: 20); spot.fill(rect: CGRect(x: 0, y: 0, width: 20, height: 5))          // top rows of the picture
        h.fill = spot
        let out = HairRetouchRender.apply(h, to: Self.brown(), hairMasks: [Self.topHair], inpainter: FakeInpainter())    // fake paints green where masked
        #expect(GeometryTests.rgb(out, x: 50, y: 97)[1] > 200 && GeometryTests.near(GeometryTests.rgb(out, x: 50, y: 30), GeometryTests.rgb(Self.brown(), x: 50, y: 30)))
        #expect(GeometryTests.near(RendererTests.pixel(HairRetouchRender.apply(h, to: Self.brown(), hairMasks: [Self.topHair], inpainter: nil)), RendererTests.pixel(Self.brown())))   // no inpainter: unchanged
    }

    @Test func shapeFieldsPersistAndOldHairDraftsOpen() throws {
        var h = HairRetouch(); h.volume = 0.4; h.glow = 0.3; h.fill = MaskCanvas(width: 4, height: 4)
        #expect(!h.isIdentity)
        #expect(try JSONDecoder().decode(HairRetouch.self, from: JSONEncoder().encode(h)) == h)
        let old = try JSONDecoder().decode(HairRetouch.self, from: Data(#"{"dye":{"color":{"r":1,"g":0,"b":0,"a":1},"strength":0.5,"keepShine":0.5},"deOil":0.2}"#.utf8))
        #expect(old.deOil == 0.2 && old.volume == 0 && old.fill == nil)
    }
}
}
