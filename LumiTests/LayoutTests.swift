import CoreGraphics
import Foundation
import Testing
@testable import Lumi

struct LayoutTests {
    @Test func gridSlotsAreInsideCanvasAndDoNotOverlap() {
        for l in CollageLayout.builtin {
            for s in l.slots {
                #expect(s.rect.minX >= 0 && s.rect.minY >= 0 && s.rect.maxX <= 1.0000001 && s.rect.maxY <= 1.0000001 && s.rect.width > 0 && s.rect.height > 0, "\(l.id)")
            }
            for (i, a) in l.slots.enumerated() { for b in l.slots[(i + 1)...] { #expect(!a.rect.insetBy(dx: 1e-9, dy: 1e-9).intersects(b.rect), "\(l.id)") } }
        }
    }

    @Test func builtinHasManyUniqueLayoutsIncludingNineGridAndShapes() {
        let ids = CollageLayout.builtin.map(\.id)
        #expect(Set(ids).count == ids.count && ids.count >= 50)
        #expect(CollageLayout.builtin.first { $0.id == "nine-grid" }?.slots.count == 9)
        #expect(CollageLayout.builtin.contains { $0.slots.contains { $0.shape == .heart } })
        #expect(CollageLayout.builtin.contains { $0.slots.contains { $0.shape == .triangle } })
    }

    @Test func layoutsSurviveJSON() throws {
        let data = try JSONEncoder().encode(CollageLayout.builtin)
        #expect(try JSONDecoder().decode([CollageLayout].self, from: data) == CollageLayout.builtin)
    }

    @Test func autoPickMatchesPhotoCountAndAspect() {
        let portrait = CollageLayout.autoPick(photoAspects: [0.75, 0.75, 0.75, 0.75])!
        let landscape = CollageLayout.autoPick(photoAspects: [1.5, 1.5, 1.5, 1.5])!
        #expect(portrait.slots.count == 4 && landscape.slots.count == 4)
        func slotAspect(_ l: CollageLayout) -> Double { Double(l.slots[0].rect.width / l.slots[0].rect.height) * l.aspect }
        #expect(slotAspect(portrait) < slotAspect(landscape))
    }

    @Test func autoPickWithNoMatchIsNil() {
        #expect(CollageLayout.autoPick(photoAspects: Array(repeating: 1, count: 99)) == nil)
        #expect(CollageLayout.autoPick(photoAspects: []) == nil)
    }

    @Test func swappingSlotsExchangesPhotos() {
        var s = CollageState(layout: .grid(rows: 1, cols: 3), photoCount: 3)
        s.swap(0, 2)
        #expect(s.fills.map(\.photo) == [2, 1, 0])
        s.swap(0, 0); s.swap(0, 9); s.swap(-1, 1)
        #expect(s.fills.map(\.photo) == [2, 1, 0])
    }

    @Test func fewerPhotosThanSlotsRepeat() {
        #expect(CollageState(layout: .grid(rows: 2, cols: 2), photoCount: 2).fills.map(\.photo) == [0, 1, 0, 1])
        #expect(CollageState(layout: .grid(rows: 1, cols: 2), photoCount: 0).fills.map(\.photo) == [0, 0])
    }

    @Test func zoomAndPanAreClamped() {
        var s = CollageState(layout: .grid(rows: 1, cols: 2), photoCount: 2)
        s.setZoom(100, slot: 0); s.setZoom(0.1, slot: 1)
        #expect(s.fills[0].zoom == 8 && s.fills[1].zoom == 1)
        s.setPan(CGPoint(x: 5, y: -5), slot: 0)
        #expect(s.fills[0].pan == CGPoint(x: 1, y: -1))
        s.setZoom(2, slot: 7); s.setPan(.zero, slot: -1)
    }

    @Test func sourceCropFillsSlotAndStaysInsideImage() {
        let img = CGSize(width: 4000, height: 3000)
        for zoom in [1.0, 2.5, 8] { for pan in [CGPoint(x: -1, y: -1), .zero, CGPoint(x: 1, y: 1)] {
            let c = CollageMath.sourceCrop(image: img, slotAspect: 1, zoom: zoom, pan: pan)
            #expect(abs(Double(c.width / c.height) - 1) < 1e-9)
            #expect(c.minX >= 0 && c.minY >= 0 && c.maxX <= 4000.0001 && c.maxY <= 3000.0001)
        } }
    }

    @Test func zoomShrinksTheCropAndPanMovesIt() {
        let img = CGSize(width: 1000, height: 1000)
        let a = CollageMath.sourceCrop(image: img, slotAspect: 1, zoom: 1, pan: .zero)
        let b = CollageMath.sourceCrop(image: img, slotAspect: 1, zoom: 2, pan: CGPoint(x: -1, y: -1))
        let c = CollageMath.sourceCrop(image: img, slotAspect: 1, zoom: 2, pan: CGPoint(x: 1, y: 1))
        #expect(a == CGRect(x: 0, y: 0, width: 1000, height: 1000))
        #expect(b.width == 500 && b.minX == 0 && c.maxX == 1000)
    }

    @Test func degenerateInputsGiveEmptyCrop() {
        #expect(CollageMath.sourceCrop(image: .zero, slotAspect: 1, zoom: 1, pan: .zero) == .zero)
        #expect(CollageMath.sourceCrop(image: CGSize(width: 10, height: 10), slotAspect: 0, zoom: 1, pan: .zero) == .zero)
    }
}
