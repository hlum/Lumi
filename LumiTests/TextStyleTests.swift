import CoreImage
import Foundation
import Testing
import UIKit
@testable import Lumi

extension ServicesSerial {
struct TextStyleTests {
    @Test func presetsAreUniqueAndUseRealFonts() {
        FontLibrary.registerBundled()
        #expect(TextStylePresets.all.count >= 8 && Set(TextStylePresets.all.map(\.id)).count == TextStylePresets.all.count)
        for p in TextStylePresets.all { #expect(UIFont(name: p.style.fontName, size: 12) != nil, "\(p.id): \(p.style.fontName)") }
    }

    @Test func applyingAPresetKeepsTextAndPlacement() {
        var layer = Layer(content: .text("Hello", TextStyle()))
        layer.transform.center = CGPoint(x: 0.2, y: 0.8); layer.transform.rotation = 0.5; layer.opacity = 0.7
        let out = TextStylePresets.apply(TextStylePresets.preset("neon")!, to: layer)
        guard case .text(let s, let style) = out.content else { Issue.record("not text"); return }
        #expect(s == "Hello" && style == TextStylePresets.preset("neon")!.style)
        #expect(out.transform == layer.transform && out.opacity == 0.7 && out.id == layer.id)
        let sticker = Layer(content: .sticker(id: "heart", outline: 0))
        #expect(TextStylePresets.apply(TextStylePresets.preset("neon")!, to: sticker) == sticker)           // stickers are untouched
    }

    @Test func presetsActuallyLookDifferent() throws {
        FontLibrary.registerBundled()
        let a = try #require(LayerRenderer.textImage("Ag", style: TextStylePresets.preset("clean")!.style, imageHeight: 600))
        let b = try #require(LayerRenderer.textImage("Ag", style: TextStylePresets.preset("poster")!.style, imageHeight: 600))
        #expect(a.extent.size != b.extent.size)
    }

    // MARK: behind subject
    static func scene() -> (base: CIImage, mask: CIImage) {
        let ext = CGRect(x: 0, y: 0, width: 200, height: 100)
        let base = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: ext)                       // blue world
        let mask = MosaicOps.mask(rects: [CGRect(x: 0, y: 0, width: 0.5, height: 1)], extent: ext)           // left half is the subject
        return (base, mask)
    }
    static func bigText() -> LayerStack {
        var st = TextStyle(); st.size = 1.2; st.color = RGBA(r: 1, g: 0, b: 0, a: 1)       // huge red text covering everything
        var stack = LayerStack(); try? stack.add(Layer(content: .text("MMMM", st)))
        return stack
    }

    @Test func textInFrontCoversTheSubject() {
        let (base, mask) = Self.scene()
        let out = LayerRenderer.render(Self.bigText(), over: base, subjectMask: mask)
        #expect((5..<95).contains { x in (5..<95).contains { y in GeometryTests.rgb(out, x: x, y: y)[0] > 150 } })          // red glyphs appear over the subject side too
    }

    @Test func textBehindTheSubjectIsHiddenWhereTheSubjectIs() {
        let (base, mask) = Self.scene()
        var stack = Self.bigText()
        stack.update(stack.layers[0].id) { $0.behindSubject = true }
        let out = LayerRenderer.render(stack, over: base, subjectMask: mask)
        #expect(GeometryTests.rgb(out, x: 20, y: 50)[2] > 200 && GeometryTests.rgb(out, x: 20, y: 50)[0] < 40)  // subject side: untouched blue
        let right = (110..<190).contains { GeometryTests.rgb(out, x: $0, y: 50)[0] > 150 }
        #expect(right)                                                                                          // background side: the text shows
    }

    @Test func withoutAMaskBehindSubjectJustDrawsNormally() {
        let (base, _) = Self.scene()
        var stack = Self.bigText(); stack.update(stack.layers[0].id) { $0.behindSubject = true }
        let out = LayerRenderer.render(stack, over: base, subjectMask: nil)
        #expect((10..<190).contains { GeometryTests.rgb(out, x: $0, y: 50)[0] > 150 })
    }

    @Test func rendererFindsTheSubjectOnlyWhenALayerNeedsIt() {
        Renderer.services = Renderer.Services(); Renderer.services.subjectMasker = FakeMasker()
        defer { Renderer.services = Renderer.Services() }
        let (base, _) = Self.scene()
        var d = EditDocument(); d.layers = Self.bigText()
        _ = Renderer.render(base, document: d)
        #expect(Renderer.services.inpaintCalls == 0)                                                           // no behind-subject layer: no mask work
        var stack = d.layers; stack.update(stack.layers[0].id) { $0.behindSubject = true }; d.layers = stack
        let out = Renderer.render(base, document: d)
        #expect(Renderer.services.inpaintCalls == 1)
        #expect(GeometryTests.rgb(out, x: 20, y: 50)[2] > 200)                                                  // FakeMasker's left half stays in front of the text
        _ = Renderer.render(base, document: d); #expect(Renderer.services.inpaintCalls == 1)                    // cached
    }

    @Test func behindSubjectSurvivesJSON() throws {
        var stack = Self.bigText(); stack.update(stack.layers[0].id) { $0.behindSubject = true }
        #expect(try JSONDecoder().decode(LayerStack.self, from: JSONEncoder().encode(stack)).layers[0].behindSubject)
    }

    @Test func draftsSavedBeforeNewFieldsStillOpen() throws {
        // a layer saved when `behindSubject` did not exist, and face params saved before cheek volume and lift
        let oldLayer = #"{"content":{"text":{"_0":"Hi","_1":{"fontName":"HelveticaNeue-Bold","size":0.06,"color":{"r":1,"g":1,"b":1,"a":1},"strokeWidth":0,"strokeColor":{"r":0,"g":0,"b":0,"a":1},"shadowRadius":0,"alignment":"center"}}},"transform":{"center":[0.5,0.5],"scale":1,"rotation":0,"flipH":false},"opacity":1}"#
        let layer = try JSONDecoder().decode(Layer.self, from: Data(oldLayer.utf8))
        #expect(!layer.behindSubject && layer.opacity == 1)
        let oldFace = try JSONDecoder().decode(FaceReshapeParams.self, from: Data(#"{"jawSlim":0.3,"eyeSize":0.2}"#.utf8))
        #expect(oldFace.jawSlim == 0.3 && oldFace.cheekVolume == 0 && oldFace.lift == 0)
    }
}
}
