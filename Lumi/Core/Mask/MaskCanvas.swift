import CoreImage
import Foundation

/// 8-bit single-channel mask (255 = selected). Codable so masks survive save and reopen.
struct MaskCanvas: Codable, Equatable {
    let width: Int
    let height: Int
    private(set) var pixels: [UInt8]

    init(width: Int, height: Int) {
        precondition(width > 0 && height > 0)
        self.width = width; self.height = height
        pixels = Array(repeating: 0, count: width * height)
    }

    subscript(x: Int, y: Int) -> UInt8 { pixels[y * width + x] }

    var isEmpty: Bool { !pixels.contains { $0 != 0 } }

    /// Round brush; `hardness` 0...1 (1 = hard edge). Erase lowers coverage, paint raises it.
    mutating func stamp(x: Double, y: Double, radius: Double, hardness: Double, erase: Bool) {
        guard radius > 0 else { return }
        let x0 = max(0, Int((x - radius).rounded(.down))), x1 = min(width - 1, Int((x + radius).rounded(.up)))
        let y0 = max(0, Int((y - radius).rounded(.down))), y1 = min(height - 1, Int((y + radius).rounded(.up)))
        guard x0 <= x1, y0 <= y1 else { return }
        let h = min(max(hardness, 0), 1)
        for py in y0...y1 { for px in x0...x1 {
            let d = ((Double(px) + 0.5 - x) * (Double(px) + 0.5 - x) + (Double(py) + 0.5 - y) * (Double(py) + 0.5 - y)).squareRoot() / radius
            guard d < 1 else { continue }
            let cover = d <= h ? 1.0 : (1 - d) / (1 - h)
            let v = UInt8((cover * 255).rounded())
            let i = py * width + px
            pixels[i] = erase ? (pixels[i] > v ? pixels[i] - v : 0) : max(pixels[i], v)
        } }
    }

    mutating func stroke(from a: (Double, Double), to b: (Double, Double), radius: Double, hardness: Double, erase: Bool) {
        let dist = ((b.0 - a.0) * (b.0 - a.0) + (b.1 - a.1) * (b.1 - a.1)).squareRoot()
        let step = max(radius / 4, 0.5)
        let n = max(1, Int((dist / step).rounded(.up)))
        for i in 0...n {
            let t = Double(i) / Double(n)
            stamp(x: a.0 + (b.0 - a.0) * t, y: a.1 + (b.1 - a.1) * t, radius: radius, hardness: hardness, erase: erase)
        }
    }

    /// Box select: fills (or clears) the rect, clamped to the canvas.
    mutating func fill(rect r: CGRect, erase: Bool = false) {
        let x0 = max(0, Int(r.minX.rounded(.down))), x1 = min(width, Int(r.maxX.rounded(.up)))
        let y0 = max(0, Int(r.minY.rounded(.down))), y1 = min(height, Int(r.maxY.rounded(.up)))
        guard x0 < x1, y0 < y1 else { return }
        for y in y0..<y1 { for x in x0..<x1 { pixels[y * width + x] = erase ? 0 : 255 } }
    }

    mutating func invert() { pixels = pixels.map { 255 - $0 } }

    mutating func union(_ other: MaskCanvas) {
        precondition(other.width == width && other.height == height)
        for i in pixels.indices { pixels[i] = max(pixels[i], other.pixels[i]) }
    }

    var ciImage: CIImage {
        CIImage(bitmapData: Data(pixels), bytesPerRow: width, size: CGSize(width: width, height: height),
                format: .L8, colorSpace: nil)
    }
}

extension MaskCanvas {
    /// RGBA overlay (premultiplied): the mask as a translucent color, for showing a selection.
    func tintedImage(red: Double = 1, green: Double = 0.2, blue: Double = 0.2, opacity: Double = 0.5) -> CGImage? {
        guard !isEmpty else { return nil }
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<pixels.count {
            let a = Double(pixels[i]) / 255 * opacity
            rgba[i * 4] = UInt8((red * a * 255).rounded()); rgba[i * 4 + 1] = UInt8((green * a * 255).rounded())
            rgba[i * 4 + 2] = UInt8((blue * a * 255).rounded()); rgba[i * 4 + 3] = UInt8((a * 255).rounded())
        }
        return rgba.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
    }
}
