import CoreGraphics
import Foundation

/// Finds small dark blemishes (spots, pimples) on skin by comparing each pixel to its local mean.
enum SpotDetector {
    struct Spot: Equatable { var center: CGPoint; var radius: Double; var area: Int }

    /// `skin`: optional mask (same size, nonzero = skin). Coordinates are pixels, y-down.
    static func detect(_ img: GrayImage, skin: [UInt8]? = nil, window: Int = 15, threshold: Int = 14, minArea: Int = 3, maxArea: Int = 400) -> [Spot] {
        let w = img.width, h = img.height
        guard w > 2, h > 2, window >= 3, skin == nil || skin!.count == w * h else { return [] }
        // integral image for fast local means
        var integral = [Int](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h { var row = 0; for x in 0..<w { row += Int(img.pixels[y * w + x]); integral[(y + 1) * (w + 1) + x + 1] = integral[y * (w + 1) + x + 1] + row } }
        func mean(_ x: Int, _ y: Int) -> Double {
            let r = window / 2
            let x0 = max(0, x - r), x1 = min(w, x + r + 1), y0 = max(0, y - r), y1 = min(h, y + r + 1)
            let s = integral[y1 * (w + 1) + x1] - integral[y0 * (w + 1) + x1] - integral[y1 * (w + 1) + x0] + integral[y0 * (w + 1) + x0]
            return Double(s) / Double((x1 - x0) * (y1 - y0))
        }
        var flag = [Bool](repeating: false, count: w * h)
        for y in 0..<h { for x in 0..<w {
            if let skin, skin[y * w + x] == 0 { continue }
            if mean(x, y) - Double(img.pixels[y * w + x]) > Double(threshold) { flag[y * w + x] = true }
        } }
        // connected components
        var seen = [Bool](repeating: false, count: w * h), out: [Spot] = []
        for start in 0..<(w * h) where flag[start] && !seen[start] {
            var stack = [start], area = 0, sx = 0.0, sy = 0.0, minX = w, maxX = 0, minY = h, maxY = 0
            seen[start] = true
            while let i = stack.popLast() {
                let x = i % w, y = i / w
                area += 1; sx += Double(x); sy += Double(y)
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let j = ny * w + nx
                    if flag[j] && !seen[j] { seen[j] = true; stack.append(j) }
                }
            }
            let bw = maxX - minX + 1, bh = maxY - minY + 1
            let aspect = Double(max(bw, bh)) / Double(min(bw, bh))
            guard area >= minArea, area <= maxArea, aspect <= 2.5 else { continue }
            out.append(Spot(center: CGPoint(x: sx / Double(area) + 0.5, y: sy / Double(area) + 0.5), radius: (Double(area) / .pi).squareRoot() * 1.4 + 1, area: area))
        }
        return out.sorted { ($0.center.y, $0.center.x) < ($1.center.y, $1.center.x) }
    }
}
