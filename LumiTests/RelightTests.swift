import CoreImage
import Foundation
import Testing
@testable import Lumi

struct RelightTests {
    private let ctx = CIContext()
    private let face = FaceReshapeTests.face()
    private func px(_ i: CIImage, _ nx: Double, _ ny: Double) -> [Int] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: Int(nx * 200), y: Int((1 - ny) * 200), width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return b.map(Int.init)
    }
    private func scene(_ g: CGFloat = 0.3) -> CIImage { CIImage(color: CIColor(red: g, green: g, blue: g)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200)) }
    private func cfg(_ s: RelightStyle, _ v: Double = 1) -> RelightConfig { var c = RelightConfig(); c.style = s; c.strength = v; return c }
    /// Left half of the picture is the person.
    private var person: CIImage { CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 200)).composited(over: CIImage(color: .black).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 200))) }

    @Test func zeroStrengthIsIdentity() {
        let g = scene()
        for s in RelightStyle.allCases { #expect(RelightOps.apply(cfg(s, 0), to: g, faces: [face], personMask: nil) == g, "\(s)") }
        #expect(RelightConfig().isIdentity && !cfg(.flash).isIdentity)
    }

    @Test func everyStyleKeepsTheFrame() {
        for s in RelightStyle.allCases { #expect(RelightOps.apply(cfg(s), to: scene(), faces: [face], personMask: person).extent == scene().extent, "\(s)") }
    }

    @Test func flashLightsThePersonAndDarkensTheBackground() {
        let out = RelightOps.apply(cfg(.flash), to: scene(0.4), faces: [], personMask: person)
        #expect(px(out, 0.2, 0.5)[0] > px(scene(0.4), 0.2, 0.5)[0] + 20)
        #expect(px(out, 0.8, 0.5)[0] < px(scene(0.4), 0.8, 0.5)[0] - 10)
    }

    @Test func fillLightAndBacklitLiftTheDarkParts() {
        let dark = scene(0.12)
        #expect(px(RelightOps.apply(cfg(.fillLight), to: dark, faces: [], personMask: person), 0.2, 0.5)[0] > px(dark, 0.2, 0.5)[0] + 8)
        let b = RelightOps.apply(cfg(.backlit), to: dark, faces: [face], personMask: nil)
        let c = FaceReshape.center(FaceReshape.points(face, "nose"))!
        #expect(px(b, Double(c.x), Double(c.y))[0] > px(dark, Double(c.x), Double(c.y))[0] + 20)
        #expect(abs(px(b, 0.02, 0.02)[0] - px(dark, 0.02, 0.02)[0]) < 6)             // the corner is not part of the face
    }

    @Test func nightLiftsShadowsEverywhere() {
        let dark = scene(0.1)
        #expect(px(RelightOps.apply(cfg(.night), to: dark, faces: [], personMask: nil), 0.5, 0.5)[0] > px(dark, 0.5, 0.5)[0] + 10)
    }

    @Test func colouredLooksTintThePersonOnly() {
        let out = RelightOps.apply(cfg(.redLight), to: scene(0.5), faces: [], personMask: person)
        let p = px(out, 0.2, 0.5), bg = px(out, 0.8, 0.5)
        #expect(p[0] > p[2] + 30 && abs(bg[0] - bg[2]) < 8)
    }

    @Test func eraserBringsBackTheUnlitPicture() {
        var c = cfg(.fillLight); var m = MaskCanvas(width: 20, height: 20); m.fill(rect: CGRect(x: 0, y: 0, width: 10, height: 20)); c.erase = m
        let dark = scene(0.12)
        let out = RelightOps.apply(c, to: dark, faces: [], personMask: nil)
        #expect(abs(px(out, 0.2, 0.5)[0] - px(dark, 0.2, 0.5)[0]) < 4)             // erased half is back to the original
        #expect(px(out, 0.8, 0.5)[0] > px(dark, 0.8, 0.5)[0] + 8)
    }

    @Test func faceMaskCoversFacesAndDocumentRoundTrips() throws {
        let m = RelightOps.faceMask([face], size: CGSize(width: 200, height: 200))!
        let c = MakeupRenderer.faceBox(face)
        #expect(px(m, Double(c.midX), Double(c.midY))[0] > 200 && px(m, 0.02, 0.02)[0] < 20)
        #expect(RelightOps.faceMask([], size: CGSize(width: 10, height: 10)) == nil)
        var d = EditDocument(); d.relight = cfg(.night, 0.5); d.effect = PhotoEffectConfig(effect: .zoomBlur, strength: 0.4)
        let back = try JSONDecoder().decode(EditDocument.self, from: JSONEncoder().encode(d))
        #expect(back.relight == d.relight && back.effect == d.effect && d.operations.count == 2)
        d.relight = RelightConfig(); d.effect = PhotoEffectConfig(); #expect(d.operations.isEmpty)
    }

    @Test func rendererRunsRelightWithServices() {
        let saved = (Renderer.services.faceLandmarker, Renderer.services.subjectMasker)
        defer { (Renderer.services.faceLandmarker, Renderer.services.subjectMasker) = saved }
        Renderer.services.faceLandmarker = nil; Renderer.services.subjectMasker = nil
        var d = EditDocument(); d.relight = cfg(.night, 1)
        #expect(Renderer.render(scene(0.1), document: d).extent == scene().extent)
    }
}
