import CoreImage
import Testing
@testable import Lumi

struct FreeformCollageTests {
    private let ctx = CIContext(options: [.workingColorSpace: NSNull()])
    private func px(_ i: CIImage, _ x: Int, _ y: Int) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 4)
        ctx.render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: Int(i.extent.height) - 1 - y, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        return b
    }
    private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CIImage { CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)) }

    @Test func editingClampsAndStacks() {
        var f = FreeformCollage(); f.add(photo: 0); f.add(photo: 1)
        f.move(0, to: CGPoint(x: 5, y: -5)); #expect(f.items[0].center == CGPoint(x: 1, y: 0))
        f.scale(0, by: 100); #expect(f.items[0].width == 1.5)
        f.scale(0, by: 0.0001); #expect(f.items[0].width == 0.1)
        f.rotate(1, by: 1); f.rotate(1, by: 0.5); #expect(f.items[1].rotation == 1.5)
        f.bringToFront(0); #expect(f.items.last?.photo == 0)
        f.remove(9); f.remove(0); #expect(f.items.count == 1)
    }

    @Test func hitTestPicksTopmostAndRespectsRotation() {
        var f = FreeformCollage()
        f.items = [.init(photo: 0, center: CGPoint(x: 0.5, y: 0.5), width: 0.4), .init(photo: 1, center: CGPoint(x: 0.5, y: 0.5), width: 0.2)]
        #expect(f.item(at: CGPoint(x: 0.5, y: 0.5), photoAspects: [1, 1]) == 1)
        #expect(f.item(at: CGPoint(x: 0.65, y: 0.5), photoAspects: [1, 1]) == 0)
        #expect(f.item(at: CGPoint(x: 0.95, y: 0.95), photoAspects: [1, 1]) == nil)
        f.items = [.init(photo: 0, center: CGPoint(x: 0.5, y: 0.5), width: 0.6, rotation: .pi / 2)]
        #expect(f.item(at: CGPoint(x: 0.5, y: 0.5), photoAspects: [2]) != nil)       // wide photo turned upright
        #expect(f.item(at: CGPoint(x: 0.5, y: 0.78), photoAspects: [2]) != nil)
        #expect(f.item(at: CGPoint(x: 0.78, y: 0.5), photoAspects: [2]) == nil)
    }

    @Test func renderPlacesPhotosAndLaterOnesCoverEarlier() {
        var f = FreeformCollage()
        f.items = [.init(photo: 0, center: CGPoint(x: 0.5, y: 0.5), width: 0.8), .init(photo: 1, center: CGPoint(x: 0.5, y: 0.5), width: 0.3)]
        let out = FreeformRenderer.render(f, photos: [solid(1, 0, 0), solid(0, 0, 1)], width: 200)
        #expect(out.extent.size == CGSize(width: 200, height: 200))
        #expect(px(out, 100, 100)[2] > 230)                                     // blue on top
        #expect(px(out, 100, 40)[0] > 230)                                      // red around it
        #expect(px(out, 5, 5)[0] > 230 && px(out, 5, 5)[1] > 230)               // white corner
    }

    @Test func splitLayoutsTileTheCanvas() {
        for v in [true, false] {
            let l = CollageLayout.split(vertical: v, ratio: 0.3)
            #expect(l.slots.count == 2)
            let area = l.slots.map { $0.rect.width * $0.rect.height }.reduce(0, +)
            #expect(abs(area - 1) < 1e-9)
        }
        #expect(CollageLayout.split(vertical: true, ratio: 0.99).slots[0].rect.width == 0.8)
    }

    @Test func seamlessRemovesGapsOnGridsOnly() {
        let s = CollageLayout.grid(rows: 2, cols: 3).seamless
        #expect(s.slots.count == 6 && abs(s.slots.map { $0.rect.width * $0.rect.height }.reduce(0, +) - 1) < 1e-9)
        #expect(s.slots[0].rect.minX == 0 && s.slots[5].rect.maxX == 1)
        let heart = CollageLayout.builtin.first { $0.id == "heart" }!
        #expect(heart.seamless == heart)
    }

    @Test func recipesResolveToStates() {
        for r in CollageRecipe.builtin { #expect(r.state(photoCount: 4) != nil, "\(r.id)") }
        #expect(CollageRecipe(id: "x", name: "x", layoutID: "nope", filterID: nil, stickers: []).state(photoCount: 1) == nil)
        let seam = CollageRecipe.builtin.first { $0.id == "seamless-quad" }!.state(photoCount: 4)!
        #expect(seam.layout.slots[0].rect.minX == 0)
    }
}
