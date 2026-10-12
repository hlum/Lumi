import CoreImage
import Foundation
import Testing
@testable import Lumi

struct ReplaceTextTests {
    private func crop(bg: (UInt8, UInt8, UInt8), fg: (UInt8, UInt8, UInt8), textShare: Double = 0.2, n: Int = 400) -> [UInt8] {
        (0..<n).flatMap { i -> [UInt8] in Double(i % 100) / 100 < textShare ? [fg.0, fg.1, fg.2, 255] : [bg.0, bg.1, bg.2, 255] }
    }

    @Test func darkTextOnLightAndLightTextOnDark() throws {
        let a = try #require(ReplaceText.sampleColors(rgba: crop(bg: (240, 240, 235), fg: (20, 20, 25))))
        #expect(a.background.r > 0.85 && a.text.r < 0.2)
        let b = try #require(ReplaceText.sampleColors(rgba: crop(bg: (20, 30, 90), fg: (250, 240, 200))))
        #expect(b.background.b > b.background.r && b.text.r > 0.85)
    }

    @Test func coloursAreKeptNotJustBlackAndWhite() throws {
        let c = try #require(ReplaceText.sampleColors(rgba: crop(bg: (245, 245, 245), fg: (200, 30, 40))))
        #expect(c.text.r > 0.7 && c.text.g < 0.25)
    }

    @Test func aPlainCropFallsBackToAReadableColour() throws {
        let c = try #require(ReplaceText.sampleColors(rgba: crop(bg: (250, 250, 250), fg: (250, 250, 250), textShare: 0)))
        #expect(c.text.r < 0.2)
        let d = try #require(ReplaceText.sampleColors(rgba: crop(bg: (10, 10, 10), fg: (10, 10, 10), textShare: 0)))
        #expect(d.text.r > 0.8)
        #expect(ReplaceText.sampleColors(rgba: [1, 2, 3, 255]) == nil)
    }

    @Test func fontSizeFitsTheLineAndShrinksForLongText() {
        let short = ReplaceText.fontSize(for: "OPEN", fontName: "HelveticaNeue-Bold", boxWidthPx: 400, boxHeightPx: 60, photoHeightPx: 1000)
        let long = ReplaceText.fontSize(for: "OPEN 9-5 EVERY DAY OF THE WEEK", fontName: "HelveticaNeue-Bold", boxWidthPx: 400, boxHeightPx: 60, photoHeightPx: 1000)
        #expect(short > long && short <= 0.06 * 0.83 + 1e-6)
        #expect(ReplaceText.fontSize(for: "", fontName: "x", boxWidthPx: 1, boxHeightPx: 1, photoHeightPx: 1) == 0.04)
    }

    @Test func planRemovesTheOldLineAndPlacesTheNewTextThere() throws {
        let img = CIImage(color: CIColor(red: 0.95, green: 0.95, blue: 0.9)).cropped(to: CGRect(x: 0, y: 0, width: 1000, height: 800))
        let line = TextLine(text: "OPEN 8-6", box: CGRect(x: 0.2, y: 0.6, width: 0.4, height: 0.08))
        let plan = try #require(ReplaceText.plan(line: line, newText: " OPEN 9-5 ", in: img))
        #expect(plan.mask[Int(0.4 * Double(plan.mask.width)), Int((1 - 0.64) * Double(plan.mask.height))] == 255)
        #expect(plan.mask[2, 2] == 0)
        guard case .text(let s, let style) = plan.layer.content else { Issue.record("not text"); return }
        #expect(s == "OPEN 9-5" && style.size > 0 && style.size < 0.1)
        #expect(abs(plan.layer.transform.center.x - 0.4) < 1e-9 && abs(plan.layer.transform.center.y - (1 - 0.64)) < 1e-9)
        #expect(ReplaceText.plan(line: line, newText: "  ", in: img) == nil)
    }

    @Test func planInTheDocumentLeavesTheTextOnTopOfTheRemoval() throws {
        let img = CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
        let plan = try #require(ReplaceText.plan(line: TextLine(text: "x", box: CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1)), newText: "New", in: img))
        var d = EditDocument()
        d.layers = { var s = LayerStack(); try? s.add(Layer(content: .text("Old caption", TextStyle()))); return s }()
        d.removals = d.removals + [plan.mask]
        var stack = d.layers; try? stack.add(plan.layer); d.layers = stack
        let kinds = d.operations.map(\.kind)
        #expect(kinds.firstIndex(of: .remove)! < kinds.lastIndex(of: .layers)!)
    }

    @Test func captionIdeasUseWhatTheSceneContains() {
        #expect(SceneCaptionSuggester.captions(from: ["beach", "sky"]).contains("Beach and sky"))
        #expect(SceneCaptionSuggester.captions(from: []).count == 3)
        #expect(SceneCaptionSuggester.captions(from: ["cat"]).allSatisfy { $0.localizedCaseInsensitiveContains("cat") })
    }
}
