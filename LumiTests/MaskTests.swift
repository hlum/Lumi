import CoreImage
import Foundation
import Testing
@testable import Lumi

struct MaskTests {
    @Test func startsEmpty() { #expect(MaskCanvas(width: 8, height: 8).isEmpty) }

    @Test func hardStampFillsCircleOnly() {
        var m = MaskCanvas(width: 20, height: 20)
        m.stamp(x: 10, y: 10, radius: 4, hardness: 1, erase: false)
        #expect(m[10, 10] == 255)
        #expect(m[0, 0] == 0 && m[19, 19] == 0)
    }

    @Test func softBrushFallsOffFromCenter() {
        var m = MaskCanvas(width: 40, height: 40)
        m.stamp(x: 20, y: 20, radius: 10, hardness: 0, erase: false)
        #expect(m[20, 20] > m[24, 20] && m[24, 20] > m[28, 20])
    }

    @Test func eraseClearsAndNeverUnderflows() {
        var m = MaskCanvas(width: 20, height: 20)
        m.stamp(x: 10, y: 10, radius: 5, hardness: 1, erase: false)
        m.stamp(x: 10, y: 10, radius: 8, hardness: 1, erase: true)
        #expect(m.isEmpty)
    }

    @Test func paintingNeverLowersCoverage() {
        var m = MaskCanvas(width: 20, height: 20)
        m.stamp(x: 10, y: 10, radius: 5, hardness: 1, erase: false)
        m.stamp(x: 10, y: 10, radius: 5, hardness: 0, erase: false)
        #expect(m[10, 10] == 255)
    }

    @Test func stampOffCanvasDoesNotCrash() {
        var m = MaskCanvas(width: 10, height: 10)
        m.stamp(x: -50, y: -50, radius: 5, hardness: 1, erase: false)
        m.stamp(x: 500, y: 500, radius: 5, hardness: 1, erase: false)
        m.stamp(x: 5, y: 5, radius: 0, hardness: 1, erase: false)
        #expect(m.isEmpty)
    }

    @Test func strokeIsContinuousBetweenPoints() {
        var m = MaskCanvas(width: 100, height: 20)
        m.stroke(from: (5, 10), to: (95, 10), radius: 3, hardness: 1, erase: false)
        #expect((5...95).allSatisfy { m[$0, 10] == 255 })
    }

    @Test func zeroLengthStrokeStillPaintsDot() {
        var m = MaskCanvas(width: 20, height: 20)
        m.stroke(from: (10, 10), to: (10, 10), radius: 3, hardness: 1, erase: false)
        #expect(m[10, 10] == 255)
    }

    @Test func boxSelectFillsAndClamps() {
        var m = MaskCanvas(width: 10, height: 10)
        m.fill(rect: CGRect(x: -5, y: 2, width: 10, height: 3))
        #expect(m[0, 2] == 255 && m[4, 4] == 255 && m[5, 2] == 0 && m[0, 5] == 0)
        m.fill(rect: CGRect(x: 0, y: 0, width: 10, height: 10), erase: true)
        #expect(m.isEmpty)
        m.fill(rect: CGRect(x: 50, y: 50, width: 5, height: 5))   // fully outside
        #expect(m.isEmpty)
    }

    @Test func invertTwiceIsIdentity() {
        var m = MaskCanvas(width: 10, height: 10)
        m.stamp(x: 5, y: 5, radius: 3, hardness: 0.5, erase: false)
        let orig = m
        m.invert(); #expect(m != orig)
        m.invert(); #expect(m == orig)
    }

    @Test func unionTakesMax() {
        var a = MaskCanvas(width: 10, height: 10), b = a
        a.fill(rect: CGRect(x: 0, y: 0, width: 3, height: 10))
        b.fill(rect: CGRect(x: 7, y: 0, width: 3, height: 10))
        a.union(b)
        #expect(a[1, 5] == 255 && a[8, 5] == 255 && a[5, 5] == 0)
    }

    @Test func ciImageMatchesSize() {
        let m = MaskCanvas(width: 12, height: 7)
        #expect(m.ciImage.extent == CGRect(x: 0, y: 0, width: 12, height: 7))
    }

    @Test func masksSurviveSerialization() throws {
        var store = MaskStore()
        var m = MaskCanvas(width: 16, height: 16)
        m.stamp(x: 8, y: 8, radius: 4, hardness: 0.3, erase: false)
        store["skin"] = m
        let back = try JSONDecoder().decode(MaskStore.self, from: JSONEncoder().encode(store))
        #expect(back == store && back["skin"] == m && back["missing"] == nil)
    }

    @Test func storeRemove() {
        var s = MaskStore(); s["a"] = MaskCanvas(width: 2, height: 2)
        s.remove("a")
        #expect(s["a"] == nil)
    }
}
