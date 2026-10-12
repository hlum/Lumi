import CoreImage
import Foundation
import Testing
@testable import Lumi

struct SkinStyleTests {
    private let ctx = CIContext()
    private func px(_ i: CIImage, _ x: Int, _ y: Int) -> [Int] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: y, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return b.map(Int.init)
    }
    private func flat(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ s: CGFloat = 64) -> CIImage { CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: CGRect(x: 0, y: 0, width: s, height: s)) }
    private func all(_ img: CIImage) -> CIImage { CIImage(color: .white).cropped(to: img.extent) }

    @Test func whitenLiftsMidtonesButKeepsBlackAndWhite() {
        var p = SkinParams(); p.whiten = 1
        #expect(px(SkinOps.apply(p, to: flat(0.5, 0.5, 0.5), mask: all(flat(0, 0, 0))), 5, 5)[0] > px(flat(0.5, 0.5, 0.5), 5, 5)[0] + 15)
        let black = flat(0, 0, 0), white = flat(1, 1, 1)
        #expect(px(SkinOps.apply(p, to: black, mask: all(black)), 5, 5)[0] <= 3 && px(SkinOps.apply(p, to: white, mask: all(white)), 5, 5)[0] >= 252)
    }

    @Test func tanDarkensMidtones() {
        var p = SkinParams(); p.tan = 1
        let img = flat(0.6, 0.45, 0.4)
        #expect(px(SkinOps.apply(p, to: img, mask: all(img)), 5, 5)[0] < px(img, 5, 5)[0] - 8)
    }

    @Test func evenOutLevelsColourBlotchesAndKeepsLight() {
        // left half reddish, right half greenish-yellow, same brightness
        let left = flat(0.75, 0.45, 0.4).cropped(to: CGRect(x: 0, y: 0, width: 32, height: 64)), right = flat(0.6, 0.6, 0.35).cropped(to: CGRect(x: 32, y: 0, width: 32, height: 64))
        let img = right.composited(over: left)
        var p = SkinParams(); p.even = 1
        let out = SkinOps.apply(p, to: img, mask: all(img))
        func chromaGap(_ i: CIImage) -> Int { abs((px(i, 30, 32)[0] - px(i, 30, 32)[1]) - (px(i, 34, 32)[0] - px(i, 34, 32)[1])) }
        #expect(chromaGap(out) < chromaGap(img))
    }

    @Test func matteCalmsHighlightsAndGlowAddsLight() {
        let shiny = flat(0.95, 0.85, 0.8)
        var m = SkinParams(); m.matte = 1
        #expect(px(SkinOps.apply(m, to: shiny, mask: all(shiny)), 5, 5)[0] <= px(shiny, 5, 5)[0])
        var g = SkinParams(); g.glow = 1
        let dim = flat(0.5, 0.4, 0.35)
        #expect(px(SkinOps.apply(g, to: dim, mask: all(dim)), 5, 5)[0] >= px(dim, 5, 5)[0])
        #expect(!m.isIdentity && !g.isIdentity && SkinParams().isIdentity)
    }

    @Test func oldSkinDraftsDecode() throws {
        let old = #"{"smooth":0.3,"texture":0.7,"whiten":0.1,"rosy":0,"tan":0}"#
        let p = try JSONDecoder().decode(SkinParams.self, from: Data(old.utf8))
        #expect(p.smooth == 0.3 && p.texture == 0.7 && p.even == 0 && p.glow == 0)
        var n = SkinParams(); n.even = 0.4; n.matte = 0.2
        #expect(try JSONDecoder().decode(SkinParams.self, from: JSONEncoder().encode(n)) == n)
    }
}
