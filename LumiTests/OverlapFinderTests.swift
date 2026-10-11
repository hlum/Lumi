import Foundation
import Testing
@testable import Lumi

struct OverlapFinderTests {
    /// A deterministic "page": row y is a pseudo-random but non-repeating pattern.
    static func page(rows: Range<Int>, width: Int = 16) -> GrayImage {
        var px: [UInt8] = []
        for y in rows { for x in 0..<width { px.append(UInt8(truncatingIfNeeded: (y * 37 + x * 11 + (y * y) % 29) * 7)) } }
        return GrayImage(width: width, height: rows.count, pixels: px)
    }

    @Test func findsExactOverlap() {
        let top = Self.page(rows: 0..<100), bottom = Self.page(rows: 70..<170)       // 30 shared rows
        #expect(OverlapFinder.verticalOverlap(top: top, bottom: bottom) == 30)
    }

    @Test func noOverlapReturnsNil() {
        #expect(OverlapFinder.verticalOverlap(top: Self.page(rows: 0..<60), bottom: Self.page(rows: 500..<560)) == nil)
    }

    @Test func toleratesSmallNoise() {
        let top = Self.page(rows: 0..<100)
        var b = Self.page(rows: 70..<170).pixels
        for i in stride(from: 0, to: b.count, by: 5) { b[i] = b[i] &+ 2 }
        #expect(OverlapFinder.verticalOverlap(top: top, bottom: GrayImage(width: 16, height: 100, pixels: b)) == 30)
    }

    @Test func mismatchedWidthsAndTinyImagesAreNil() {
        #expect(OverlapFinder.verticalOverlap(top: Self.page(rows: 0..<50, width: 8), bottom: Self.page(rows: 0..<50, width: 16)) == nil)
        #expect(OverlapFinder.verticalOverlap(top: Self.page(rows: 0..<5), bottom: Self.page(rows: 0..<5)) == nil)
    }

    @Test func identicalPagesDoNotMatchFullHeightOrCrash() {
        let p = Self.page(rows: 0..<40)
        _ = OverlapFinder.verticalOverlap(top: p, bottom: p)
    }

    @Test func scoreIsZeroForExactMatchAndPositiveOtherwise() {
        let top = Self.page(rows: 0..<100), bottom = Self.page(rows: 70..<170)
        #expect(OverlapFinder.score(top: top, bottom: bottom, rows: 30) == 0)
        #expect(OverlapFinder.score(top: top, bottom: bottom, rows: 29) > 0)
    }

    @Test func stitchedHeightSubtractsOverlaps() {
        #expect(OverlapFinder.stitchedHeight([100, 100, 100], overlaps: [30, 20]) == 250)
        #expect(OverlapFinder.stitchedHeight([], overlaps: []) == 0)
    }

    @Test func slicesCoverTheWholeImageWithoutGaps() {
        let s = OverlapFinder.slices(totalHeight: 2500, pageHeight: 1000)
        #expect(s == [0..<1000, 1000..<2000, 2000..<2500])
        #expect(OverlapFinder.slices(totalHeight: 0, pageHeight: 10).isEmpty && OverlapFinder.slices(totalHeight: 10, pageHeight: 0).isEmpty)
        #expect(OverlapFinder.slices(totalHeight: 10, pageHeight: 100) == [0..<10])
    }
}
