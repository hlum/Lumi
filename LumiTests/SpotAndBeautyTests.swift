import CoreImage
import Foundation
import Testing
@testable import Lumi

struct SpotAndBeautyTests {
    static func skin(_ w: Int = 100, _ h: Int = 100, dots: [(Int, Int, Int)] = [], value: UInt8 = 200, dotValue: UInt8 = 120) -> GrayImage {
        var px = [UInt8](repeating: value, count: w * h)
        for (cx, cy, r) in dots { for y in 0..<h { for x in 0..<w where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r { px[y * w + x] = dotValue } } }
        return GrayImage(width: w, height: h, pixels: px)
    }

    @Test func cleanSkinHasNoSpots() { #expect(SpotDetector.detect(Self.skin()).isEmpty) }

    @Test func findsEachDotNearItsCenter() {
        let spots = SpotDetector.detect(Self.skin(dots: [(25, 30, 3), (70, 60, 4)]))
        #expect(spots.count == 2)
        #expect(abs(spots[0].center.x - 25.5) < 1.5 && abs(spots[0].center.y - 30.5) < 1.5)
        #expect(abs(spots[1].center.x - 70.5) < 1.5 && spots[1].radius > spots[0].radius)
    }

    @Test func largeDarkAreasAreNotBlemishes() {
        #expect(SpotDetector.detect(Self.skin(dots: [(50, 50, 20)])).isEmpty)           // a shadow, not a spot
    }

    @Test func elongatedStreaksAreIgnored() {
        var px = [UInt8](repeating: 200, count: 100 * 100)
        for x in 20..<60 { px[50 * 100 + x] = 100; px[51 * 100 + x] = 100 }             // a hair-like line
        #expect(SpotDetector.detect(GrayImage(width: 100, height: 100, pixels: px)).isEmpty)
    }

    @Test func faintDeviationsBelowThresholdAreIgnored() {
        #expect(SpotDetector.detect(Self.skin(dots: [(50, 50, 3)], dotValue: 195)).isEmpty)
    }

    @Test func skinMaskRestrictsDetection() {
        var mask = [UInt8](repeating: 0, count: 100 * 100)
        for y in 0..<100 { for x in 0..<50 { mask[y * 100 + x] = 255 } }                // only the left half is skin
        let spots = SpotDetector.detect(Self.skin(dots: [(20, 50, 3), (80, 50, 3)]), skin: mask)
        #expect(spots.count == 1 && spots[0].center.x < 50)
    }

    @Test func degenerateInputsReturnNothing() {
        #expect(SpotDetector.detect(GrayImage(width: 2, height: 2, pixels: [0, 0, 0, 0])).isEmpty)
        #expect(SpotDetector.detect(Self.skin(), skin: [0, 1]).isEmpty)                  // wrong mask size
    }

    @Test func healingRemovesTheSpotButNotTheRestOfThePhoto() {
        let bg = CIImage(color: CIColor(red: 0.8, green: 0.65, blue: 0.55)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
        // dark dot at y-down (50, 40) -> CI y = 60
        let dot = CIImage(color: CIColor(red: 0.3, green: 0.2, blue: 0.2)).cropped(to: CGRect(x: 47, y: 57, width: 6, height: 6))
        let img = dot.composited(over: bg)
        let healed = HealOps.apply([SpotDetector.Spot(center: CGPoint(x: 50, y: 40), radius: 4, area: 28)], to: img)
        #expect(GeometryTests.rgb(healed, x: 50, y: 60)[0] > 180)                       // dot is gone (was ~77)
        #expect(GeometryTests.rgb(healed, x: 10, y: 10)[0] == GeometryTests.rgb(img, x: 10, y: 10)[0])
        #expect(HealOps.apply([], to: img).extent == img.extent)
    }

    // MARK: auto beauty
    @Test func looksAreUniqueAndDoSomething() {
        #expect(Set(AutoBeauty.looks.map(\.id)).count == AutoBeauty.looks.count)
        for l in AutoBeauty.looks { #expect(!l.skin.isIdentity || !l.face.isIdentity || !l.makeup.isIdentity, "\(l.id)") }
    }

    @Test func strengthZeroDoesNothingAndOneIsAsDesigned() {
        let l = AutoBeauty.looks[2]
        let off = AutoBeauty.scaled(l, strength: 0)
        #expect(off.skin.isIdentity && off.face.isIdentity && off.makeup.isIdentity)
        #expect(AutoBeauty.scaled(l, strength: 1) == l)
        #expect(AutoBeauty.scaled(l, strength: 7) == l)                                 // clamped
    }

    @Test func halfStrengthIsHalfTheValues() {
        let l = AutoBeauty.looks[2], half = AutoBeauty.scaled(l, strength: 0.5)
        #expect(abs(half.skin.smooth - l.skin.smooth / 2) < 1e-12 && abs(half.face.jawSlim - l.face.jawSlim / 2) < 1e-12 && abs(half.makeup.lipOpacity - l.makeup.lipOpacity / 2) < 1e-12)
        #expect(half.skin.texture == l.skin.texture)                                    // texture is a keep-detail knob, not a strength
    }

    @Test func looksSurviveJSON() throws {
        let data = try JSONEncoder().encode(AutoBeauty.looks)
        #expect(try JSONDecoder().decode([BeautyLook].self, from: data) == AutoBeauty.looks)
    }
}
