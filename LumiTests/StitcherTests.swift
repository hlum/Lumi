import CoreImage
import Foundation
import Testing
@testable import Lumi

struct StitcherTests {
    /// A page of 360 x `h` with rows that all differ, so a repeated stretch can be found exactly.
    private func page(height h: Int, width w: Int = 360) -> CIImage {
        let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        for y in 0..<h {
            for block in 0..<12 {
                let g = CGFloat((y * 37 + block * 91 + (y / 3) * 17) % 255) / 255
                c.setFillColor(gray: g, alpha: 1)
                c.fill(CGRect(x: CGFloat(block * w / 12), y: CGFloat(h - 1 - y), width: CGFloat(w / 12), height: 1))            // y = row from the top
            }
        }
        return CIImage(cgImage: c.makeImage()!)
    }
    /// Rows [from, to) from the top of the page, as their own picture.
    private func window(_ p: CIImage, from: Int, to: Int) -> CIImage {
        let h = Int(p.extent.height)
        return p.cropped(to: CGRect(x: 0, y: CGFloat(h - to), width: p.extent.width, height: CGFloat(to - from))).transformed(by: CGAffineTransform(translationX: 0, y: CGFloat(-(h - to))))
    }
    private func rowPixel(_ i: CIImage, row: Int, x: Int = 10) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 4)
        CIContext().render(i, toBitmap: &b, rowBytes: 4, bounds: CGRect(x: x, y: Int(i.extent.height) - 1 - row, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return b
    }

    @Test func screenshotsWithARepeatedStretchAreJoinedWithoutTheRepeat() throws {
        let tall = page(height: 1500)
        let a = window(tall, from: 0, to: 600), b = window(tall, from: 400, to: 1000), c = window(tall, from: 800, to: 1400)
        let found = Stitcher.overlaps([a, b, c], direction: .vertical)
        #expect(found.count == 2 && found.allSatisfy { abs($0 - 200) <= 6 }, "\(found)")
        let out = try #require(Stitcher.stitch([a, b, c], direction: .vertical, cutOverlap: true))
        #expect(abs(out.extent.height - 1400) <= 12 && out.extent.width == 360)
        // a row from the middle of the second picture is where it would be in the original page
        let original = rowPixel(tall, row: 700), joined = rowPixel(out, row: 700)
        #expect(abs(Int(original[0]) - Int(joined[0])) < 12)
    }

    @Test func withoutCuttingEverythingIsKeptEndToEnd() throws {
        let a = window(page(height: 800), from: 0, to: 300), b = window(page(height: 800), from: 300, to: 600)
        let out = try #require(Stitcher.stitch([a, b], direction: .vertical, cutOverlap: false))
        #expect(out.extent.height == 600)
    }

    @Test func unrelatedPicturesAreNotCut() {
        let a = page(height: 400), b = CIImage(color: CIColor(red: 0.2, green: 0.9, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 360, height: 400))
        #expect(Stitcher.overlaps([a, b], direction: .vertical) == [0])
    }

    @Test func differentWidthsAreScaledToTheFirst() throws {
        let a = page(height: 300, width: 360), b = page(height: 300, width: 720)
        let out = try #require(Stitcher.stitch([a, b], direction: .vertical, cutOverlap: false))
        #expect(out.extent.width == 360 && abs(out.extent.height - (300 + 150)) < 1)
    }

    @Test func sideBySideJoinsLeftToRight() throws {
        let a = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 200))
        let b = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 0, y: 0, width: 150, height: 200))
        let out = try #require(Stitcher.stitch([a, b], direction: .horizontal, cutOverlap: false))
        #expect(out.extent.size == CGSize(width: 250, height: 200))
        #expect(rowPixel(out, row: 100, x: 20)[0] > 200 && rowPixel(out, row: 100, x: 200)[2] > 200)
        #expect(Stitcher.stitch([], direction: .vertical, cutOverlap: true) == nil)
        #expect(Stitcher.overlaps([a], direction: .vertical).isEmpty)
    }
}
