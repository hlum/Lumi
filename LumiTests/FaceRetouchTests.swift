import CoreImage
import Foundation
import Testing
@testable import Lumi

struct FakeLandmarker: FaceLandmarking {
    var faces: [FaceInfo]
    func faces(in image: CIImage) throws -> [FaceInfo] { faces }
}

extension ServicesSerial {
struct FaceRetouchTests {
    static let ext = CGRect(x: 0, y: 0, width: 300, height: 300)
    static func face() -> FaceInfo { var f = MakeupPlacementTests.face(); f.box = CGRect(x: 0.25, y: 0.2, width: 0.5, height: 0.6); return f }
    static func photo() -> CIImage { CIImage(color: CIColor(red: 0.7, green: 0.5, blue: 0.4)).cropped(to: ext) }

    @Test func identityAndNoFacesChangeNothing() {
        #expect(FaceRetouch().isIdentity)
        var r = FaceRetouch(); r.skin.smooth = 1
        #expect(FaceRetouchRender.apply(r, to: Self.photo(), faces: []).extent == Self.ext)
        #expect(GeometryTests.near(RendererTests.pixel(FaceRetouchRender.apply(FaceRetouch(), to: Self.photo(), faces: [Self.face()])), RendererTests.pixel(Self.photo())))
    }

    @Test func everyGroupChangesPixelsOnTheFace() {
        let f = Self.face(), base = Self.photo()
        func differs(_ r: FaceRetouch) -> Bool {
            let out = FaceRetouchRender.apply(r, to: base, faces: [f])
            return stride(from: 100, to: 200, by: 7).contains { x in stride(from: 80, to: 240, by: 9).contains { y in GeometryTests.rgb(out, x: x, y: y) != GeometryTests.rgb(base, x: x, y: y) } }
        }
        var w = FaceRetouch(); w.skin.whiten = 1
        var m = FaceRetouch(); m.makeup.lipOpacity = 1; m.makeup.blushOpacity = 1
        var d = FaceRetouch(); d.detail.flash = 1
        #expect(differs(w) && differs(m) && differs(d))
    }

    @Test func reshapeWarpsAPatternedImage() {
        let pattern = CIFilter(name: "CICheckerboardGenerator", parameters: ["inputWidth": 10, "inputColor0": CIColor.white, "inputColor1": CIColor.black])!.outputImage!.cropped(to: Self.ext)
        var r = FaceRetouch(); r.reshape.eyeSize = 1; r.reshape.jawSlim = 1
        let out = FaceRetouchRender.apply(r, to: pattern, faces: [Self.face()])
        #expect(out.extent == Self.ext)
        #expect((60..<240).contains { x in (60..<240).contains { y in GeometryTests.rgb(out, x: x, y: y) != GeometryTests.rgb(pattern, x: x, y: y) } })
    }

    @Test func lookStrengthScalesTheOperation() {
        let l = AutoBeauty.looks[2]
        #expect(FaceRetouch.look(l, strength: 0).isIdentity)
        let half = FaceRetouch.look(l, strength: 0.5), full = FaceRetouch.look(l)
        #expect(abs(half.skin.smooth * 2 - full.skin.smooth) < 1e-9 && !full.isIdentity)
    }

    @Test func operationRoundTripsAndRendersThroughTheDocumentWithCachedDetection() throws {
        Renderer.services = Renderer.Services(); Renderer.services.faceLandmarker = FakeLandmarker(faces: [Self.face()])
        defer { Renderer.services = Renderer.Services() }
        var d = EditDocument(); d.face.skin.whiten = 1
        #expect(try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d)).face == d.face)
        let img = Self.photo()
        let a = Renderer.render(img, document: d)
        #expect(GeometryTests.rgb(a, x: 150, y: 170) != GeometryTests.rgb(img, x: 150, y: 170))
        d.face.skin.whiten = 0.5                                                               // slider drag: same image, same prefix -> reuse the detection
        _ = Renderer.render(img, document: d)
        #expect(Renderer.services.faceCacheKeyCount == 1)
        d.face = FaceRetouch(); #expect(d.operations.isEmpty)
    }

    @Test func withoutALandmarkerTheImageIsUnchanged() {
        Renderer.services = Renderer.Services()
        var d = EditDocument(); d.face.skin.whiten = 1
        #expect(GeometryTests.near(RendererTests.pixel(Renderer.render(Self.photo(), document: d)), RendererTests.pixel(Self.photo())))
    }

    @Test func visionLandmarkerRunsOnAnImageWithNoFace() throws {
        let faces = try VisionFaceLandmarker().faces(in: CIImage(color: .gray).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200)))
        #expect(faces.isEmpty)
    }
}
}
