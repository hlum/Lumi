import Foundation

struct GrayImage: Equatable {
    let width: Int, height: Int
    let pixels: [UInt8]
    init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height)
        self.width = width; self.height = height; self.pixels = pixels
    }
    func row(_ y: Int) -> ArraySlice<UInt8> { pixels[y * width..<(y + 1) * width] }
}

/// Finds how many rows at the bottom of `top` repeat at the top of `bottom` (screenshot stitching).
enum OverlapFinder {
    /// Returns the overlap in rows, or nil when no convincing overlap exists. Translation-only registration.
    static func verticalOverlap(top: GrayImage, bottom: GrayImage, minRows: Int = 8, tolerance: Double = 4) -> Int? {
        guard top.width == bottom.width, minRows > 0 else { return nil }
        let maxRows = min(top.height, bottom.height) - 1
        guard maxRows >= minRows else { return nil }
        var best: (rows: Int, score: Double)?
        for k in stride(from: maxRows, through: minRows, by: -1) {
            let s = score(top: top, bottom: bottom, rows: k)
            if s <= tolerance, best == nil || s < best!.score - 0.5 { best = (k, s) }    // prefer the larger overlap on ties
            if s == 0 && best?.rows == k { break }
        }
        return best?.rows
    }

    /// Mean absolute difference of the last `rows` rows of top against the first `rows` of bottom.
    static func score(top: GrayImage, bottom: GrayImage, rows k: Int) -> Double {
        var sum = 0
        for i in 0..<k {
            let a = top.row(top.height - k + i), b = bottom.row(i)
            for (x, y) in zip(a, b) { sum += abs(Int(x) - Int(y)) }
        }
        return Double(sum) / Double(k * top.width)
    }

    /// Height of the stitched result.
    static func stitchedHeight(_ heights: [Int], overlaps: [Int]) -> Int {
        heights.reduce(0, +) - overlaps.reduce(0, +)
    }

    /// Splits a tall image into pages no taller than `pageHeight`.
    static func slices(totalHeight: Int, pageHeight: Int) -> [Range<Int>] {
        guard totalHeight > 0, pageHeight > 0 else { return [] }
        return stride(from: 0, to: totalHeight, by: pageHeight).map { $0..<min($0 + pageHeight, totalHeight) }
    }
}
