import CoreImage
import Foundation
import Testing
@testable import Lumi

struct CollageRenderTests {
    static func photo(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ w: CGFloat = 400, _ h: CGFloat = 300) -> CIImage { CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: CGRect(x: 0, y: 0, width: w, height: h)) }
    static let red = photo(1, 0, 0), blue = photo(0, 0, 1)

    @Test func canvasHasTheLayoutAspect() {
        let l = CollageLayout.grid(rows: 1, cols: 2, aspect: 3.0 / 4)
        let out = CollageRenderer.render(CollageState(layout: l, photoCount: 2), photos: [Self.red, Self.blue], width: 300)
        #expect(out.extent == CGRect(x: 0, y: 0, width: 300, height: 400))
    }

    @Test func eachSlotShowsItsPhotoAndGapsShowTheBackground() {
        var l = CollageLayout.grid(rows: 1, cols: 2, aspect: 1, gap: 0.05)
        l.id = "t"
        let out = CollageRenderer.render(CollageState(layout: l, photoCount: 2), photos: [Self.red, Self.blue], width: 200, background: RGBA(r: 0, g: 1, b: 0, a: 1))
        #expect(GeometryTests.rgb(out, x: 50, y: 100)[0] > 200)                          // left slot: first photo (red)
        #expect(GeometryTests.rgb(out, x: 150, y: 100)[2] > 200)                         // right slot: second photo
        #expect(GeometryTests.rgb(out, x: 100, y: 100)[1] > 200)                         // gutter between: background
    }

    @Test func swappingSlotsSwapsThePictures() {
        let l = CollageLayout.grid(rows: 1, cols: 2)
        var s = CollageState(layout: l, photoCount: 2); s.swap(0, 1)
        let out = CollageRenderer.render(s, photos: [Self.red, Self.blue], width: 200)
        #expect(GeometryTests.rgb(out, x: 50, y: 100)[2] > 200 && GeometryTests.rgb(out, x: 150, y: 100)[0] > 200)
    }

    @Test func bordersShrinkTheSlotsAndCornersRoundThem() {
        let l = CollageLayout.grid(rows: 1, cols: 1, gap: 0.0)
        var s = CollageState(layout: l, photoCount: 1)
        let plain = CollageRenderer.render(s, photos: [Self.red], width: 200, background: RGBA(r: 0, g: 1, b: 0, a: 1))
        #expect(GeometryTests.rgb(plain, x: 3, y: 100)[0] > 200)                          // photo reaches the edge
        s.border = 0.05
        let framed = CollageRenderer.render(s, photos: [Self.red], width: 200, background: RGBA(r: 0, g: 1, b: 0, a: 1))
        #expect(GeometryTests.rgb(framed, x: 3, y: 100)[1] > 200)                         // now the edge is background
        s.border = 0; s.cornerRadius = 0.5
        let round = CollageRenderer.render(s, photos: [Self.red], width: 200, background: RGBA(r: 0, g: 1, b: 0, a: 1))
        #expect(GeometryTests.rgb(round, x: 1, y: 1)[1] > 200 && GeometryTests.rgb(round, x: 100, y: 100)[0] > 200)
    }

    @Test func heartAndTriangleSlotsClipThePhoto() throws {
        let heart = try #require(CollageLayout.builtin.first { $0.id == "heart" }), tri = try #require(CollageLayout.builtin.first { $0.id == "triangle" })
        let h = CollageRenderer.render(CollageState(layout: heart, photoCount: 1), photos: [Self.red], width: 300, background: RGBA(r: 0, g: 1, b: 0, a: 1))
        #expect(GeometryTests.rgb(h, x: 150, y: 150)[0] > 200)                            // middle of the heart is photo
        #expect(GeometryTests.rgb(h, x: Int(h.extent.width) / 2, y: 5)[1] > 150 && GeometryTests.rgb(h, x: 3, y: 3)[1] > 200)   // heart's tip region / corner is background
        let t = CollageRenderer.render(CollageState(layout: tri, photoCount: 1), photos: [Self.red], width: 300, background: RGBA(r: 0, g: 1, b: 0, a: 1))
        #expect(GeometryTests.rgb(t, x: 150, y: 100)[0] > 200 && GeometryTests.rgb(t, x: 30, y: 270)[1] > 200)
    }

    @Test func zoomAndPanChooseTheVisiblePartOfThePhoto() {
        // photo: left half red, right half blue
        let two = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 200, y: 0, width: 200, height: 300)).composited(over: Self.red)
        var s = CollageState(layout: CollageLayout.grid(rows: 1, cols: 1, gap: 0), photoCount: 1)
        s.setZoom(2, slot: 0); s.setPan(CGPoint(x: 1, y: 0), slot: 0)                      // zoom in and look at the right side
        let out = CollageRenderer.render(s, photos: [two], width: 200)
        #expect(GeometryTests.rgb(out, x: 100, y: 130)[2] > 200)
        s.setPan(CGPoint(x: -1, y: 0), slot: 0)
        #expect(GeometryTests.rgb(CollageRenderer.render(s, photos: [two], width: 200), x: 100, y: 130)[0] > 200)
    }

    @Test func noPhotosOrBadIndicesGiveJustTheBackground() {
        let l = CollageLayout.grid(rows: 1, cols: 2)
        let out = CollageRenderer.render(CollageState(layout: l, photoCount: 2), photos: [], width: 100)
        #expect(out.extent.width == 100 && GeometryTests.rgb(out, x: 50, y: 50)[0] > 240)
        var s = CollageState(layout: l, photoCount: 2); s.swap(0, 1)
        _ = CollageRenderer.render(s, photos: [Self.red], width: 100)                      // second photo missing: slot skipped, no crash
    }

    @Test func everyBundledLayoutRenders() {
        for l in CollageLayout.builtin {
            let n = l.slots.count
            let photos = (0..<n).map { _ in Self.red }
            let out = CollageRenderer.render(CollageState(layout: l, photoCount: n), photos: photos, width: 120)
            #expect(out.extent.width == 120, "\(l.id)")
        }
    }
}
